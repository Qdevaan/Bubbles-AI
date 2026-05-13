"""Analytics repo — session_analytics, coaching_reports, trends, digest reads.

``coaching_reports`` has no unique constraint on ``session_id`` in the live
schema, so ``upsert_coaching_report`` does DELETE-then-INSERT inside the
caller's transaction (the worker wraps its writes in a UnitOfWork). Safe
because the worker is idempotent per session.
"""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any
from uuid import UUID

import asyncpg

from bubbles.db.models import CoachingReport, SessionAnalytics

_SA_COLS = (
    "session_id, user_id, total_turns, user_turns, others_turns, llm_turns, "
    "user_word_count, assistant_word_count, average_latency_ms, avg_advice_latency_ms, "
    "total_duration_seconds, memories_saved, events_extracted, highlights_created, "
    "avg_sentiment_score, dominant_sentiment, topic_summary, computed_at"
)

_CR_COLS = (
    "id, user_id, session_id, model_used, user_talk_pct, others_talk_pct, "
    "key_topics, key_decisions, action_items, follow_up_people, filler_words, "
    "filler_word_count, tone_summary, engagement_trend, suggestions, strengths, "
    "areas_of_improvement, report_text, report_content, generated_at"
)


def _list(value: Any) -> list[str]:
    if not value:
        return []
    return [str(v) for v in value]


def _int(value: Any) -> int:
    return int(value) if value is not None else 0


def _float(value: Any) -> float | None:
    return float(value) if value is not None else None


def _session_analytics(row: asyncpg.Record) -> SessionAnalytics:
    return SessionAnalytics(
        session_id=row["session_id"],
        user_id=row["user_id"],
        total_turns=_int(row["total_turns"]),
        user_turns=_int(row["user_turns"]),
        others_turns=_int(row["others_turns"]),
        llm_turns=_int(row["llm_turns"]),
        user_word_count=_int(row["user_word_count"]),
        assistant_word_count=_int(row["assistant_word_count"]),
        average_latency_ms=row["average_latency_ms"],
        avg_advice_latency_ms=_float(row["avg_advice_latency_ms"]),
        total_duration_seconds=_float(row["total_duration_seconds"]),
        memories_saved=_int(row["memories_saved"]),
        events_extracted=_int(row["events_extracted"]),
        highlights_created=_int(row["highlights_created"]),
        avg_sentiment_score=_float(row["avg_sentiment_score"]),
        dominant_sentiment=row["dominant_sentiment"],
        topic_summary=row["topic_summary"],
        computed_at=row["computed_at"],
    )


def _coaching_report(row: asyncpg.Record) -> CoachingReport:
    raw_content = row["report_content"]
    if isinstance(raw_content, str):
        content: dict[str, Any] = json.loads(raw_content)
    elif raw_content is None:
        content = {}
    else:
        content = dict(raw_content)
    return CoachingReport(
        id=row["id"],
        user_id=row["user_id"],
        session_id=row["session_id"],
        model_used=row["model_used"],
        user_talk_pct=_float(row["user_talk_pct"]),
        others_talk_pct=_float(row["others_talk_pct"]),
        key_topics=_list(row["key_topics"]),
        key_decisions=_list(row["key_decisions"]),
        action_items=_list(row["action_items"]),
        follow_up_people=_list(row["follow_up_people"]),
        filler_words=_list(row["filler_words"]),
        filler_word_count=_int(row["filler_word_count"]),
        tone_summary=row["tone_summary"],
        engagement_trend=row["engagement_trend"],
        suggestions=_list(row["suggestions"]),
        strengths=_list(row["strengths"]),
        areas_of_improvement=_list(row["areas_of_improvement"]),
        report_text=row["report_text"],
        report_content=content,
        generated_at=row["generated_at"],
    )


# --- session_analytics -----------------------------------------------------


async def get_session_analytics(
    conn: asyncpg.Connection, *, session_id: UUID
) -> SessionAnalytics | None:
    row = await conn.fetchrow(
        f"SELECT {_SA_COLS} FROM session_analytics WHERE session_id = $1", session_id
    )
    return _session_analytics(row) if row is not None else None


