"""Integration tests for the analytics repo."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import asyncpg
import pytest

from bubbles.db.repo import analytics as analytics_repo

pytestmark = pytest.mark.integration


async def _new_session(conn: asyncpg.Connection, user_id: UUID) -> UUID:
    sid = uuid4()
    await conn.execute(
        "INSERT INTO sessions (id, user_id, status) VALUES ($1, $2, 'ended')", sid, user_id
    )
    return sid


async def test_upsert_and_get_session_analytics(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        sid = await _new_session(conn, user_id)
        await analytics_repo.upsert_session_analytics(
            conn,
            session_id=sid,
            user_id=user_id,
            total_turns=4,
            user_turns=2,
            others_turns=1,
            llm_turns=1,
            user_word_count=10,
            assistant_word_count=8,
            total_duration_seconds=120.0,
            memories_saved=3,
            events_extracted=1,
            highlights_created=2,
            topic_summary="a chat",
        )
        row = await analytics_repo.get_session_analytics(conn, session_id=sid)
        assert row is not None
        assert row.total_turns == 4
        assert row.user_word_count == 10
        assert row.memories_saved == 3
        assert row.topic_summary == "a chat"
        assert row.average_latency_ms is None
        assert row.avg_sentiment_score is None
        await analytics_repo.upsert_session_analytics(
            conn,
            session_id=sid,
            user_id=user_id,
            total_turns=9,
            user_turns=5,
            others_turns=2,
            llm_turns=2,
            user_word_count=20,
            assistant_word_count=15,
            total_duration_seconds=240.0,
            memories_saved=4,
            events_extracted=2,
            highlights_created=3,
            topic_summary="updated",
        )
        row2 = await analytics_repo.get_session_analytics(conn, session_id=sid)
        assert row2 is not None
        assert row2.total_turns == 9
        assert row2.topic_summary == "updated"
        assert await analytics_repo.get_session_analytics(conn, session_id=uuid4()) is None


async def test_upsert_and_get_coaching_report(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        sid = await _new_session(conn, user_id)
        await analytics_repo.upsert_coaching_report(
            conn,
            session_id=sid,
            user_id=user_id,
            model_used="analytics.coaching",
            user_talk_pct=60.0,
            others_talk_pct=40.0,
            key_topics=["budget", "timeline"],
            key_decisions=["ship friday"],
            action_items=["email alice"],
            follow_up_people=["alice"],
            filler_words=["um", "like"],
            filler_word_count=7,
            tone_summary="warm",
            engagement_trend="rising",
            suggestions=["pause more"],
            strengths=["clear"],
            areas_of_improvement=["fillers"],
            report_text="Solid conversation.",
            report_content={"tone_clarity": 8, "tone_empathy": 7},
        )
        row = await analytics_repo.get_coaching_report(conn, session_id=sid)
        assert row is not None
        assert row.user_talk_pct == 60.0
        assert row.key_topics == ["budget", "timeline"]
        assert row.filler_word_count == 7
        assert row.report_content == {"tone_clarity": 8, "tone_empathy": 7}
        await analytics_repo.upsert_coaching_report(
            conn,
            session_id=sid,
            user_id=user_id,
            model_used="analytics.coaching",
            user_talk_pct=55.0,
            others_talk_pct=45.0,
            key_topics=["new"],
            key_decisions=[],
            action_items=[],
            follow_up_people=[],
            filler_words=[],
            filler_word_count=0,
            tone_summary=None,
            engagement_trend=None,
            suggestions=[],
            strengths=[],
            areas_of_improvement=[],
            report_text=None,
            report_content={},
        )
        again = await analytics_repo.get_coaching_report(conn, session_id=sid)
        assert again is not None
        assert again.user_talk_pct == 55.0
        assert again.key_topics == ["new"]
        cnt = await conn.fetchval(
            "SELECT count(*) FROM coaching_reports WHERE session_id = $1", sid
        )
        assert cnt == 1
        assert await analytics_repo.get_coaching_report(conn, session_id=uuid4()) is None


async def test_trends_since_window(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        recent_sid = await _new_session(conn, user_id)
        old_sid = await _new_session(conn, user_id)
        now = datetime.now(UTC)
        await conn.execute(
            "INSERT INTO session_analytics (session_id, user_id, total_turns, computed_at) "
            "VALUES ($1, $2, 3, $3)",
            recent_sid,
            user_id,
            now - timedelta(days=2),
        )
        await conn.execute(
            "INSERT INTO session_analytics (session_id, user_id, total_turns, computed_at) "
            "VALUES ($1, $2, 9, $3)",
            old_sid,
            user_id,
            now - timedelta(days=40),
        )
        rows = await analytics_repo.trends_since(
            conn, user_id=user_id, since=now - timedelta(days=14)
        )
        assert [r["session_id"] for r in rows] == [recent_sid]


async def test_digest_reads(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        now = datetime.now(UTC)
        sid = uuid4()
        await conn.execute(
            "INSERT INTO sessions (id, user_id, title, mode, status, created_at) "
            "VALUES ($1, $2, 'recent', 'live_wingman', 'ended', $3)",
            sid,
            user_id,
            now - timedelta(hours=1),
        )
        old_sid = uuid4()
        await conn.execute(
            "INSERT INTO sessions (id, user_id, title, created_at) VALUES ($1, $2, 'old', $3)",
            old_sid,
            user_id,
            now - timedelta(days=30),
        )
        await conn.execute(
            "INSERT INTO tasks (user_id, title, status) VALUES ($1, 'todo', 'pending'), "
            "($1, 'done-task', 'done')",
            user_id,
        )
        await conn.execute(
            "INSERT INTO entities (user_id, canonical_name, display_name, entity_type, mention_count) "
            "VALUES ($1, 'alice', 'Alice', 'person', 9), ($1, 'bob', 'Bob', 'person', 2)",
            user_id,
        )
        await conn.execute(
            "INSERT INTO highlights (user_id, session_id, highlight_type, title, body, created_at) "
            "VALUES ($1, $2, 'insight', 'h1', 'body1', $3)",
            user_id,
            sid,
            now - timedelta(hours=2),
        )
        since = now - timedelta(days=7)
        sessions = await analytics_repo.digest_sessions(conn, user_id=user_id, since=since)
        assert [r["title"] for r in sessions] == ["recent"]
        tasks = await analytics_repo.digest_pending_tasks(conn, user_id=user_id)
        assert [r["title"] for r in tasks] == ["todo"]
        ents = await analytics_repo.digest_top_entities(conn, user_id=user_id)
        assert [r["display_name"] for r in ents] == ["Alice", "Bob"]
        hls = await analytics_repo.digest_recent_highlights(conn, user_id=user_id, since=since)
        assert [r["title"] for r in hls] == ["h1"]
