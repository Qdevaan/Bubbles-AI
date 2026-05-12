# Batch 2 — Gamification HTTP Routes (v5 port) — Design

**Date:** 2026-05-12 • **Author:** backend • **Status:** approved, ready for plan

Part of the v2→v5 port (6-batch plan). Batch 1 (entity routes) is done & merged. This batch ports the gamification HTTP surface from `legacy/server_v2/app/routes/gamification.py` into Bubbles Brain API v5, improving the logic rather than copying v2's fire-and-forget Supabase service verbatim.

---

## 1. Scope

**In scope — 6 endpoints:**

| Method & path | Purpose |
|---|---|
| `GET /v1/gamification/{user_id}` | Full XP/level/streak profile + badges + recent XP |
| `GET /v1/quests/{user_id}` | Today's daily quests; auto-assigns 3 random if none assigned today |
| `GET /v1/rewards/{user_id}` | Reward catalog enriched with caller's balance + per-reward affordability/ownership |
| `POST /v1/rewards/{user_id}/redeem` | Redeem a reward by id (atomic XP deduction) |
| `GET /v1/leaderboard?period=&limit=` | Global leaderboard for a period + caller's rank |
| `POST /v1/leaderboard/{user_id}/opt_in` | Toggle leaderboard visibility |

**Out of scope (follow-ups — list in §9):**

- `POST /quests/{uid}/{uqid}/answer` and `POST /quests/{uid}/{uqid}/attach_session` (question_set / conversation mission types — the heaviest v2 logic) — own later batch.
- Streak-milestone XP bursts (3/7/14/30/60/100/365-day), daily XP cap (500), first-action-today bonus — land when the XP-awarding worker hooks land.
- Achievement auto-detection worker job (the thing that writes `user_achievements` rows) — own later batch.
- Profile `stats{}` aggregate block from v2 — add only if the Flutter client needs it.

---

## 2. New DB tables — Alembic migration `0003`

These three tables exist in the live Supabase DB (`Documentation/db_schema.sql`) but are not yet modelled in v5. Column names/types must match the prod DDL so v5 stays compatible with the live database. The migration's `upgrade()` is `CREATE TABLE IF NOT EXISTS` (no-op against the existing prod schema, consistent with how `0001` baseline behaves); `downgrade()` drops all three in reverse FK order.

```sql
CREATE TABLE IF NOT EXISTS xp_transactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount integer NOT NULL,
    source_type text NOT NULL,
    source_id text,
    description text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS xp_transactions_dedup_idx
    ON xp_transactions (user_id, source_type, source_id) WHERE source_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS xp_transactions_user_recent_idx
    ON xp_transactions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS xp_transactions_period_idx
    ON xp_transactions (created_at, user_id) WHERE amount > 0;

CREATE TABLE IF NOT EXISTS achievements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text UNIQUE,
    title text NOT NULL,
    description text,
    icon text DEFAULT '🏆',
    category text DEFAULT 'general',
    criteria_type text NOT NULL,
    criteria_value integer NOT NULL,
    xp_reward integer DEFAULT 0,
    tier text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_achievements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    achievement_id uuid NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
    awarded_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, achievement_id)
);
```

`downgrade()`: `DROP TABLE IF EXISTS user_achievements; DROP TABLE IF EXISTS achievements; DROP TABLE IF EXISTS xp_transactions;` (indexes drop with their table).

