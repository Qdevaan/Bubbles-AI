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
    # The middle bucket (~1.5 days ago) has the 10 XP; the other two are 0.
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
