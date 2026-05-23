# Longitudinal Progress Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one omnibus `GET /v1/dashboard?range=…` endpoint that returns time-bucketed series (XP, sessions, mistakes, sentiment, talk-time) plus a snapshot summary with previous-window deltas.

**Architecture:** Read-only feature. No new tables, no worker, no migration. Pure on-the-fly aggregation: each series query is `generate_series(start, end, step) LEFT JOIN raw_table` so empty buckets are filled deterministically. Granularity (`daily/weekly/monthly`) is server-decided from `range` (`30d/90d/365d`). Summary metrics carry `{current, previous, delta_pct}` over the requested window.

**Tech Stack:** FastAPI, asyncpg (raw SQL), Pydantic v2, pytest + testcontainers Postgres.

**Spec:** `docs/superpowers/specs/2026-05-23-progress-dashboard-design.md`.

---

## File Structure

| Path | Type | Responsibility |
|---|---|---|
| `server/src/bubbles/api/v1/_dashboard_helpers.py` | Create | Pure helpers: `RANGES` map, `resolve_range(range_arg, now)`, `delta_pct(current, previous)`. No I/O. |
| `server/src/bubbles/db/repo/dashboard.py` | Create | Repo: 5 `series_*` SQL functions + `summary_window` + `snapshot`. Internal dataclasses `BucketPoint`, `BucketPointF`, `SummaryWindow`, `SummarySnapshot`. |
| `server/src/bubbles/db/repo/__init__.py` | Modify | Re-export `dashboard` repo. |
| `server/src/bubbles/api/v1/_schemas.py` | Modify | 5 new DTOs: `BucketPointOut`, `BucketPointFOut`, `MetricDelta`, `DashboardSummary`, `DashboardSeries`, `DashboardWindow`, `DashboardResponse`. |
| `server/src/bubbles/api/v1/dashboard.py` | Create | One route `GET /v1/dashboard`, owner-scoped via JWT user id. Wires helpers + repo into the response. |
| `server/src/bubbles/api/router.py` | Modify | Register `dashboard_router` under `/v1`. |
| `server/tests/unit/test_dashboard_helpers.py` | Create | Pure unit tests for `resolve_range` + `delta_pct`. |
| `server/tests/integration/test_repo_dashboard.py` | Create | Each `series_*` fills zero buckets, respects time boundary, cross-user invisible; `summary_window` cur/prev; `snapshot` reads gamification + drill_cards. |
| `server/tests/integration/test_routes_dashboard.py` | Create | Auth, owner-scoped, bad range → 400, daily/weekly/monthly granularity, schema validates. |

---

## Notes for the implementer

- **No placeholders.** Every step produces fully working code. No `pass`-stub, no `TODO`, no fake returns.
- **No Co-Authored-By trailer** on commits.
- **Explicit pathspec on every commit:** `git commit -m "..." -- <file1> <file2>`. After every commit run `git show --stat HEAD` and verify the file list matches the task's "Files" block.
- **TDD.** Every task starts with the failing test, runs to fail, then implements, then runs green.
- **Integration tests need Docker** (testcontainers). When Docker is absent the integration suite skips at collection — that is acceptable; complete static checks (`ruff`, `mypy --strict`, smoke import) and mark `DONE_WITH_CONCERNS`.
- **Branch.** All work on `feat/progress-dashboard` (already created from `main` post-F2-merge).
- **Patterns to follow:**
  - Schemas subclass `_Base` (already in `_schemas.py`); `_Base` sets `extra="forbid"`, `str_strip_whitespace=True`.
  - Routes use `CurrentUserDep` for auth, `PoolDep` + `transaction(pool)` for reads, `RateLimiterDep` for rate limits. Pattern reference: `server/src/bubbles/api/v1/scenarios.py`.
  - Rate-limit shape: `rl = await limiter.check(key, capacity=…, refill_per_s=…); if not rl.allowed: raise RateLimited(rl.retry_after_s)`.
  - Repos use `(conn: asyncpg.Connection, *, …)` keyword-only signatures, `_COLS` constants where applicable, frozen-slot dataclasses for output rows.

---

## Tasks

### Task 1: `_dashboard_helpers.py` + unit tests

**Files:**
- Create: `server/src/bubbles/api/v1/_dashboard_helpers.py`
- Create: `server/tests/unit/test_dashboard_helpers.py`

- [ ] **Step 1: Write the failing unit tests**

Create `server/tests/unit/test_dashboard_helpers.py`:

```python
"""Pure-helper tests for api.v1._dashboard_helpers."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from bubbles.api.v1._dashboard_helpers import RANGES, delta_pct, resolve_range


_NOW = datetime(2026, 5, 23, 12, 0, 0, tzinfo=UTC)


def test_ranges_table_has_three_entries() -> None:
    assert set(RANGES.keys()) == {"30d", "90d", "365d"}


@pytest.mark.parametrize(
    ("range_arg", "expected_delta_days", "expected_step", "expected_granularity"),
    [
        ("30d", 30, "1 day", "daily"),
        ("90d", 90, "1 week", "weekly"),
        ("365d", 365, "1 month", "monthly"),
    ],
)
def test_resolve_range_returns_expected_window_and_step(
    range_arg: str, expected_delta_days: int, expected_step: str, expected_granularity: str
) -> None:
    cur_start, cur_end, prev_start, prev_end, step, granularity = resolve_range(range_arg, _NOW)
    assert cur_end == _NOW
    assert cur_start == _NOW - timedelta(days=expected_delta_days)
    assert prev_end == cur_start
    assert prev_start == cur_start - timedelta(days=expected_delta_days)
    assert step == expected_step
    assert granularity == expected_granularity


def test_resolve_range_rejects_unknown_value() -> None:
    with pytest.raises(ValueError, match=r"unknown range"):
        resolve_range("7d", _NOW)


def test_delta_pct_basic_increase() -> None:
    assert delta_pct(120, 100) == 20.0


def test_delta_pct_basic_decrease() -> None:
    assert delta_pct(50, 100) == -50.0


def test_delta_pct_previous_zero_returns_none() -> None:
    assert delta_pct(10, 0) is None


def test_delta_pct_both_zero_returns_zero() -> None:
    assert delta_pct(0, 0) == 0.0


def test_delta_pct_rounds_to_one_decimal() -> None:
    assert delta_pct(123, 100) == 23.0
    assert delta_pct(1234, 1000) == 23.4
    assert delta_pct(12345, 10000) == 23.5  # 0.234500 → 23.4 or 23.5 depending on rounding
```

