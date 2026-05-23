# Feature 3 — Longitudinal Progress Dashboard

One omnibus endpoint that returns time-bucketed series (XP, sessions,
mistakes, sentiment, talk-time) plus a snapshot summary with
previous-window deltas, so the app can render an "am I improving?"
screen with sparklines + headline numbers.

## Server side — what was built

**No new tables, no worker, no migration.** Pure read-side feature
running on-the-fly aggregation against the already time-indexed source
tables (`xp_transactions`, `user_mistakes`, `sessions`,
`session_analytics`, `drill_cards`, `user_gamification`).

**Endpoint** (under `/v1`, JWT-authenticated, owner-scoped via JWT
user id — no `{user_id}` path param):

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/dashboard?range=30d` | Returns the full dashboard payload. `range` ∈ `{30d, 90d, 365d}`. `200` with `DashboardResponse`. `400` on unknown range. `429` when rate-limited (~30/min/user). |

**Granularity (server-decided from `range`):**

| range | bucket | series length |
|---|---|---|
| `30d`  | daily   | 30 points |
| `90d`  | weekly  | ~13 points |
| `365d` | monthly | ~12 points |

Echoed back in `granularity` so the app picks the right axis-label
format.

**Response shape (`DashboardResponse`):**

```json
{
  "range": "30d",
  "granularity": "daily",
  "window": {"start": "2026-04-23T00:00:00Z", "end": "2026-05-23T00:00:00Z"},
  "summary": {
    "total_xp":          {"current": 850, "previous": 690, "delta_pct": 23.2},
    "sessions":          {"current": 12,  "previous": 9,   "delta_pct": 33.3},
    "mistakes":          {"current": 47,  "previous": 71,  "delta_pct": -33.8},
    "avg_sentiment":     {"current": 0.42,"previous": 0.31,"delta_pct": 35.5},
    "talk_time_minutes": {"current": 145.3,"previous":110.1,"delta_pct": 32.0},
    "drill_mastery_pct": 64,
    "current_streak": 7,
    "level": 4,
    "due_drill_count": 3
  },
  "series": {
    "xp_per_bucket":               [{"bucket": "2026-04-23", "value": 25}, …],
    "sessions_per_bucket":         [{"bucket": "2026-04-23", "value": 1},  …],
    "mistakes_per_bucket":         [{"bucket": "2026-04-23", "value": 4},  …],
    "avg_sentiment_per_bucket":    [{"bucket": "2026-04-23", "value": 0.4},…],
    "talk_time_minutes_per_bucket":[{"bucket": "2026-04-23", "value": 12}, …]
  }
}
```

**Series rules:**

- Every series fills empty buckets with `0` (or `null` for sentiment —
  zero would lie about flat affect).
- All series are server-built with `generate_series` LEFT JOIN — the
  app never has to gap-fill.
- `sessions_per_bucket` counts only ended sessions
  (`ended_at IS NOT NULL AND deleted_at IS NULL`).
- `xp_per_bucket` and `total_xp.summary` count positive XP only
  (`amount > 0`); XP spend is tracked separately on
  `user_gamification.xp_spent`.
- `talk_time_minutes_per_bucket` is whole minutes (rounded); summary's
  `talk_time_minutes.current/previous` carry 1-dp precision.

**Delta semantics:**

- `delta_pct = round((cur - prev) / prev * 100, 1)` when `prev > 0`.
- `delta_pct = null` when `prev == 0 and cur != 0` (cannot divide).
- `delta_pct = 0.0` when both are exactly zero (no change).

**Snapshot bits** (not time-windowed):

- `drill_mastery_pct` — `round(avg(100 * total_correct / NULLIF(total_reviews, 0)))` over the user's non-retired drill cards. `null` when the user has no drill cards yet.
- `current_streak`, `level` — from `user_gamification`. Defaults `0/1` for a brand-new user with no row yet.
- `due_drill_count` — count of drill cards where `retired_at IS NULL AND due_at <= now()`.

**Speed:** one route, one DB transaction, 5 series queries + 5 summary
CTE queries + 1 gamification read + 1 due-count read. Every query is
bounded by `created_at >= prev_start` and hits an existing
`(user_id, time)` index. Wingman's 0.5 s context budget and per-turn
loop are untouched.

## App side — what is required (Flutter)

1. **Progress tab / screen** — a new screen that fetches
   `GET /v1/dashboard?range=30d` on tab open. Default range is `30d`;
   provide a segmented control to switch between `30d / 90d / 365d`.

2. **Summary cards** — render one card per `summary` metric:
   - Headline number (`current`, formatted per metric — int for
     xp/sessions/mistakes/streak/level; one-dp percent for sentiment;
     one-dp minute for talk-time).
   - Delta pill (`delta_pct`): green when positive (note: positive
     delta on `mistakes` is bad — invert the color), red when negative
     (or positive for mistakes), grey when `null`. "—" when both
     current and previous are zero.
   - Sub-line: "vs previous 30d" (text comes from `range`).

3. **Sparklines** — small line/bar charts per series. The bucket field
   is a `date` (ISO). The app's chart lib should accept the list
   directly; for `avg_sentiment_per_bucket`, treat `null` values as
   gaps (don't draw a line through them).

4. **Snapshot strip** — a row above the cards: `current_streak` (with
   the flame icon), `level` (with XP bar to next level — XP-to-next is
   not in this endpoint; reuse the existing gamification endpoint),
   `due_drill_count` (with link to the Drills tab), `drill_mastery_pct`
   (with progress ring).

5. **Refresh cadence** — fetch on tab open + pull-to-refresh. Optional:
   re-fetch after `end_session` returns (the workers populate
   `session_analytics` asynchronously, so wait 2-5 s before refresh).

6. **No app-side aggregation logic** — the server does all bucketing
   and gap-filling. The app just renders.

## Error handling

- **`400`** — unknown `range`. App should not allow the user to send
  one; segmented control is the only input.
- **`401`** — missing/invalid JWT. Force re-login.
- **`429`** — rate-limited. Show a brief "slow down" toast; the
  segmented control should debounce range changes.
- **`5xx`** — generic "couldn't load progress — try again" with a
  manual refresh button.

## File map (server)

- `server/src/bubbles/api/v1/_dashboard_helpers.py` — `RANGES`, `resolve_range`, `delta_pct` (pure).
- `server/src/bubbles/db/repo/dashboard.py` — `BucketPoint`, `BucketPointF`, `SummaryWindow`, `SummarySnapshot` dataclasses + `series_*` (5) + `summary_window` + `snapshot`.
- `server/src/bubbles/db/repo/__init__.py` — repo registered.
- `server/src/bubbles/api/v1/_schemas.py` — `BucketPointOut`, `BucketPointFOut`, `MetricDelta`, `DashboardSummary`, `DashboardSeries`, `DashboardWindow`, `DashboardResponse`.
- `server/src/bubbles/api/v1/dashboard.py` — single route + `_to_int_buckets` / `_to_float_buckets` / `_seconds_buckets_to_minutes` helpers.
- `server/src/bubbles/api/router.py` — router registered.

## Tests

- `server/tests/unit/test_dashboard_helpers.py` — 10 cases for `resolve_range` + `delta_pct`.
- `server/tests/integration/test_repo_dashboard.py` — 8 cases (each series fills zero buckets, sentiment returns null for empty, session counter excludes open sessions, summary cur/prev split, snapshot reads gamification + drill mastery + due count, cross-user invisibility).
- `server/tests/integration/test_routes_dashboard.py` — 6 cases (daily for 30d, weekly for 90d, monthly for 365d, bad range → 400, owner-scoped, XP delta in summary).

Integration tests run with `$env:RUN_INTEGRATION='1'` and require
Docker (testcontainers Postgres). They skip automatically when Docker
is unavailable.

## Out of scope (handled later, if ever)

- Pre-aggregation table / nightly worker — on-the-fly is enough at
  current data volume.
- Cohort / leaderboard comparison — single-user view only.
- Drill-review-per-day series — `total_reviews` is lifetime; a
  per-day event log would be needed.
- CSV / PDF export.
- Real-time / websocket push — pull-only.
- Custom `since`/`until` ranges — only the three presets.
- Localised date labels — server returns ISO `date`; app formats.
