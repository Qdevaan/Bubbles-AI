# Longitudinal Progress Dashboard — time-bucketed metrics for "am I improving?"

**Date:** 2026-05-23 • **Owner:** backend • **Type:** new feature (Feature 3 of 4) • **Ref:** brainstorming 2026-05-23

## Problem

The server already collects every signal needed to show a user whether they are getting better at communication: XP awards via `xp_transactions`, sessions with `ended_at`, mistakes via `user_mistakes`, sentiment and talk-time on `session_analytics`, drill cards from F2, streak/level on `user_gamification`. But every existing read surface answers a *point-in-time* question — "this session's analytics", "this period's average filler count" — not "how have I changed over the last 30 days?".

The existing endpoints (`/v1/analytics/communication_trends`, `/v1/analytics/performance_summary`, `/v1/analytics/digest`) return per-session lists or single-window aggregates. None bucket results into days/weeks/months for a chart, and none compare the current window to the previous one. A user opening a "Progress" tab cannot see a sparkline of their last 30 days of XP, sessions, or mistakes.

## Decision

A dedicated `dashboard` read-only subsystem. Not folded into the existing `analytics.py` repo: that module is already 400+ lines and mixes write-side helpers (`upsert_session_analytics`, `upsert_coaching_report`) with single-window reads. The dashboard's queries are time-bucketed `generate_series` joins of a different shape; giving them their own repo keeps each module focused.

**Compute model:** on-the-fly aggregation. The raw tables (`xp_transactions`, `user_mistakes`, `sessions`, `session_analytics`) all carry `(user_id, time)` indexes already. A 30-day window is single-digit ms at user scale; 365 days is still safely under 200 ms. No new table, no worker, no staleness window.

**Endpoint:** one omnibus `GET /v1/dashboard?range={30d|90d|365d}`. Single round-trip from the app; matches the single-screen dashboard the app will render. Auth is JWT-bearer; the user id comes from the JWT — no `{user_id}` path param, no leak surface.

**Granularity:** server-decided from the `range` query param — `30d → daily`, `90d → weekly`, `365d → monthly`. Echoed back as `granularity` so the app knows what label format to render.

**Bucket fill:** every series LEFT JOINs against `generate_series(start, end, step)` so empty days emit `{bucket, value: 0}` (or `null` for sentiment, where 0 would be misleading). No client-side gap-filling.

**Summary cards carry deltas:** for each window-sized metric, the response includes `{current, previous, delta_pct}` where `previous` covers `[cur_start - range, cur_start)`. That delta is the headline ("XP up 23% vs last 30 days") — the whole point of a progress dashboard.

**Snapshot bits** that are not time-windowed — drill mastery %, current streak, level, due drill count — sit alongside the windowed metrics in the same `summary` object.

**Speed:** one route, one DB transaction, 5 series queries + 5 summary CTE queries + 1 gamification read + 1 drill-count read. Every query is bounded by `created_at >= prev_start`, hits an existing `(user_id, created_at)` index, and returns at most ~30 buckets. The 0.5 s wingman context budget and per-turn loop are untouched.

## Scope

1. **`db/repo/dashboard.py`** — new repo. No migration; reads only:

   - `BucketPoint` — `bucket: date`, `value: int` (XP / sessions / mistakes / talk_time_seconds).
   - `BucketPointF` — `bucket: date`, `value: float | None` (sentiment — `None` for empty buckets).
   - `SummaryWindow` — dataclass with 10 fields: `cur_xp, prev_xp, cur_sessions, prev_sessions, cur_mistakes, prev_mistakes, cur_sentiment, prev_sentiment, cur_talk_seconds, prev_talk_seconds` (last two as `float | None`).
   - `SummarySnapshot` — dataclass `drill_mastery_pct: int | None`, `current_streak: int`, `level: int`, `due_drill_count: int`.
   - `async series_xp(conn, *, user_id, start, end, step) -> list[BucketPoint]`
   - `async series_sessions(conn, *, user_id, start, end, step) -> list[BucketPoint]`
   - `async series_mistakes(conn, *, user_id, start, end, step) -> list[BucketPoint]`
   - `async series_sentiment(conn, *, user_id, start, end, step) -> list[BucketPointF]`
   - `async series_talk_time(conn, *, user_id, start, end, step) -> list[BucketPoint]` (seconds; route converts to minutes for the response shape).
   - `async summary_window(conn, *, user_id, cur_start, cur_end, prev_start, prev_end) -> SummaryWindow`
   - `async snapshot(conn, *, user_id) -> SummarySnapshot`
   - Register in `db/repo/__init__.py`.

   All five series functions use the same pattern: `generate_series(start, end, step)` LEFT JOIN raw table aggregates bound to `[bucket, bucket + step)`. Bound the input scan with `WHERE created_at >= start AND created_at < end` so the planner uses `(user_id, created_at)`.

2. **`api/v1/_dashboard_helpers.py`** — pure helper module (unit-testable, no I/O):
   - `RANGES: Final[Mapping[str, tuple[timedelta, str, str]]]` — maps `"30d" → (timedelta(days=30), "1 day", "daily")`, etc.
   - `resolve_range(range_arg, now) -> tuple[datetime, datetime, datetime, datetime, str, str]` — returns `(cur_start, cur_end, prev_start, prev_end, pg_step, granularity)`. `cur_end = now`, `cur_start = now - delta`, `prev_end = cur_start`, `prev_start = cur_start - delta`. Raises `ValueError` on unknown range.
   - `delta_pct(current, previous) -> float | None` — `((current - previous) / previous) * 100` rounded to 1 dp; `None` when `previous == 0` (cannot divide); `0.0` when `current == previous == 0`.