async def upsert_session_analytics(
    conn: asyncpg.Connection,
    *,
    session_id: UUID,
    user_id: UUID,
    total_turns: int,
    user_turns: int,
    others_turns: int,
    llm_turns: int,
    user_word_count: int,
    assistant_word_count: int,
    total_duration_seconds: float | None,
    memories_saved: int,
    events_extracted: int,
    highlights_created: int,
    topic_summary: str | None,
    average_latency_ms: int | None = None,
    avg_advice_latency_ms: float | None = None,
    avg_sentiment_score: float | None = None,
    dominant_sentiment: str | None = None,
) -> None:
    await conn.execute(
        """
        INSERT INTO session_analytics (
            session_id, user_id, total_turns, user_turns, others_turns, llm_turns,
            user_word_count, assistant_word_count, total_duration_seconds,
            memories_saved, events_extracted, highlights_created, topic_summary,
            average_latency_ms, avg_advice_latency_ms, avg_sentiment_score,
            dominant_sentiment, computed_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
                $14, $15, $16, $17, now())
        ON CONFLICT (session_id) DO UPDATE SET
            user_id = EXCLUDED.user_id,
            total_turns = EXCLUDED.total_turns,
            user_turns = EXCLUDED.user_turns,
            others_turns = EXCLUDED.others_turns,
            llm_turns = EXCLUDED.llm_turns,
            user_word_count = EXCLUDED.user_word_count,
            assistant_word_count = EXCLUDED.assistant_word_count,
            total_duration_seconds = EXCLUDED.total_duration_seconds,
            memories_saved = EXCLUDED.memories_saved,
            events_extracted = EXCLUDED.events_extracted,
            highlights_created = EXCLUDED.highlights_created,
            topic_summary = EXCLUDED.topic_summary,
            average_latency_ms = COALESCE(EXCLUDED.average_latency_ms, session_analytics.average_latency_ms),
            avg_advice_latency_ms = COALESCE(EXCLUDED.avg_advice_latency_ms, session_analytics.avg_advice_latency_ms),
            avg_sentiment_score = COALESCE(EXCLUDED.avg_sentiment_score, session_analytics.avg_sentiment_score),
            dominant_sentiment = COALESCE(EXCLUDED.dominant_sentiment, session_analytics.dominant_sentiment),
            computed_at = now()
        """,
        session_id,
        user_id,
        total_turns,
        user_turns,
        others_turns,
        llm_turns,
        user_word_count,
        assistant_word_count,
        total_duration_seconds,
        memories_saved,
        events_extracted,
        highlights_created,
        topic_summary,
        average_latency_ms,
        avg_advice_latency_ms,
        avg_sentiment_score,
        dominant_sentiment,
    )


async def sentiment_trend_for_session(conn: asyncpg.Connection, *, session_id: UUID) -> list[float]:
    """Ordered list of per-turn sentiment scores (turns without a score are skipped)."""
    rows = await conn.fetch(
        """
        SELECT sentiment_score FROM session_logs
        WHERE session_id = $1 AND sentiment_score IS NOT NULL
        ORDER BY turn_index ASC
        """,
        session_id,
    )
    return [float(r["sentiment_score"]) for r in rows]


# --- coaching_reports ------------------------------------------------------


async def get_coaching_report(
    conn: asyncpg.Connection, *, session_id: UUID
) -> CoachingReport | None:
    row = await conn.fetchrow(
        f"SELECT {_CR_COLS} FROM coaching_reports WHERE session_id = $1 "
        "ORDER BY generated_at DESC LIMIT 1",
        session_id,
    )
    return _coaching_report(row) if row is not None else None


async def upsert_coaching_report(
    conn: asyncpg.Connection,
    *,
    session_id: UUID,
    user_id: UUID,
    model_used: str | None,
    user_talk_pct: float | None,
    others_talk_pct: float | None,
    key_topics: list[str],
    key_decisions: list[str],
    action_items: list[str],
    follow_up_people: list[str],
    filler_words: list[str],
    filler_word_count: int,
    tone_summary: str | None,
    engagement_trend: str | None,
    suggestions: list[str],
    strengths: list[str],
    areas_of_improvement: list[str],
    report_text: str | None,
    report_content: dict[str, Any],
) -> None:
    await conn.execute("DELETE FROM coaching_reports WHERE session_id = $1", session_id)
    await conn.execute(
        """
        INSERT INTO coaching_reports (
            session_id, user_id, model_used, user_talk_pct, others_talk_pct,
            key_topics, key_decisions, action_items, follow_up_people, filler_words,
            filler_word_count, tone_summary, engagement_trend, suggestions, strengths,
            areas_of_improvement, report_text, report_content, generated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
                $16, $17, $18::jsonb, now())
        """,
        session_id,
        user_id,
        model_used,
        user_talk_pct,
        others_talk_pct,
        key_topics,
        key_decisions,
        action_items,
        follow_up_people,
        filler_words,
        filler_word_count,
        tone_summary,
        engagement_trend,
        suggestions,
        strengths,
        areas_of_improvement,
        report_text,
        json.dumps(report_content),
    )