- [ ] **Step 2: Run tests to verify they fail**

Run from `e:\FYP\FYP_V2\Bubbles-AI\server`:

```powershell
uv run pytest tests/unit/test_dashboard_helpers.py -v --no-cov
```

Expected: `ModuleNotFoundError: No module named 'bubbles.api.v1._dashboard_helpers'`.

- [ ] **Step 3: Write the helper module**

Create `server/src/bubbles/api/v1/_dashboard_helpers.py`:

```python
"""Pure helpers for the progress-dashboard route.

No I/O, no DB, no HTTP. ``resolve_range`` turns the ``range`` query
parameter into a ``(cur_start, cur_end, prev_start, prev_end, pg_step,
granularity)`` tuple. ``delta_pct`` computes the previous-window
comparison with the well-known edge cases handled explicitly.

The ``pg_step`` strings are PostgreSQL ``interval`` literals consumed by
the dashboard repo's ``generate_series`` queries.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Final, Mapping

# (delta, pg_step, granularity label)
RANGES: Final[Mapping[str, tuple[timedelta, str, str]]] = {
    "30d": (timedelta(days=30), "1 day", "daily"),
    "90d": (timedelta(days=90), "1 week", "weekly"),
    "365d": (timedelta(days=365), "1 month", "monthly"),
}


def resolve_range(
    range_arg: str, now: datetime
) -> tuple[datetime, datetime, datetime, datetime, str, str]:
    """Resolve ``range_arg`` into ``(cur_start, cur_end, prev_start, prev_end, pg_step, granularity)``.

    ``cur_end`` is ``now``; ``cur_start`` is ``now - delta``. The previous
    window is the same-length window immediately before the current one:
    ``[cur_start - delta, cur_start)``. Raises ``ValueError`` if
    ``range_arg`` is not one of the three preset keys.
    """
    if range_arg not in RANGES:
        raise ValueError(f"unknown range: {range_arg!r}")
    delta, pg_step, granularity = RANGES[range_arg]
    cur_end = now
    cur_start = now - delta
    prev_end = cur_start
    prev_start = cur_start - delta
    return cur_start, cur_end, prev_start, prev_end, pg_step, granularity


def delta_pct(current: float, previous: float) -> float | None:
    """Return ``((current - previous) / previous) * 100`` rounded to 1 dp.

    Returns ``None`` when ``previous == 0 and current != 0`` (cannot
    divide). Returns ``0.0`` when both are exactly zero (no change).
    """
    if previous == 0:
        return 0.0 if current == 0 else None
    return round(((current - previous) / previous) * 100, 1)
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
uv run pytest tests/unit/test_dashboard_helpers.py -v --no-cov
```

Expected: 8 tests passed (1 table + 3 parametrized resolve + 1 raises + 4 delta_pct cases).

- [ ] **Step 5: Lint + type-check**

```powershell
uv run ruff check src/bubbles/api/v1/_dashboard_helpers.py tests/unit/test_dashboard_helpers.py
uv run mypy --strict src/bubbles/api/v1/_dashboard_helpers.py
```

Expected: both clean.

- [ ] **Step 6: Commit**

```bash
git add server/src/bubbles/api/v1/_dashboard_helpers.py server/tests/unit/test_dashboard_helpers.py
git commit -m "feat(dashboard): add resolve_range + delta_pct helpers with unit tests" -- server/src/bubbles/api/v1/_dashboard_helpers.py server/tests/unit/test_dashboard_helpers.py
git show --stat HEAD
```

Expected: exactly 2 files changed.

---

### Task 2: `db/repo/dashboard.py` + integration tests

**Files:**
- Create: `server/src/bubbles/db/repo/dashboard.py`
- Modify: `server/src/bubbles/db/repo/__init__.py`
- Create: `server/tests/integration/test_repo_dashboard.py`

- [ ] **Step 1: Write the failing integration tests**

Create `server/tests/integration/test_repo_dashboard.py`:

