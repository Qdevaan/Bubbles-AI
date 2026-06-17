# Purpose: Repository queries that power the dashboard endpoint (recent sessions, today XP, active quests).
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
    (WHERE ...)`` to compute the current-window and previous-window total
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
