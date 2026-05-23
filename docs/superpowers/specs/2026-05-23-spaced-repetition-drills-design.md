# Spaced-Repetition Mistake Drills — turn past mistakes into practice

**Date:** 2026-05-23 • **Owner:** backend • **Type:** new feature (Feature 2 of 4) • **Ref:** brainstorming 2026-05-23

## Problem

The `user_mistakes` table already collects every grammar/usage error the user makes — populated by `POST /v1/check_user_turn` (LLM pass) and the `grammar_scan` worker (LanguageTool pass). But the table is write-only: the only read surface is `GET /v1/user_mistakes`, which returns a flat reverse-chronological list. There is no concept of a card, no scheduling, no follow-up. A user who made the same article-omission mistake 20 times sees 20 raw rows and never gets prompted to actually fix it.

Spaced repetition is the well-known fix: surface each mistake pattern on an expanding interval (1d, 3d, 7d, …) until the user demonstrates they have it down. The existing data is enough — we just need a card abstraction, a scheduler, a review endpoint, and a worker that materializes cards from new mistakes at session end.

## Decision

A dedicated `drills` subsystem. Not folded into the grammar surface: that surface is per-turn and write-heavy, while drills are user-paced and read-heavy with their own SRS state.

**Card grain:** one card per `(user_id, rule_id, category)`. Same rule_id hitting 20 times = 1 card with 10 most-recent example snippets. Dedup matches how SRS pedagogy normally works.

**Algorithm:** Leitner 5-box with fixed intervals `{1: 1d, 3d, 7d, 14d, 30d}`. Correct → next box. Wrong → back to box 1. Stateless math, debuggable, no ease-factor tuning.

**Card format:** self-grade flashcard. Front = newest example snippet. Back = newest suggestion. User taps `correct` or `wrong`. Zero LLM cost per review.

**Delivery:** primary surface is the daily due-stack (`GET /v1/drills/queue`). When the stack is empty, the same endpoint returns next-N upcoming cards (`include_upcoming=true`) so the user can practice early.

**Materialization:** ARQ worker `materialize_drill_cards` fires from the `end_session` fan-out next to `generate_scenarios`. Loads the session's mistakes, upserts into `drill_cards` (append new examples, cap at 10). Idempotent per session.

**XP:** `+15` on correct review that advances the box, `+5` on wrong review (showing-up credit), `+0` on correct review that stays in box 5. Idempotent on `(user_id, source_type='drill_review', source_id=f"{card_id}:{from_box}->{to_box}")` — each transition is its own XP event, double-award impossible.

**Speed:** queue read is a single indexed query (`(user_id, due_at) WHERE retired_at IS NULL`). Review is a single UPDATE + at most one XP write. Materialization runs in a worker. The 0.5 s wingman context budget and per-turn loop are untouched.

## Scope

1. **Migration `2026_05_23_0007_drill_cards`** — `drill_cards` table (forward + working `downgrade`; `IF NOT EXISTS`-guarded to match `0002`–`0006` against the live Supabase schema):

   | column | type | notes |
   |---|---|---|
   | `id` | `uuid pk default gen_random_uuid()` | |
   | `user_id` | `uuid not null references auth.users(id) on delete cascade` | |
   | `rule_id` | `text not null` | grouping key (e.g. `LLM_ARTICLE`, `UPPERCASE_SENTENCE_START`) |
   | `category` | `text not null` | grouping key (e.g. `article`, `agreement`) |
   | `examples` | `jsonb not null default '[]'::jsonb` | array of `{mistake_id, snippet, suggestion, created_at}` — newest first, cap 10 |
   | `box` | `smallint not null default 1 check (box between 1 and 5)` | Leitner box |
   | `due_at` | `timestamptz not null default now()` | next review time; new cards are immediately due |
   | `last_reviewed_at` | `timestamptz` | null until first review |
   | `correct_streak` | `integer not null default 0` | resets on wrong |
   | `total_reviews` | `integer not null default 0` | lifetime count |
   | `total_correct` | `integer not null default 0` | lifetime |
   | `retired_at` | `timestamptz` | null = active; set when user retires the card |
   | `created_at` | `timestamptz not null default now()` | |
   | `updated_at` | `timestamptz not null default now()` | |

   Constraint: `unique (user_id, rule_id, category)`.
   Indexes: `(user_id, due_at) where retired_at is null` (queue hot path), `(user_id, retired_at)`.
   Add `drill_cards` to `baseline.sql` and to the conftest teardown DROP list.

