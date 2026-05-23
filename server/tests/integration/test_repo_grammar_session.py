"""grammar_repo.list_for_session — per-session mistake reader used by the materialize worker."""

from __future__ import annotations

from uuid import UUID

import pytest

from bubbles.db.repo import grammar as grammar_repo

pytestmark = pytest.mark.integration


@pytest.mark.asyncio
async def test_list_for_session_returns_only_that_sessions_rows(
    pool, user_id: UUID, session_id: UUID, other_session_id: UUID
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await grammar_repo.bulk_insert(
                conn,
                user_id=user_id,
                session_id=session_id,
                mistakes=[
                    {
                        "rule_id": "LLM_ARTICLE",
                        "category": "article",
                        "snippet": "X went to store.",
                        "suggestion": "X went to the store.",
                        "source": "llm",
                    },
                ],
            )
            await grammar_repo.bulk_insert(
                conn,
                user_id=user_id,
                session_id=other_session_id,
                mistakes=[
                    {
                        "rule_id": "LLM_AGREEMENT",
                        "category": "agreement",
                        "snippet": "He go home.",
                        "suggestion": "He goes home.",
                        "source": "llm",
                    },
                ],
            )
        async with conn.transaction():
            rows = await grammar_repo.list_for_session(conn, session_id=session_id)
        assert len(rows) == 1
        assert rows[0].rule_id == "LLM_ARTICLE"
        assert rows[0].session_id == session_id


@pytest.mark.asyncio
async def test_list_for_session_empty_when_no_rows(pool, session_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            rows = await grammar_repo.list_for_session(conn, session_id=session_id)
        assert rows == []