```python
"""dashboard repo integration tests.

Requires Docker (testcontainers Postgres); skipped automatically without it.
Toggle on via: $env:RUN_INTEGRATION='1'
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest

from bubbles.db.repo import dashboard as repo

pytestmark = pytest.mark.integration


@pytest.mark.asyncio
async def test_series_xp_fills_zero_buckets(pool, user_id: UUID) -> None:
    now = datetime.now(UTC)
    start = now - timedelta(days=3)
    async with pool.acquire() as conn:
        async with conn.transaction():
            # Insert one XP row in the middle bucket.
            await conn.execute(
                "INSERT INTO xp_transactions (user_id, amount, source_type, created_at) "
                "VALUES ($1, 10, 'test', $2)",
                user_id,
                now - timedelta(days=1, hours=12),
            )
        async with conn.transaction():
            rows = await repo.series_xp(
                conn, user_id=user_id, start=start, end=now, step="1 day"
            )
    # 3 daily buckets covering [start, end). Buckets are inclusive on left.
    assert len(rows) == 3
    # The middle bucket (≈1.5 days ago) has the 10 XP; the other two are 0.
    nonzero = [r for r in rows if r.value > 0]
    assert len(nonzero) == 1
    assert nonzero[0].value == 10


@pytest.mark.asyncio
async def test_series_sessions_counts_only_ended_sessions(pool, user_id: UUID) -> None:
    now = datetime.now(UTC)
    start = now - timedelta(days=2)
    async with pool.acquire() as conn:
        async with conn.transaction():
            sid_ended = uuid4()
            sid_open = uuid4()
            await conn.execute(
                "INSERT INTO sessions (id, user_id, ended_at, created_at) "
                "VALUES ($1, $2, $3, $4)",
                sid_ended,
                user_id,
                now - timedelta(hours=6),
                now - timedelta(hours=7),
            )
            await conn.execute(
                "INSERT INTO sessions (id, user_id, ended_at, created_at) "
                "VALUES ($1, $2, NULL, $3)",
                sid_open,
                user_id,
                now - timedelta(hours=8),
            )
        async with conn.transaction():
            rows = await repo.series_sessions(
                conn, user_id=user_id, start=start, end=now, step="1 day"
            )
    assert sum(r.value for r in rows) == 1


@pytest.mark.asyncio
async def test_series_mistakes_counts_rows(pool, user_id: UUID, session_id: UUID) -> None:
    now = datetime.now(UTC)
    start = now - timedelta(days=2)
    async with pool.acquire() as conn:
        async with conn.transaction():
            for _ in range(3):
                await conn.execute(
                    "INSERT INTO user_mistakes (user_id, session_id, rule_id, category, snippet, source, created_at) "
                    "VALUES ($1, $2, 'X', 'cat', 'snip', 'llm', $3)",
                    user_id,
                    session_id,
                    now - timedelta(hours=1),
                )
        async with conn.transaction():
            rows = await repo.series_mistakes(
                conn, user_id=user_id, start=start, end=now, step="1 day"
            )
    assert sum(r.value for r in rows) == 3


@pytest.mark.asyncio
async def test_series_sentiment_returns_null_for_empty_buckets(
    pool, user_id: UUID, session_id: UUID
) -> None:
    now = datetime.now(UTC)
    start = now - timedelta(days=2)
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "INSERT INTO session_analytics (session_id, user_id, avg_sentiment_score, computed_at) "
                "VALUES ($1, $2, 0.5, $3)",
                session_id,
                user_id,
                now - timedelta(hours=6),
            )
        async with conn.transaction():
            rows = await repo.series_sentiment(
                conn, user_id=user_id, start=start, end=now, step="1 day"
            )
    has_value = [r for r in rows if r.value is not None]
    has_null = [r for r in rows if r.value is None]
    assert len(has_value) == 1
    assert has_value[0].value == pytest.approx(0.5)
    assert len(has_null) >= 1  # at least one empty bucket should be null, not 0


@pytest.mark.asyncio
async def test_series_talk_time_sums_seconds(pool, user_id: UUID, session_id: UUID) -> None:
    now = datetime.now(UTC)
    start = now - timedelta(days=2)
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "INSERT INTO session_analytics (session_id, user_id, total_duration_seconds, computed_at) "
                "VALUES ($1, $2, 600, $3)",
                session_id,
                user_id,
                now - timedelta(hours=6),
            )
        async with conn.transaction():
            rows = await repo.series_talk_time(
                conn, user_id=user_id, start=start, end=now, step="1 day"
            )
    assert sum(r.value for r in rows) == 600


@pytest.mark.asyncio
async def test_summary_window_cur_vs_prev(pool, user_id: UUID) -> None:
    now = datetime.now(UTC)
    cur_start = now - timedelta(days=30)
    prev_start = cur_start - timedelta(days=30)
    async with pool.acquire() as conn:
        async with conn.transaction():
            # 10 XP in current window, 5 XP in previous window
            await conn.execute(
                "INSERT INTO xp_transactions (user_id, amount, source_type, created_at) "
                "VALUES ($1, 10, 'test', $2)",
                user_id,
                now - timedelta(days=5),
            )
            await conn.execute(
                "INSERT INTO xp_transactions (user_id, amount, source_type, created_at) "
                "VALUES ($1, 5, 'test', $2)",
                user_id,
                now - timedelta(days=45),
            )
        async with conn.transaction():
            sw = await repo.summary_window(
                conn,
                user_id=user_id,
                cur_start=cur_start,
                cur_end=now,
                prev_start=prev_start,
                prev_end=cur_start,
            )
    assert sw.cur_xp == 10
    assert sw.prev_xp == 5


@pytest.mark.asyncio
async def test_snapshot_reads_gamification_and_due_count(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "INSERT INTO user_gamification (user_id, total_xp, level, current_streak) "
                "VALUES ($1, 500, 3, 4)",
                user_id,
            )
        async with conn.transaction():
            snap = await repo.snapshot(conn, user_id=user_id)
    assert snap.current_streak == 4
    assert snap.level == 3
    assert snap.due_drill_count == 0
    assert snap.drill_mastery_pct is None  # no drill cards seeded


@pytest.mark.asyncio
async def test_series_cross_user_isolation(
    pool, user_id: UUID, other_user_id: UUID
) -> None:
    now = datetime.now(UTC)
    start = now - timedelta(days=2)
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "INSERT INTO xp_transactions (user_id, amount, source_type, created_at) "
                "VALUES ($1, 100, 'test', $2)",
                other_user_id,
                now - timedelta(hours=2),
            )
        async with conn.transaction():
            rows = await repo.series_xp(
                conn, user_id=user_id, start=start, end=now, step="1 day"
            )
    assert sum(r.value for r in rows) == 0
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
$env:RUN_INTEGRATION = '1'
uv run pytest tests/integration/test_repo_dashboard.py -v --no-cov
```