3. **Schemas** (`api/v1/_schemas.py`):
   - `BucketPointOut` — `bucket: date`, `value: int = Field(ge=0)`.
   - `BucketPointFOut` — `bucket: date`, `value: float | None = None`.
   - `MetricDelta` — `current: float`, `previous: float`, `delta_pct: float | None`.
   - `DashboardSummary` — `total_xp, sessions, mistakes, avg_sentiment, talk_time_minutes: MetricDelta`; `drill_mastery_pct: int | None`; `current_streak: int = Field(ge=0)`; `level: int = Field(ge=1)`; `due_drill_count: int = Field(ge=0)`.
   - `DashboardSeries` — `xp_per_bucket, sessions_per_bucket, mistakes_per_bucket, talk_time_minutes_per_bucket: list[BucketPointOut]`; `avg_sentiment_per_bucket: list[BucketPointFOut]`.
   - `DashboardWindow` — `start: datetime`, `end: datetime`.
   - `DashboardResponse` — `range: Literal["30d","90d","365d"]`, `granularity: Literal["daily","weekly","monthly"]`, `window: DashboardWindow`, `summary: DashboardSummary`, `series: DashboardSeries`.

4. **`api/v1/dashboard.py`** — new router; auth + ownership via JWT user id (no path param):
   - `GET /v1/dashboard?range=30d` — body none. Validates `range ∈ {"30d","90d","365d"}` (else `400`). Resolves window + step + granularity via `resolve_range(range, now=datetime.now(UTC))`. Inside one `transaction(pool)`:
     - `series_xp`, `series_sessions`, `series_mistakes`, `series_sentiment`, `series_talk_time` — five calls.
     - `summary_window` once.
     - `snapshot` once.
   - Build `DashboardSummary` — each `MetricDelta.current/previous` carries cur/prev values from the `SummaryWindow` (talk-time converted seconds → minutes); `delta_pct = delta_pct(current, previous)`.
   - Build `DashboardSeries` — `talk_time_minutes_per_bucket` derived from `series_talk_time` by dividing seconds → minutes with rounding to 1 dp; rest direct.
   - `RateLimiter` ~30/min/user (dashboard is hit on tab open and pull-to-refresh).
   - Return `DashboardResponse`. `200` happy path. `400` on bad range. `401` missing auth.

5. **`api/router.py`** — register the dashboard router under `/v1`.

## Out of scope

- Pre-aggregated `user_daily_metrics` table or nightly worker — on-the-fly is enough at current data scale.
- Cohort or leaderboard comparison — single-user view only.
- Drill-review-per-day series — F2 stores `total_reviews` lifetime but no per-day event log. Re-introduce if the gap matters; for now the summary's `drill_mastery_pct` snapshot is the drill-progress signal.
- Per-rule mistake breakdown — covered by F2's `drill_cards.examples` and existing `/v1/user_mistakes`.
- CSV / PDF export.
- Real-time push / websocket — pull-based fetch is sufficient for a dashboard tab.
- Editing the time window with arbitrary `since`/`until` — only the three preset ranges. Adding a custom range later is a single new `RANGES` entry plus a validation tweak.
- Localised date labels (the response returns ISO `date`; the app handles user-facing formatting).

## Tests

- `tests/unit/test_dashboard_helpers.py` — `resolve_range("30d", fixed_now)` returns the expected `(cur_start, cur_end, prev_start, prev_end, step, granularity)`; same for 90d (weekly) and 365d (monthly); `resolve_range("7d", …)` raises `ValueError`; `delta_pct(120, 100) == 20.0`; `delta_pct(50, 100) == -50.0`; `delta_pct(10, 0) is None`; `delta_pct(0, 0) == 0.0`; `delta_pct(rounding)` checks 1-dp rounding.
- `tests/integration/test_repo_dashboard.py` — each `series_*` fills zero buckets for empty days/weeks; respects `[start, end)` boundary; cross-user invisibility; `summary_window` returns cur/prev correctly; `snapshot` reads `user_gamification` row, returns `drill_mastery_pct` from non-retired cards with `total_reviews > 0`, and `due_drill_count` matches `drill_cards_repo.count_due`.
- `tests/integration/test_routes_dashboard.py` — `GET /v1/dashboard?range=30d` returns `granularity='daily'` and a 30-bucket series; `range=90d` → `weekly` and ~13 buckets; `range=365d` → `monthly` and ~12 buckets; bad range → `400`; cross-user data invisible (seed another user; their rows must not contribute to the caller's response); response validates against `DashboardResponse` schema (extra fields would `extra="forbid"` via `_Base`); rate-limit on rapid repeats.

## Done when

`ruff` clean, `mypy --strict` clean, the unit suite green (integration suite green under `RUN_INTEGRATION=1`); the dashboard router is registered and visible in the OpenAPI schema; every function fully implemented — no placeholder bodies, stub returns, or "implement later" comments.
