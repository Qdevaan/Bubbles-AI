"""Integration test for the compute_session_analytics worker job."""

from __future__ import annotations

from typing import Any
from uuid import UUID, uuid4

import asyncpg
import pytest

from bubbles.db.repo import analytics as analytics_repo
from bubbles.workers.jobs import compute_session_analytics

pytestmark = pytest.mark.integration


class _FakeCompletion:
    def __init__(self, text: str) -> None:
        self.text = text
        self.raw: dict[str, Any] = {}


class _FakeRouter:
    """Returns canned JSON for whichever task is asked for."""

    async def complete(self, task: str, messages: Any, **kwargs: Any) -> _FakeCompletion:
        if task == "analytics.coaching":
            return _FakeCompletion(
                '{"user_talk_pct": 60.0, "others_talk_pct": 40.0, "key_topics": ["budget"], '
                '"key_decisions": [], "action_items": ["email alice"], "follow_up_people": ["alice"], '
                '"filler_words": ["um"], "filler_word_count": 3, "tone_summary": "warm", '
                '"engagement_trend": "rising", "report_text": "Good chat.", "suggestions": ["pause"], '
                '"strengths": ["clear"], "areas_of_improvement": ["fillers"], "tone_clarity": 8, '
                '"tone_empathy": 7}'
            )
        if task == "wingman.json":
            return _FakeCompletion('{"title": "T", "summary": "S", "highlights": []}')
        return _FakeCompletion("{}")


class _FakeAI:
    router = _FakeRouter()


class _FakeCtxBubbles:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self.pool = pool
        self.ai = _FakeAI()


async def test_worker_writes_analytics_and_coaching(pool: asyncpg.Pool, user_id: UUID) -> None:
    sid = uuid4()
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO sessions (id, user_id, status) VALUES ($1, $2, 'ended')", sid, user_id
        )
    transcript = "User: hi how are you\nAI: I am well thanks\nUser: great to hear"
    ctx = {"bubbles": _FakeCtxBubbles(pool)}
    result = await compute_session_analytics.run(
        ctx, user_id=str(user_id), session_id=str(sid), transcript=transcript
    )
    assert result["coaching"] is True
    assert result["turns"] == 3
    async with pool.acquire() as conn:
        sa = await analytics_repo.get_session_analytics(conn, session_id=sid)
        assert sa is not None
        assert sa.total_turns == 3
        assert sa.user_turns == 2
        assert sa.llm_turns == 1
        assert sa.user_word_count == 8
        assert sa.assistant_word_count == 4
        cr = await analytics_repo.get_coaching_report(conn, session_id=sid)
        assert cr is not None
        assert cr.user_talk_pct == 60.0
        assert cr.filler_word_count == 3
        assert cr.report_content == {"tone_clarity": 8, "tone_empathy": 7}