2. **`db/models.py`** — `DrillCard` frozen-slot dataclass mirroring the table.

3. **`db/repo/drill_cards.py`** — new repo (register in `db/repo/__init__.py`):
   - `upsert_from_mistakes(conn, *, user_id, mistakes) -> int` — for each mistake, `INSERT … ON CONFLICT (user_id, rule_id, category) DO UPDATE` that prepends a new `{mistake_id, snippet, suggestion, created_at}` entry to `examples` (kept to 10 newest), bumps `updated_at`. Returns count of cards touched.
   - `list_due(conn, *, user_id, limit, offset) -> list[DrillCard]` — `retired_at IS NULL AND due_at <= now()` ordered by `due_at ASC`.
   - `count_due(conn, *, user_id) -> int`
   - `list_upcoming(conn, *, user_id, limit) -> list[DrillCard]` — `retired_at IS NULL AND due_at > now()` ordered by `due_at ASC`.
   - `get(conn, *, card_id) -> DrillCard | None`
   - `apply_review(conn, *, card_id, result, intervals) -> DrillCard` — single UPDATE that bumps `box`, `due_at`, `correct_streak`, `total_reviews`, `total_correct`, `last_reviewed_at` atomically per Leitner rules. RETURNING `{_COLS}`. Result is `"correct"` or `"wrong"`; `intervals` is the box→timedelta map injected for testability.
   - `retire(conn, *, card_id) -> DrillCard` — set `retired_at = now()`, RETURNING; guard `WHERE retired_at IS NULL`.
   - All writes bump `updated_at`.

4. **`db/repo/grammar.py`** — add `list_for_session(conn, *, session_id) -> list[UserMistake]`. Used by the materialize worker to pull a session's mistakes by `session_id`.

5. **`ai/drills.py`** — pure helper module:
   - `BOX_INTERVALS: Final[Mapping[int, timedelta]]` — `{1: 1d, 2: 3d, 3: 7d, 4: 14d, 5: 30d}`.
   - `next_state(box, result) -> tuple[int, timedelta, str]` — returns `(new_box, interval, transition_label)` where `transition_label = f"{from_box}->{to_box}"`.
   - No LLM, no I/O, pure function — unit-testable.

6. **Schemas** (`api/v1/_schemas.py`):
   - `DrillCardOut` — `id, rule_id, category, front, back, examples_count, box, due_at, last_reviewed_at, correct_streak, total_reviews, total_correct, retired_at, created_at, updated_at`. `front` and `back` are derived from `examples[0]` (`snippet` and `suggestion`).
   - `ReviewDrillRequest` — `result: Literal["correct","wrong"]`.
   - `ReviewDrillResponse` — `card: DrillCardOut`, `xp_awarded: int`, `transition: str` (e.g. `"3->4"`).
   - `DrillQueueResponse` — `items: list[DrillCardOut]`, `total_due: int`.

7. **`api/v1/drills.py`** — new router; every route authenticated and ownership-checked against the JWT user:
   - `GET /v1/drills/queue?limit=20&offset=0&include_upcoming=false` — returns `list_due`. When `include_upcoming=true` and `list_due` is empty, returns `list_upcoming(limit)` instead (practice-early). `DrillQueueResponse`.
   - `POST /v1/drills/{id}/review` — body `ReviewDrillRequest`. Verify ownership; `409` when `retired_at IS NOT NULL`; `apply_review`; on correct-advance write XP via `xp_repo.award` with `source_type='drill_review'`, `source_id=f"{card_id}:{transition}"`, action `complete_drill_review`, amount `+15`. On wrong write XP `+5` with same `source_id` format. On correct-stay-in-box-5 write `+0` (no XP row). Returns `ReviewDrillResponse`. `404` unknown card, `403` not owner. `RateLimiter` ~60/min/user (reviews are user-paced but not abused).
   - `POST /v1/drills/{id}/retire` — `409` if already retired; otherwise `retire`. Returns `DrillCardOut`.