Expected: `ModuleNotFoundError: No module named 'bubbles.db.repo.dashboard'`. (If Docker is unavailable, the suite skips at collection — that's also a valid "fail" signal; proceed to write the repo and rely on static checks.)

- [ ] **Step 3: Write the repo**

Create `server/src/bubbles/db/repo/dashboard.py`:

```python
"""Dashboard repo — on-the-fly time-bucketed aggregates for the progress view.

No writes. Every series query uses ``generate_series(start, end, step)``
LEFT JOIN raw aggregates so empty buckets emit ``0`` (or ``NULL`` for
sentiment). Bound by ``(user_id, created_at)`` indexes on the raw
tables; current data scale makes 365-day windows comfortably sub-200ms.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from uuid import UUID

import asyncpg


@dataclass(frozen=True, slots=True)
class BucketPoint:
    """A single bucket with an integer value (XP, counts, talk-time seconds)."""

    bucket: date
    value: int


@dataclass(frozen=True, slots=True)
class BucketPointF:
    """A single bucket with a nullable float (sentiment — null if no data)."""

    bucket: date
    value: float | None


@dataclass(frozen=True, slots=True)
class SummaryWindow:
    """Current and previous-window totals for the five windowed metrics."""

    cur_xp: int
    prev_xp: int
    cur_sessions: int
    prev_sessions: int
    cur_mistakes: int
    prev_mistakes: int
    cur_sentiment: float | None
    prev_sentiment: float | None
    cur_talk_seconds: float
    prev_talk_seconds: float


@dataclass(frozen=True, slots=True)
class SummarySnapshot:
    """Non-windowed values: mastery %, streak, level, due drill count."""

    drill_mastery_pct: int | None
    current_streak: int
    level: int
    due_drill_count: int


async def series_xp(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    start: datetime,
    end: datetime,
    step: str,
) -> list[BucketPoint]:
    rows = await conn.fetch(
        """
        SELECT b.bucket::date AS bucket,
               COALESCE(SUM(x.amount), 0)::int AS value
        FROM generate_series($1::timestamptz, $2::timestamptz - $3::interval, $3::interval)
             AS b(bucket)
        LEFT JOIN xp_transactions x
          ON x.user_id = $4
         AND x.amount > 0
         AND x.created_at >= b.bucket
         AND x.created_at <  b.bucket + $3::interval
        GROUP BY b.bucket
        ORDER BY b.bucket ASC
        """,
        start,
        end,
        step,
        user_id,
    )
    return [BucketPoint(bucket=r["bucket"], value=int(r["value"])) for r in rows]


async def series_sessions(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    start: datetime,
    end: datetime,
    step: str,
) -> list[BucketPoint]:
    rows = await conn.fetch(
        """
        SELECT b.bucket::date AS bucket,
               COALESCE(COUNT(s.id), 0)::int AS value
        FROM generate_series($1::timestamptz, $2::timestamptz - $3::interval, $3::interval)
             AS b(bucket)
        LEFT JOIN sessions s
          ON s.user_id = $4
         AND s.ended_at IS NOT NULL
         AND s.deleted_at IS NULL
         AND s.ended_at >= b.bucket
         AND s.ended_at <  b.bucket + $3::interval
        GROUP BY b.bucket
        ORDER BY b.bucket ASC
        """,
        start,
        end,
        step,
        user_id,
    )
    return [BucketPoint(bucket=r["bucket"], value=int(r["value"])) for r in rows]


async def series_mistakes(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    start: datetime,
    end: datetime,
    step: str,
) -> list[BucketPoint]:
    rows = await conn.fetch(
        """
        SELECT b.bucket::date AS bucket,
               COALESCE(COUNT(m.id), 0)::int AS value
        FROM generate_series($1::timestamptz, $2::timestamptz - $3::interval, $3::interval)
             AS b(bucket)
        LEFT JOIN user_mistakes m
          ON m.user_id = $4
         AND m.created_at >= b.bucket
         AND m.created_at <  b.bucket + $3::interval
        GROUP BY b.bucket
        ORDER BY b.bucket ASC
        """,
        start,
        end,
        step,
        user_id,
    )
    return [BucketPoint(bucket=r["bucket"], value=int(r["value"])) for r in rows]


async def series_sentiment(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    start: datetime,
    end: datetime,
    step: str,
) -> list[BucketPointF]:
    rows = await conn.fetch(
        """
        SELECT b.bucket::date AS bucket,
               AVG(sa.avg_sentiment_score)::float AS value
        FROM generate_series($1::timestamptz, $2::timestamptz - $3::interval, $3::interval)
             AS b(bucket)
        LEFT JOIN session_analytics sa
          ON sa.user_id = $4
         AND sa.computed_at >= b.bucket
         AND sa.computed_at <  b.bucket + $3::interval
         AND sa.avg_sentiment_score IS NOT NULL
        GROUP BY b.bucket
        ORDER BY b.bucket ASC
        """,
        start,
        end,
        step,
        user_id,
    )
    return [
        BucketPointF(
            bucket=r["bucket"],
            value=float(r["value"]) if r["value"] is not None else None,
        )
        for r in rows
    ]


async def series_talk_time(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    start: datetime,
    end: datetime,
    step: str,
) -> list[BucketPoint]:
    """Talk-time per bucket in seconds. Route converts to minutes for the response shape."""
    rows = await conn.fetch(
        """
        SELECT b.bucket::date AS bucket,
               COALESCE(SUM(sa.total_duration_seconds), 0)::int AS value
        FROM generate_series($1::timestamptz, $2::timestamptz - $3::interval, $3::interval)
             AS b(bucket)
        LEFT JOIN session_analytics sa
          ON sa.user_id = $4
         AND sa.computed_at >= b.bucket
         AND sa.computed_at <  b.bucket + $3::interval
        GROUP BY b.bucket
        ORDER BY b.bucket ASC
        """,
        start,
        end,
        step,
        user_id,
    )
    return [BucketPoint(bucket=r["bucket"], value=int(r["value"])) for r in rows]


async def summary_window(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    cur_start: datetime,
    cur_end: datetime,
    prev_start: datetime,
    prev_end: datetime,
) -> SummaryWindow:
    """Current vs previous totals over a single bounded scan per source table.

    Five separate single-row queries — one per metric. Each uses ``FILTER
    (WHERE …)`` to compute the current-window and previous-window total
    in a single pass over rows ``>= prev_start``, so the planner uses
    one ``(user_id, time)`` index scan per metric.
    """
    xp = await conn.fetchrow(
        """
        SELECT
          COALESCE(SUM(amount) FILTER (
            WHERE created_at >= $2 AND created_at < $3), 0)::int AS cur_xp,
          COALESCE(SUM(amount) FILTER (
            WHERE created_at >= $4 AND created_at < $5), 0)::int AS prev_xp
        FROM xp_transactions
        WHERE user_id = $1 AND amount > 0 AND created_at >= $4
        """,
        user_id,
        cur_start,
        cur_end,
        prev_start,
        prev_end,
    )
    sessions = await conn.fetchrow(
        """
        SELECT
          COUNT(*) FILTER (
            WHERE ended_at >= $2 AND ended_at < $3)::int AS cur_sessions,
          COUNT(*) FILTER (
            WHERE ended_at >= $4 AND ended_at < $5)::int AS prev_sessions
        FROM sessions
        WHERE user_id = $1 AND deleted_at IS NULL
          AND ended_at IS NOT NULL AND ended_at >= $4
        """,
        user_id,
        cur_start,
        cur_end,
        prev_start,
        prev_end,
    )
    mistakes = await conn.fetchrow(
        """
        SELECT
          COUNT(*) FILTER (
            WHERE created_at >= $2 AND created_at < $3)::int AS cur_mistakes,
          COUNT(*) FILTER (
            WHERE created_at >= $4 AND created_at < $5)::int AS prev_mistakes
        FROM user_mistakes
        WHERE user_id = $1 AND created_at >= $4
        """,
        user_id,
        cur_start,
        cur_end,
        prev_start,
        prev_end,
    )
    sentiment = await conn.fetchrow(
        """
        SELECT
          AVG(avg_sentiment_score) FILTER (
            WHERE computed_at >= $2 AND computed_at < $3)::float AS cur_sentiment,
          AVG(avg_sentiment_score) FILTER (
            WHERE computed_at >= $4 AND computed_at < $5)::float AS prev_sentiment
        FROM session_analytics
        WHERE user_id = $1 AND computed_at >= $4 AND avg_sentiment_score IS NOT NULL
        """,
        user_id,
        cur_start,
        cur_end,
        prev_start,
        prev_end,
    )
    talk = await conn.fetchrow(
        """
        SELECT
          COALESCE(SUM(total_duration_seconds) FILTER (
            WHERE computed_at >= $2 AND computed_at < $3), 0)::float AS cur_talk,
          COALESCE(SUM(total_duration_seconds) FILTER (
            WHERE computed_at >= $4 AND computed_at < $5), 0)::float AS prev_talk
        FROM session_analytics
        WHERE user_id = $1 AND computed_at >= $4
        """,
        user_id,
        cur_start,
        cur_end,
        prev_start,
        prev_end,
    )
    assert xp is not None and sessions is not None and mistakes is not None
    assert sentiment is not None and talk is not None
    return SummaryWindow(
        cur_xp=int(xp["cur_xp"]),
        prev_xp=int(xp["prev_xp"]),
        cur_sessions=int(sessions["cur_sessions"]),
        prev_sessions=int(sessions["prev_sessions"]),
        cur_mistakes=int(mistakes["cur_mistakes"]),
        prev_mistakes=int(mistakes["prev_mistakes"]),
        cur_sentiment=(
            float(sentiment["cur_sentiment"]) if sentiment["cur_sentiment"] is not None else None
        ),
        prev_sentiment=(
            float(sentiment["prev_sentiment"]) if sentiment["prev_sentiment"] is not None else None
        ),
        cur_talk_seconds=float(talk["cur_talk"]),
        prev_talk_seconds=float(talk["prev_talk"]),
    )


async def snapshot(conn: asyncpg.Connection, *, user_id: UUID) -> SummarySnapshot:
    """Non-windowed snapshot: drill mastery, streak, level, due drill count."""
    mastery = await conn.fetchval(
        """
        SELECT ROUND(AVG(100.0 * total_correct / NULLIF(total_reviews, 0)))::int
        FROM drill_cards
        WHERE user_id = $1 AND retired_at IS NULL AND total_reviews > 0
        """,
        user_id,
    )
    g = await conn.fetchrow(
        "SELECT current_streak, level FROM user_gamification WHERE user_id = $1",
        user_id,
    )
    due = await conn.fetchval(
        """
        SELECT COUNT(*)::int FROM drill_cards
        WHERE user_id = $1 AND retired_at IS NULL AND due_at <= now()
        """,
        user_id,
    )
    return SummarySnapshot(
        drill_mastery_pct=int(mastery) if mastery is not None else None,
        current_streak=int(g["current_streak"]) if g is not None else 0,
        level=int(g["level"]) if g is not None else 1,
        due_drill_count=int(due or 0),
    )
```

- [ ] **Step 4: Register the repo**

Open `server/src/bubbles/db/repo/__init__.py`. Add the import alongside `drill_cards`, `scenarios`:

```python
from bubbles.db.repo import dashboard as dashboard  # noqa: F401
```

(If the file uses an explicit `__all__`, append `"dashboard"`.)

- [ ] **Step 5: Run tests to verify they pass**

```powershell
$env:RUN_INTEGRATION = '1'
uv run pytest tests/integration/test_repo_dashboard.py -v --no-cov
```

Expected: 8 tests passed. (If Docker is unavailable, expect `SKIPPED` — that's acceptable; rely on Step 6 for confidence.)

- [ ] **Step 6: Lint + type-check**

```powershell
uv run ruff check src/bubbles/db/repo/dashboard.py src/bubbles/db/repo/__init__.py tests/integration/test_repo_dashboard.py
uv run mypy --strict src/bubbles/db/repo/dashboard.py
```

Expected: both clean.

- [ ] **Step 7: Commit**

```bash
git add server/src/bubbles/db/repo/dashboard.py server/src/bubbles/db/repo/__init__.py server/tests/integration/test_repo_dashboard.py
git commit -m "feat(dashboard): repo with 5 time-bucketed series + summary + snapshot" -- server/src/bubbles/db/repo/dashboard.py server/src/bubbles/db/repo/__init__.py server/tests/integration/test_repo_dashboard.py
git show --stat HEAD
```

Expected: exactly 3 files changed.

---

### Task 3: Dashboard schemas

**Files:**
- Modify: `server/src/bubbles/api/v1/_schemas.py`

- [ ] **Step 1: Sanity-check current state**

```powershell
uv run python -c "from bubbles.api.v1._schemas import DashboardResponse" 2>&1
```

Expected: `ImportError: cannot import name 'DashboardResponse' from 'bubbles.api.v1._schemas'`.

- [ ] **Step 2: Append the schemas**

Open `server/src/bubbles/api/v1/_schemas.py`. At the end of the file (after the last drill-cards section from F2), append:

```python


# ---- progress dashboard (F3) ---------------------------------------------


class BucketPointOut(_Base):
    """A single time-bucket with an integer value."""

    bucket: date
    value: int = Field(ge=0)


class BucketPointFOut(_Base):
    """A single time-bucket with a nullable float (sentiment)."""

    bucket: date
    value: float | None = None


class MetricDelta(_Base):
    """Current/previous window pair with rounded percentage delta."""

    current: float
    previous: float
    delta_pct: float | None = None


class DashboardSummary(_Base):
    total_xp: MetricDelta
    sessions: MetricDelta
    mistakes: MetricDelta
    avg_sentiment: MetricDelta
    talk_time_minutes: MetricDelta
    drill_mastery_pct: int | None = None
    current_streak: int = Field(ge=0)
    level: int = Field(ge=1)
    due_drill_count: int = Field(ge=0)


class DashboardSeries(_Base):
    xp_per_bucket: list[BucketPointOut]
    sessions_per_bucket: list[BucketPointOut]
    mistakes_per_bucket: list[BucketPointOut]
    avg_sentiment_per_bucket: list[BucketPointFOut]
    talk_time_minutes_per_bucket: list[BucketPointOut]


class DashboardWindow(_Base):
    start: datetime
    end: datetime


class DashboardResponse(_Base):
    range: Literal["30d", "90d", "365d"]
    granularity: Literal["daily", "weekly", "monthly"]
    window: DashboardWindow
    summary: DashboardSummary
    series: DashboardSeries
```

(`date`, `datetime`, `Literal`, `Field`, `_Base` are already imported at the top of the file.)

- [ ] **Step 3: Verify imports**

```powershell
uv run python -c "from bubbles.api.v1._schemas import DashboardResponse, DashboardSeries, DashboardSummary, DashboardWindow, MetricDelta, BucketPointOut, BucketPointFOut; print('ok')"
```

Expected: prints `ok`.

- [ ] **Step 4: Lint + type-check**

```powershell
uv run ruff check src/bubbles/api/v1/_schemas.py
uv run mypy --strict src/bubbles/api/v1/_schemas.py
```

Expected: both clean.

- [ ] **Step 5: Commit**

```bash
git add server/src/bubbles/api/v1/_schemas.py
git commit -m "feat(dashboard): add dashboard response schemas" -- server/src/bubbles/api/v1/_schemas.py
git show --stat HEAD
```

Expected: exactly 1 file changed.

---

### Task 4: Dashboard route + router registration + integration tests

**Files:**
- Create: `server/src/bubbles/api/v1/dashboard.py`
- Modify: `server/src/bubbles/api/router.py`
- Create: `server/tests/integration/test_routes_dashboard.py`

- [ ] **Step 1: Write the failing integration tests**

Create `server/tests/integration/test_routes_dashboard.py`:

```python
"""Dashboard route integration tests."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import current_user
from bubbles.deps import RateLimiterDep, get_pool
from bubbles.models.user import CurrentUser

pytestmark = pytest.mark.integration


class _FakeLimiter:
    async def check(self, key: str, *, capacity: int, refill_per_s: float) -> object:
        class _RL:
            allowed = True
            retry_after_s = 0.0

        return _RL()


def _override(app: FastAPI, pool, uid: UUID) -> None:
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email="t@t", roles=[]
    )
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[RateLimiterDep] = lambda: _FakeLimiter()


@pytest.mark.asyncio
async def test_dashboard_30d_returns_daily_granularity(
    app: FastAPI, pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/dashboard?range=30d")
    assert r.status_code == 200
    body = r.json()
    assert body["range"] == "30d"
    assert body["granularity"] == "daily"
    assert len(body["series"]["xp_per_bucket"]) == 30
    assert all(p["value"] == 0 for p in body["series"]["xp_per_bucket"])
    assert body["summary"]["current_streak"] == 0
    assert body["summary"]["level"] == 1


@pytest.mark.asyncio
async def test_dashboard_90d_returns_weekly(
    app: FastAPI, pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/dashboard?range=90d")
    assert r.status_code == 200
    body = r.json()
    assert body["granularity"] == "weekly"
    # 90 days / 7 = ~13 buckets
    assert 12 <= len(body["series"]["xp_per_bucket"]) <= 14


@pytest.mark.asyncio
async def test_dashboard_365d_returns_monthly(
    app: FastAPI, pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/dashboard?range=365d")
    assert r.status_code == 200
    body = r.json()
    assert body["granularity"] == "monthly"
    assert 11 <= len(body["series"]["xp_per_bucket"]) <= 13


@pytest.mark.asyncio
async def test_dashboard_bad_range_returns_400(
    app: FastAPI, pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/dashboard?range=7d")
    assert r.status_code == 400


@pytest.mark.asyncio
async def test_dashboard_owner_scoped(
    app: FastAPI, pool, user_id: UUID, other_user_id: UUID
) -> None:
    # Seed XP for the OTHER user; current user should still see zero.
    now = datetime.now(UTC)
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "INSERT INTO xp_transactions (user_id, amount, source_type, created_at) "
                "VALUES ($1, 500, 'test', $2)",
                other_user_id,
                now - timedelta(days=1),
            )
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/dashboard?range=30d")
    body = r.json()
    assert body["summary"]["total_xp"]["current"] == 0


@pytest.mark.asyncio
async def test_dashboard_summary_includes_xp_delta(
    app: FastAPI, pool, user_id: UUID
) -> None:
    now = datetime.now(UTC)
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "INSERT INTO xp_transactions (user_id, amount, source_type, created_at) "
                "VALUES ($1, 100, 'test', $2)",
                user_id,
                now - timedelta(days=5),
            )
            await conn.execute(
                "INSERT INTO xp_transactions (user_id, amount, source_type, created_at) "
                "VALUES ($1, 50, 'test', $2)",
                user_id,
                now - timedelta(days=45),
            )
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/dashboard?range=30d")
    body = r.json()
    assert body["summary"]["total_xp"]["current"] == 100
    assert body["summary"]["total_xp"]["previous"] == 50
    assert body["summary"]["total_xp"]["delta_pct"] == 100.0
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
$env:RUN_INTEGRATION = '1'
uv run pytest tests/integration/test_routes_dashboard.py -v --no-cov
```

Expected: 404 on every endpoint (router not registered yet) — or skip on Docker absence.

- [ ] **Step 3: Write the router**

Create `server/src/bubbles/api/v1/dashboard.py`:

```python
"""Progress dashboard route.

Single omnibus endpoint ``GET /v1/dashboard?range={30d|90d|365d}``.
Returns time-bucketed series (XP, sessions, mistakes, sentiment,
talk-time) and a snapshot summary with previous-window deltas. Reads
only; bound by ``(user_id, time)`` indexes on the source tables.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Literal, cast
from uuid import UUID

from fastapi import APIRouter, Query

from bubbles.api.v1._dashboard_helpers import RANGES, delta_pct, resolve_range
from bubbles.api.v1._schemas import (
    BucketPointFOut,
    BucketPointOut,
    DashboardResponse,
    DashboardSeries,
    DashboardSummary,
    DashboardWindow,
    MetricDelta,
)
from bubbles.auth.current_user import CurrentUserDep
from bubbles.core.errors import BadRequest, RateLimited
from bubbles.core.logging import get_logger
from bubbles.db.repo import dashboard as dashboard_repo
from bubbles.db.uow import transaction
from bubbles.deps import PoolDep, RateLimiterDep

log = get_logger(__name__)
router = APIRouter(tags=["dashboard"])

_RATE_CAPACITY = 30
_RATE_REFILL_PER_S = 30 / 60  # ~30 dashboard fetches per minute per user


def _to_int_buckets(rows: list[dashboard_repo.BucketPoint]) -> list[BucketPointOut]:
    return [BucketPointOut(bucket=r.bucket, value=r.value) for r in rows]


def _to_float_buckets(rows: list[dashboard_repo.BucketPointF]) -> list[BucketPointFOut]:
    return [BucketPointFOut(bucket=r.bucket, value=r.value) for r in rows]


def _seconds_buckets_to_minutes(
    rows: list[dashboard_repo.BucketPoint],
) -> list[BucketPointOut]:
    """Round seconds → whole minutes for the response shape."""
    return [BucketPointOut(bucket=r.bucket, value=round(r.value / 60)) for r in rows]


@router.get("/dashboard", response_model=DashboardResponse)
async def get_dashboard(
    user: CurrentUserDep,
    pool: PoolDep,
    limiter: RateLimiterDep,
    range_arg: str = Query("30d", alias="range"),
) -> DashboardResponse:
    rl = await limiter.check(
        f"dashboard:{user.id}",
        capacity=_RATE_CAPACITY,
        refill_per_s=_RATE_REFILL_PER_S,
    )
    if not rl.allowed:
        raise RateLimited(rl.retry_after_s)

    if range_arg not in RANGES:
        raise BadRequest(f"unknown range: {range_arg!r}")
    range_lit = cast(Literal["30d", "90d", "365d"], range_arg)

    cur_start, cur_end, prev_start, prev_end, step, granularity = resolve_range(
        range_arg, datetime.now(UTC)
    )

    uid = UUID(user.id)
    async with transaction(pool) as conn:
        xp_rows = await dashboard_repo.series_xp(
            conn, user_id=uid, start=cur_start, end=cur_end, step=step
        )
        sess_rows = await dashboard_repo.series_sessions(
            conn, user_id=uid, start=cur_start, end=cur_end, step=step
        )
        mist_rows = await dashboard_repo.series_mistakes(
            conn, user_id=uid, start=cur_start, end=cur_end, step=step
        )
        sent_rows = await dashboard_repo.series_sentiment(
            conn, user_id=uid, start=cur_start, end=cur_end, step=step
        )
        talk_rows = await dashboard_repo.series_talk_time(
            conn, user_id=uid, start=cur_start, end=cur_end, step=step
        )
        sw = await dashboard_repo.summary_window(
            conn,
            user_id=uid,
            cur_start=cur_start,
            cur_end=cur_end,
            prev_start=prev_start,
            prev_end=prev_end,
        )
        snap = await dashboard_repo.snapshot(conn, user_id=uid)

    cur_sent = sw.cur_sentiment if sw.cur_sentiment is not None else 0.0
    prev_sent = sw.prev_sentiment if sw.prev_sentiment is not None else 0.0
    cur_talk_min = sw.cur_talk_seconds / 60
    prev_talk_min = sw.prev_talk_seconds / 60

    summary = DashboardSummary(
        total_xp=MetricDelta(
            current=float(sw.cur_xp),
            previous=float(sw.prev_xp),
            delta_pct=delta_pct(sw.cur_xp, sw.prev_xp),
        ),
        sessions=MetricDelta(
            current=float(sw.cur_sessions),
            previous=float(sw.prev_sessions),
            delta_pct=delta_pct(sw.cur_sessions, sw.prev_sessions),
        ),
        mistakes=MetricDelta(
            current=float(sw.cur_mistakes),
            previous=float(sw.prev_mistakes),
            delta_pct=delta_pct(sw.cur_mistakes, sw.prev_mistakes),
        ),
        avg_sentiment=MetricDelta(
            current=cur_sent,
            previous=prev_sent,
            delta_pct=delta_pct(cur_sent, prev_sent),
        ),
        talk_time_minutes=MetricDelta(
            current=round(cur_talk_min, 1),
            previous=round(prev_talk_min, 1),
            delta_pct=delta_pct(cur_talk_min, prev_talk_min),
        ),
        drill_mastery_pct=snap.drill_mastery_pct,
        current_streak=snap.current_streak,
        level=snap.level,
        due_drill_count=snap.due_drill_count,
    )

    series = DashboardSeries(
        xp_per_bucket=_to_int_buckets(xp_rows),
        sessions_per_bucket=_to_int_buckets(sess_rows),
        mistakes_per_bucket=_to_int_buckets(mist_rows),
        avg_sentiment_per_bucket=_to_float_buckets(sent_rows),
        talk_time_minutes_per_bucket=_seconds_buckets_to_minutes(talk_rows),
    )

    log.info("dashboard_done", user=user.id, range=range_arg, granularity=granularity)

    return DashboardResponse(
        range=range_lit,
        granularity=cast(Literal["daily", "weekly", "monthly"], granularity),
        window=DashboardWindow(start=cur_start, end=cur_end),
        summary=summary,
        series=series,
    )
```

- [ ] **Step 4: Register the router**

Open `server/src/bubbles/api/router.py`. Add the import alphabetically next to the existing v1 sub-routers (e.g., between `dashboard` slot and `drills`):

```python
from bubbles.api.v1.dashboard import router as dashboard_router
```

And register it alongside the others (alphabetical position; mirror the existing `v1_router.include_router(...)` lines):

```python
v1_router.include_router(dashboard_router)
```

(If the file uses `api_router.include_router(...)` or a different naming scheme, mirror that — read the file to see the existing scenarios/drills registration and use the same style.)

- [ ] **Step 5: Run the tests to verify they pass**

```powershell
$env:RUN_INTEGRATION = '1'
uv run pytest tests/integration/test_routes_dashboard.py -v --no-cov
```

Expected: 6 tests passed (or skip on Docker absence).

- [ ] **Step 6: Smoke check OpenAPI surface**

```powershell
uv run python -c "from bubbles.api.app import build_app; app = build_app(); paths = sorted({getattr(r, 'path', '') for r in app.routes}); print([p for p in paths if 'dashboard' in p])"
```

Expected: prints `['/v1/dashboard']`.

- [ ] **Step 7: Lint + type-check**

```powershell
uv run ruff check src/bubbles/api/v1/dashboard.py src/bubbles/api/router.py tests/integration/test_routes_dashboard.py
uv run mypy --strict src/bubbles/api/v1/dashboard.py src/bubbles/api/router.py
```

Expected: both clean.

- [ ] **Step 8: Commit**

```bash
git add server/src/bubbles/api/v1/dashboard.py server/src/bubbles/api/router.py server/tests/integration/test_routes_dashboard.py
git commit -m "feat(dashboard): GET /v1/dashboard route + registration" -- server/src/bubbles/api/v1/dashboard.py server/src/bubbles/api/router.py server/tests/integration/test_routes_dashboard.py
git show --stat HEAD
```

Expected: exactly 3 files changed.

---

## After all tasks

- [ ] **Final review**

```powershell
git log --oneline main..HEAD
```

Expected: 5 commits — 1 spec + 4 implementation tasks.

```powershell
git diff --stat main..HEAD
```

Expected: ~9 files changed, ~1400 lines added.

- [ ] **OpenAPI sanity check**

```powershell
uv run python -c "from bubbles.api.app import build_app; app = build_app(); paths = sorted(getattr(r, 'path', '') for r in app.routes); print([p for p in paths if p.startswith('/v1/dashboard')])"
```

Expected: prints `['/v1/dashboard']`.

- [ ] **App-side doc**

After the implementation is green, write the app-side handoff doc at `Documentation/feature-3-progress-dashboard.md`. Cover: the single endpoint and its query params, the response schema (summary + series), UI states (empty user with no data → all-zeros chart; full-history user → real chart), refresh cadence (tab open + pull-to-refresh), error handling (`400` bad range, `429` rate-limited), and the file map. Same depth as `Documentation/feature-1-personalized-roleplay.md` and `Documentation/feature-2-spaced-repetition-drills.md`.

(The doc step lives outside the 4 implementation tasks; it is a separate commit after the feature is green and merge-ready.)