# --- trends ----------------------------------------------------------------


async def trends_since(
    conn: asyncpg.Connection, *, user_id: UUID, since: datetime
) -> list[asyncpg.Record]:
    return list(
        await conn.fetch(
            """
            SELECT session_id, total_turns, user_word_count, assistant_word_count,
                   avg_sentiment_score, total_duration_seconds, computed_at
            FROM session_analytics
            WHERE user_id = $1 AND computed_at >= $2
            ORDER BY computed_at DESC
            """,
            user_id,
            since,
        )
    )


# --- digest reads ----------------------------------------------------------


async def digest_sessions(
    conn: asyncpg.Connection, *, user_id: UUID, since: datetime, limit: int = 20
) -> list[asyncpg.Record]:
    return list(
        await conn.fetch(
            """
            SELECT id, title, mode, status, created_at, summary
            FROM sessions
            WHERE user_id = $1 AND created_at >= $2 AND deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT $3
            """,
            user_id,
            since,
            limit,
        )
    )


async def digest_pending_tasks(
    conn: asyncpg.Connection, *, user_id: UUID, limit: int = 10
) -> list[asyncpg.Record]:
    return list(
        await conn.fetch(
            """
            SELECT id, title, status, priority
            FROM tasks
            WHERE user_id = $1 AND status = 'pending'
            ORDER BY created_at DESC
            LIMIT $2
            """,
            user_id,
            limit,
        )
    )


async def digest_top_entities(
    conn: asyncpg.Connection, *, user_id: UUID, limit: int = 5
) -> list[asyncpg.Record]:
    return list(
        await conn.fetch(
            """
            SELECT id, display_name, entity_type, mention_count
            FROM entities
            WHERE user_id = $1 AND is_archived = false
            ORDER BY mention_count DESC NULLS LAST
            LIMIT $2
            """,
            user_id,
            limit,
        )
    )


async def digest_recent_highlights(
    conn: asyncpg.Connection, *, user_id: UUID, since: datetime, limit: int = 5
) -> list[asyncpg.Record]:
    return list(
        await conn.fetch(
            """
            SELECT id, highlight_type, title, body
            FROM highlights
            WHERE user_id = $1 AND created_at >= $2
            ORDER BY created_at DESC
            LIMIT $3
            """,
            user_id,
            since,
            limit,
        )
    )


async def performance_window(
    conn: asyncpg.Connection, *, user_id: UUID, since: datetime, until: datetime | None = None
) -> dict[str, Any]:
    """Aggregate the metrics the performance summary needs over ``[since, until)``.

    ``until=None`` means open-ended (up to now). Counts a session toward
    frequency once it has been ended (``ended_at`` set) within the window.
    """
    session_count = await conn.fetchval(
        """
        SELECT count(*)::int FROM sessions
        WHERE user_id = $1 AND deleted_at IS NULL AND ended_at IS NOT NULL
          AND ended_at >= $2 AND ($3::timestamptz IS NULL OR ended_at < $3)
        """,
        user_id,
        since,
        until,
    )
    avg_sentiment = await conn.fetchval(
        """
        SELECT avg(avg_sentiment_score)::float FROM session_analytics
        WHERE user_id = $1 AND computed_at >= $2 AND ($3::timestamptz IS NULL OR computed_at < $3)
        """,
        user_id,
        since,
        until,
    )
    crow = await conn.fetchrow(
        """
        SELECT avg(user_talk_pct)::float AS talk_pct, avg(filler_word_count)::float AS filler
        FROM coaching_reports
        WHERE user_id = $1 AND generated_at >= $2 AND ($3::timestamptz IS NULL OR generated_at < $3)
        """,
        user_id,
        since,
        until,
    )
    return {
        "session_count": int(session_count or 0),
        "avg_sentiment": avg_sentiment,
        "avg_user_talk_pct": crow["talk_pct"] if crow else None,
        "avg_filler_count": crow["filler"] if crow else None,
    }