8. **`api/router.py`** — register the drills router under `/v1`.

9. **`workers/jobs/materialize_drill_cards.py`** — `materialize_drill_cards(ctx, user_id, session_id)`:
   - `grammar_repo.list_for_session(conn, session_id=session_id)` to load this session's mistakes.
   - No-op when empty (return `{"materialized": 0}`).
   - `drill_cards_repo.upsert_from_mistakes(conn, user_id=user_id, mistakes=…)` inside a single `UnitOfWork`.
   - Idempotent `_job_id = f"materialize_drills:{user_id}:{session_id}"` (per-session is correct here — concurrent end_sessions for the same user but different sessions must both run).
   - `__all__ = ["run"]` for mypy compliance.

10. **`api/v1/sessions.py` `end_session`** — extend the post-session fan-out: append `enqueue_materialize_drill_cards(arq, user_id=user_id, session_id=session_id)` alongside the existing `generate_scenarios` enqueue. Idempotent job id.

11. **`workers/jobs/__init__.py` + `workers/arq_settings.py`** — register `materialize_drill_cards` in the worker function list.

12. **`workers/enqueue.py`** — `enqueue_materialize_drill_cards(arq, *, user_id, session_id) -> None`.

## Out of scope

- Push notifications — app-side concern; doc will say `count_due > 0` once/day is the trigger.
- Multi-language / locale-specific rules — uses whatever `rule_id` the existing grammar pipeline emits.
- Editing card content — `examples` auto-rotates by recency; user can `retire` to silence.
- Multiple-choice / type-the-fix variants — separate follow-up feature if engagement is weak after launch.
- A drill-specific quest or daily-streak — existing gamification (`xp`, `user_gamification`) handles general XP/streak.
- Cron-scheduled materialization — the end_session worker is sufficient; no daily cron.
- LLM-generated reformulations of cards.

## Tests

- `tests/unit/test_drill_intervals.py` — `next_state` correct/wrong transitions for every box (1–5); cap at box 5 on correct; reset to 1 on wrong; transition label format.
- `tests/integration/test_repo_drill_cards.py` — `upsert_from_mistakes` dedups across same `(rule_id, category)`, prepends new examples + caps at 10; `list_due` / `count_due` exclude retired + future-due; `apply_review` correct advances box and pushes `due_at`, wrong resets to box 1; `retire` flips flag and is `409`-equivalent on re-call (returns null / repo enforces guard); ownership scoping (cross-user invisible).
- `tests/integration/test_routes_drills.py` — queue ownership (403 cross-user); `include_upcoming=true` falls back to upcoming when due is empty; review correct returns advanced card + `+15 XP`; review wrong returns box-1 card + `+5 XP`; review of card already in box 5 returns same box + `+0 XP`; XP idempotency on repeated same-transition POST; `409` on retired card review; `409` on double-retire.
- `tests/integration/test_workers_drills.py` — `materialize_drill_cards` no-op on empty session mistakes; upserts on first call with one mistake per rule; second call with the same session is idempotent (no duplicate examples); concurrent sessions for the same user both materialize.
- `tests/integration/test_routes_sessions.py` (extend) — `end_session` enqueues `materialize_drill_cards` (job count = previous + 1).

## Done when

`ruff` clean, `mypy --strict` clean, the unit suite green (integration suite green under `RUN_INTEGRATION=1`); migration `0007` upgrades and downgrades cleanly against a fresh Postgres and is a safe no-op against the live Supabase schema; the drills router is registered and visible in the OpenAPI schema; every function is fully implemented — no placeholder bodies, stub returns, or "implement later" comments.