Also: append these tables to `server/tests/integration/fixtures/baseline.sql` (use `gen_random_uuid()` to match that file's style); add `user_achievements, achievements, xp_transactions` to the integration `conftest.py` teardown `DROP TABLE IF EXISTS` list — placed **before** `user_gamification`.

---

## 3. Models — `server/src/bubbles/db/models.py`

Frozen dataclasses with `slots=True`, matching the existing gamification models:

- `XpTransaction(id: UUID, user_id: UUID, amount: int, source_type: str, source_id: str | None, description: str | None, created_at: datetime)`
- `Achievement(id: UUID, code: str | None, title: str, description: str | None, icon: str, category: str, criteria_type: str, criteria_value: int, xp_reward: int, tier: str | None, created_at: datetime)`
- `UserAchievement(id: UUID, user_id: UUID, achievement_id: UUID, awarded_at: datetime)`
- `UserBadge(achievement: Achievement, awarded_at: datetime)` — view model returned by `achievements_repo.list_for_user`

---

## 4. Pure level helpers — `server/src/bubbles/core/gamification.py` (new, no DB)

Ported from v2's formula `cumulative_xp(level) = 50·level·(level−1)`:

```python
def xp_for_level(level: int) -> int: ...          # 50 * level * (level - 1)
def level_for_xp(total_xp: int) -> int: ...       # floor((1 + sqrt(1 + 4*xp/50)) / 2), min 1
@dataclass(frozen=True, slots=True)
class LevelProgress:
    level: int
    xp_into_level: int          # total_xp - xp_for_level(level)
    xp_to_next_level: int       # xp_for_level(level+1) - total_xp
    progress_pct: float         # xp_into_level / (xp_for_level(level+1) - xp_for_level(level)), in [0, 1)
def level_progress(total_xp: int) -> LevelProgress: ...
```

Edge cases the unit test must cover: `total_xp=0` → level 1, `xp_into_level=0`, `progress_pct=0.0`; exact level boundary (`total_xp == xp_for_level(n)`) → level `n`, `progress_pct=0.0`; negative `total_xp` clamps to level 1. `progress_pct` is always `0 <= pct < 1`.

---

## 5. Repos

### 5.1 `server/src/bubbles/db/repo/xp.py` (new)

- `async def record(conn, *, user_id: UUID, amount: int, source_type: str, source_id: str | None = None, description: str | None = None) -> XpTransaction | None`
  `INSERT INTO xp_transactions (user_id, amount, source_type, source_id, description) VALUES (...) ON CONFLICT (user_id, source_type, source_id) DO NOTHING RETURNING <cols>`. Returns `None` when the row was deduped (already awarded). Note: the partial unique index only covers `source_id IS NOT NULL`, so `ON CONFLICT` never fires when `source_id` is `None` — those always insert. Raise `ValueError` if `amount` is negative (XP awards are non-negative; spend is tracked separately via `xp_spent`).
- `async def recent(conn, *, user_id: UUID, limit: int = 20) -> list[XpTransaction]` — `WHERE user_id=$1 ORDER BY created_at DESC LIMIT $2`.
- `async def sum_since(conn, *, user_id: UUID, since: datetime) -> int` — `SELECT COALESCE(SUM(amount), 0)::int FROM xp_transactions WHERE user_id=$1 AND amount > 0 AND created_at >= $2`.

### 5.2 `server/src/bubbles/db/repo/achievements.py` (new)

- `async def list_for_user(conn, *, user_id: UUID) -> list[UserBadge]` — returns each achievement the user has earned paired with the award timestamp (`UserBadge` is a frozen dataclass in `db/models.py`: `achievement: Achievement, awarded_at: datetime`).
  `SELECT a.<achievement cols>, ua.awarded_at FROM user_achievements ua JOIN achievements a ON a.id = ua.achievement_id WHERE ua.user_id=$1 ORDER BY ua.awarded_at DESC`.

### 5.3 `server/src/bubbles/db/repo/gamification.py` (extend)

- **`add_xp`** — extend signature to `add_xp(conn, *, user_id, amount, source_type: str = "manual", source_id: str | None = None, description: str | None = None) -> UserGamification`. New behaviour: first call `xp.record(conn, user_id=..., amount=..., source_type=..., source_id=..., description=...)`; if it returns `None` (deduped), **do not** bump `user_gamification` — return `get_or_init_gamification(conn, user_id)` unchanged. Otherwise proceed with the existing `INSERT ... ON CONFLICT DO UPDATE` total-XP bump. Keeps `amount < 0 → ValueError`. Existing callers (none yet beyond tests) keep working via the default `source_type`.
- **`get_or_assign_daily_quests`** — `async def get_or_assign_daily_quests(conn, *, user_id: UUID, on_date: date, n: int = 3) -> list[UserQuest]`. If `list_user_quests(conn, user_id=user_id, on_date=on_date)` is non-empty, return it. Else: `SELECT <quest_def_cols> FROM quest_definitions WHERE is_active = true ORDER BY random() LIMIT $1` (n); for each def call `assign_quest(conn, user_id=user_id, quest_id=def.id, target=def.target, assigned_date=on_date)`; return the assigned `UserQuest`s. Runs inside the caller's transaction (no commit here). If there are zero active defs, returns `[]` (the seed_quests job normally populates them).
- **`leaderboard_period`** — `async def leaderboard_period(conn, *, since: datetime, limit: int = 25) -> list[asyncpg.Record]`:
  ```sql
  SELECT t.user_id, COALESCE(SUM(t.amount), 0)::int AS xp, g.level, g.current_streak
  FROM xp_transactions t
  JOIN user_gamification g ON g.user_id = t.user_id AND g.leaderboard_opt_in = true
  WHERE t.amount > 0 AND t.created_at >= $1
  GROUP BY t.user_id, g.level, g.current_streak
  ORDER BY xp DESC
  LIMIT $2
  ```
- **`rank_all_time`** — `async def rank_all_time(conn, *, user_id: UUID) -> int | None`: caller's 1-based rank among opted-in users by `total_xp`. Returns `None` if the caller is not opted in.
  ```sql
  SELECT rnk FROM (
    SELECT user_id, RANK() OVER (ORDER BY total_xp DESC) AS rnk
    FROM user_gamification WHERE leaderboard_opt_in = true
  ) s WHERE s.user_id = $1
  ```
- **`rank_period`** — `async def rank_period(conn, *, user_id: UUID, since: datetime) -> int | None`: same idea over the period aggregate.
  ```sql
  SELECT rnk FROM (
    SELECT t.user_id, RANK() OVER (ORDER BY COALESCE(SUM(t.amount),0) DESC) AS rnk
    FROM xp_transactions t
    JOIN user_gamification g ON g.user_id = t.user_id AND g.leaderboard_opt_in = true
    WHERE t.amount > 0 AND t.created_at >= $2
    GROUP BY t.user_id
  ) s WHERE s.user_id = $1
  ```
- `leaderboard_top`, `redeem_reward`, `list_active_rewards`, `set_leaderboard_opt_in`, `get_or_init_gamification`, `list_user_quests`, `assign_quest` — already exist; reuse unchanged.
- One small helper for the rewards endpoint: `async def owned_reward_ids(conn, *, user_id: UUID) -> set[UUID]` — `SELECT reward_id FROM user_rewards WHERE user_id=$1`.

---

## 6. Routes — `server/src/bubbles/api/v1/gamification.py` (new)

`router = APIRouter(tags=["gamification"])`; register in `server/src/bubbles/api/router.py` (`from bubbles.api.v1.gamification import router as gamification_router` + `v1_router.include_router(gamification_router)`).

Every `{user_id}`-path route: `require_ownership(user, str(user_id))` immediately after entry. The leaderboard GET has no path user — it uses `UUID(user.id)` as the caller. Use `transaction(pool)` for read-only handlers and `UnitOfWork(pool)` for writes (matches existing module conventions). No upstream calls anywhere → no `UpstreamUnavailable`.

### 6.1 `GET /v1/gamification/{user_id}` → `GamificationProfile`

```
async with transaction(pool) as conn:
    g = await gamification_repo.get_or_init_gamification(conn, user_id)
    badges = await achievements_repo.list_for_user(conn, user_id=user_id)
    recent = await xp_repo.recent(conn, user_id=user_id, limit=20)
lp = level_progress(g.total_xp)
return GamificationProfile(user_id=..., xp=g.total_xp, level=lp.level,
    xp_into_level=lp.xp_into_level, xp_to_next_level=lp.xp_to_next_level,
    xp_progress_pct=lp.progress_pct, current_streak=g.current_streak,
    longest_streak=g.longest_streak, streak_freezes=g.streak_freezes,
    last_active_date=g.last_active_date,
    badges=[AchievementOut(...) for a in badges],
    recent_xp=[XpEntryOut(...) for t in recent])
```

### 6.2 `GET /v1/quests/{user_id}` → `DailyQuestsResponse`

```
today = datetime.now(timezone.utc).date()
async with transaction(pool) as conn:        # transaction so get_or_assign's inserts commit
    await gamification_repo.get_or_init_gamification(conn, user_id)   # ensure row exists
    quests = await gamification_repo.get_or_assign_daily_quests(conn, user_id=user_id, on_date=today)
reset_at = datetime(today.year, today.month, today.day, tzinfo=timezone.utc) + timedelta(days=1)
completed = sum(1 for q in quests if q.is_completed)
return DailyQuestsResponse(quests=[UserQuestOut(...) for q in quests],
    daily_reset_at=reset_at, total_completed_today=completed, total_quests_today=len(quests))
```

(`transaction()` here both reads and writes — that's fine; `get_or_assign_daily_quests` only INSERTs when nothing's assigned yet.)

### 6.3 `GET /v1/rewards/{user_id}` → `RewardCatalogResponse`

```
async with transaction(pool) as conn:
    g = await gamification_repo.get_or_init_gamification(conn, user_id)
    rewards = await gamification_repo.list_active_rewards(conn)
    owned = await gamification_repo.owned_reward_ids(conn, user_id=user_id)
balance = g.total_xp - g.xp_spent
return RewardCatalogResponse(balance_xp=balance, rewards=[
    RewardOut(id=r.id, title=r.title, description=r.description, icon=r.icon,
        category=r.category, cost_xp=r.cost_xp, sort_order=r.sort_order,
        affordable=(balance >= r.cost_xp), owned=(r.id in owned)) for r in rewards])
```

### 6.4 `POST /v1/rewards/{user_id}/redeem` — body `RewardRedeemRequest{reward_id: UUID}` → `RewardRedeemResponse`

```
async with UnitOfWork(pool) as uow:
    try:
        ur = await gamification_repo.redeem_reward(uow.conn, user_id=user_id, reward_id=body.reward_id)
    except ValueError as e:
        raise BadRequest(str(e))          # "reward not available" | "insufficient XP"
    g = await gamification_repo.get_or_init_gamification(uow.conn, user_id)
return RewardRedeemResponse(reward_id=ur.reward_id, cost_xp=ur.cost_xp,
    unlocked_at=ur.unlocked_at, balance_xp=g.total_xp - g.xp_spent)
```

### 6.5 `GET /v1/leaderboard` → `LeaderboardResponse`

Query params: `period: Literal["all","daily","weekly","monthly"] = "all"` (FastAPI validates via `Query`), `limit: int = Query(25, ge=1, le=100)`.

```
me_id = UUID(user.id)
now = datetime.now(timezone.utc)
since = {"daily": <00:00 UTC today>, "weekly": now - 7d, "monthly": now - 30d}.get(period)
async with transaction(pool) as conn:
    if period == "all":
        rows = await gamification_repo.leaderboard_top(conn, limit=limit)
        my_rank = await gamification_repo.rank_all_time(conn, user_id=me_id)
        my_g = await gamification_repo.get_or_init_gamification(conn, me_id)
        my_xp = my_g.total_xp
        entries = [LeaderboardEntry(user_id=r["user_id"], xp=r["total_xp"], level=r["level"],
            current_streak=r["current_streak"], rank=i + 1) for i, r in enumerate(rows)]
    else:
        rows = await gamification_repo.leaderboard_period(conn, since=since, limit=limit)
        my_rank = await gamification_repo.rank_period(conn, user_id=me_id, since=since)
        my_xp = await xp_repo.sum_since(conn, user_id=me_id, since=since)
        entries = [LeaderboardEntry(user_id=r["user_id"], xp=r["xp"], level=r["level"],
            current_streak=r["current_streak"], rank=i + 1) for i, r in enumerate(rows)]
return LeaderboardResponse(period=period, entries=entries,
    me=LeaderboardMe(rank=my_rank, xp=my_xp))
```

`<00:00 UTC today>` = `datetime(now.year, now.month, now.day, tzinfo=timezone.utc)`. Note: `rank` in `entries` is the position within the returned page (1..len); `me.rank` is the true global rank from the window query (may exceed `limit`), or `None` if the caller is not opted in.

### 6.6 `POST /v1/leaderboard/{user_id}/opt_in` — body `OptInRequest{opt_in: bool}` → `OptInResponse{user_id, leaderboard_opt_in}`

```
async with UnitOfWork(pool) as uow:
    g = await gamification_repo.set_leaderboard_opt_in(uow.conn, user_id=user_id, opt_in=body.opt_in)
return OptInResponse(user_id=user_id, leaderboard_opt_in=g.leaderboard_opt_in)
```

---

## 7. Schemas — `server/src/bubbles/api/v1/_schemas.py` (append a "gamification" section)

All extend `_Base` (`extra="forbid"`, `str_strip_whitespace=True`). Request bodies likewise.

- `AchievementOut(id: UUID, code: str | None, title: str, description: str | None, icon: str, category: str, tier: str | None, awarded_at: datetime)` — built from a `UserBadge` (`awarded_at` from `user_achievements`, the rest from the joined `achievements` row).
- `XpEntryOut(amount: int, source_type: str, description: str | None, created_at: datetime)`
- `GamificationProfile(user_id: UUID, xp: int, level: int, xp_into_level: int, xp_to_next_level: int, xp_progress_pct: float, current_streak: int, longest_streak: int, streak_freezes: int, last_active_date: date | None, badges: list[AchievementOut], recent_xp: list[XpEntryOut])`
- `UserQuestOut(id: UUID, quest_id: UUID, progress: int, target: int, is_completed: bool, assigned_date: date, completed_at: datetime | None)` — (drop `xp_awarded`/`user_id`/`created_at` from the wire shape; YAGNI for the client)
- `DailyQuestsResponse(quests: list[UserQuestOut], daily_reset_at: datetime, total_completed_today: int, total_quests_today: int)`
- `RewardOut(id: UUID, title: str, description: str | None, icon: str, category: str, cost_xp: int, sort_order: int, affordable: bool, owned: bool)`
- `RewardCatalogResponse(balance_xp: int, rewards: list[RewardOut])`
- `RewardRedeemRequest(reward_id: UUID)`
- `RewardRedeemResponse(reward_id: UUID, cost_xp: int, unlocked_at: datetime, balance_xp: int)`
- `LeaderboardEntry(user_id: UUID, xp: int, level: int, current_streak: int, rank: int)`
- `LeaderboardMe(rank: int | None, xp: int)`
- `LeaderboardResponse(period: Literal["all","daily","weekly","monthly"], entries: list[LeaderboardEntry], me: LeaderboardMe)`
- `OptInRequest(opt_in: bool)`
- `OptInResponse(user_id: UUID, leaderboard_opt_in: bool)`

(`datetime`, `date`, `Literal`, `UUID` already imported in `_schemas.py` from Batch 1; add any that aren't.)

---

## 8. Errors

- Path `user_id` ≠ JWT subject → `Forbidden` via existing `require_ownership` (yields the standard `{error:{code,message,request_id}}` envelope).
- `redeem_reward` raising `ValueError("reward not available")` or `ValueError("insufficient XP")` → `BadRequest(str(e))` (HTTP 400). Both are client-correctable, so `BadRequest` not `Forbidden`.
- Missing `user_gamification` row → never an error; `get_or_init_gamification` always creates it.
- No LLM/Redis/external calls in this batch → no `UpstreamUnavailable` paths.
- `period` outside the literal set → FastAPI 422 (automatic from the `Literal` query type). `limit` out of `[1,100]` → 422.

---

## 9. Known gaps / follow-ups (note in the comparison-review doc §5 after this batch lands)

- Quest mission types `answer` (question_set) + `attach_session` (conversation) — `POST /quests/{uid}/{uqid}/answer`, `POST /quests/{uid}/{uqid}/attach_session` not ported; own later batch.
- `add_xp` does not yet apply v2's automated daily XP cap (500), streak-milestone bursts, or first-action-today bonus — to be added when the session/consultant XP-award worker hooks land. The idempotency-on-`source_id` mechanism is in place now.
- No worker job populates `user_achievements` yet (achievement auto-detection) — `badges[]` will be empty until that batch lands. `seed_quests` already seeds `quest_definitions`; a parallel `seed_achievements` + a detection job are follow-ups.
- Profile `stats{}` block from v2 (sessions count, consultant QAs, mistakes resolved, etc.) — omitted; add if the Flutter client needs it.
- Streak bookkeeping (incrementing `current_streak`/`longest_streak`/`streak_freezes` on activity) — the fields exist and are read; the *writer* lives in the same future XP-award worker batch.

---

## 10. Testing

**Unit** (`server/tests/`, runs in the local `make test` gate):
- `test_core_gamification.py` — `xp_for_level`, `level_for_xp`, `level_progress`: xp=0→L1/0/0.0; level boundaries; large xp; negative xp clamps; `progress_pct ∈ [0,1)` invariant across a sweep.

**Integration** (`server/tests/integration/`, `pytestmark = pytest.mark.integration`, module-level `_skip_if_no_docker()` — auto-skips locally, runs in CI with `RUN_INTEGRATION=1`):
- `test_repo_xp.py` — `record` inserts; `record` with same `(user_id, source_type, source_id)` returns `None` the 2nd time; `record` with `source_id=None` always inserts; `recent` newest-first; `sum_since` only counts positive amounts ≥ since.
- `test_repo_achievements.py` — seed an `achievements` row + a `user_achievements` row; `list_for_user` returns it with the right `awarded_at`; empty for a fresh user.
- `test_repo_gamification.py` (extend) — `get_or_assign_daily_quests` assigns N on first call, returns the *same* rows on a 2nd call same day, assigns fresh on a later date; `add_xp` with a `source_id` bumps total once, is a no-op the 2nd time; `leaderboard_period` / `rank_period` / `rank_all_time` against a couple of opted-in users with mixed XP and dates; `owned_reward_ids`.
- `test_routes_gamification.py` — for each of the 6 endpoints, using the existing `app.dependency_overrides[get_pool]` + `current_user` pattern and `httpx.AsyncClient(transport=ASGITransport(...))`:
  - 403 when path `user_id` ≠ JWT subject (all 5 path-scoped routes).
  - profile: fresh user → level 1, empty badges, empty recent_xp; after `add_xp` + a seeded `user_achievements` → reflected.
  - quests: first GET assigns ≤3 (seed ≥3 `quest_definitions` in the test), 2nd GET returns the same ids; `daily_reset_at` is the next UTC midnight; `total_*` counts correct.
  - rewards: seed 2 `rewards` (one cheap, one dear) + redeem one → catalog shows `owned=true` for it, `affordable` reflects balance.
  - redeem: happy path returns updated `balance_xp`; redeeming when balance < cost → 400 with "insufficient XP"; unknown/inactive reward → 400 "reward not available".
  - leaderboard: `period=all` orders by `total_xp`, page `rank` is 1..n, `me.rank` set when opted in / `None` when not; `period=weekly` only counts `xp_transactions` within 7d; bad `period` → 422.
  - opt_in: toggles the flag, response echoes it; flips back.
- baseline.sql: add `xp_transactions`, `achievements`, `user_achievements`. conftest teardown: prepend their `DROP TABLE IF EXISTS` before `user_gamification`.

**Local gate** (no Docker on the dev box): `cd server && uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest` — must be green; integration suites collect-skip locally and run in CI.

---

## 11. File summary

| Action | Path |
|---|---|
| Create | `server/alembic/versions/2026_05_12_0003_gamification_tables.py` |
| Create | `server/src/bubbles/core/gamification.py` |
| Create | `server/src/bubbles/db/repo/xp.py` |
| Create | `server/src/bubbles/db/repo/achievements.py` |
| Create | `server/src/bubbles/api/v1/gamification.py` |
| Modify | `server/src/bubbles/db/models.py` (3 new dataclasses + `UserBadge`) |
| Modify | `server/src/bubbles/db/repo/gamification.py` (`add_xp` signature; `get_or_assign_daily_quests`, `leaderboard_period`, `rank_all_time`, `rank_period`, `owned_reward_ids`) |
| Modify | `server/src/bubbles/api/v1/_schemas.py` (gamification section) |
| Modify | `server/src/bubbles/api/router.py` (register `gamification_router`) |
| Modify | `server/tests/integration/fixtures/baseline.sql` (3 tables) |
| Modify | `server/tests/integration/conftest.py` (teardown list) |
| Create | `server/tests/test_core_gamification.py` |
| Create | `server/tests/integration/test_repo_xp.py` |
| Create | `server/tests/integration/test_repo_achievements.py` |
| Create | `server/tests/integration/test_routes_gamification.py` |
| Modify | `server/tests/integration/test_repo_gamification.py` (extend) |
| Modify (after merge) | `Documentation/server-vs-server_v2-review.md` §5 (mark Batch 2 done) |
