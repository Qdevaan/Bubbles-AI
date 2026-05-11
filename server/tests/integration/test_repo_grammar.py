"""Grammar mistakes repo integration tests."""

from __future__ import annotations

from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import grammar as repo
from bubbles.db.repo import sessions as sessions_repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def test_bulk_insert_and_counts(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        sess = await sessions_repo.start(uow.conn, user_id=user_id, title="t")
    payload = [
        {
            "rule_id": "EN_AGREEMENT",
            "category": "agreement",
            "snippet": "she go",
            "suggestion": "she goes",
            "source": "lt",
        },
        {
            "rule_id": "EN_TENSE",
            "category": "tense",
            "snippet": "he eated",
            "suggestion": "he ate",
            "source": "llm",
        },
    ]
    async with UnitOfWork(pool) as uow:
        n = await repo.bulk_insert(uow.conn, user_id=user_id, session_id=sess.id, mistakes=payload)
    assert n == 2

    async with pool.acquire() as con:
        counts = await repo.category_counts(con, user_id=user_id)
        listed = await repo.list_for_user(con, user_id=user_id)
    assert counts == {"agreement": 1, "tense": 1}
    assert len(listed) == 2


async def test_bulk_insert_rejects_invalid_source(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        with pytest.raises(ValueError, match="invalid source"):
            await repo.bulk_insert(
                uow.conn,
                user_id=user_id,
                session_id=None,
                mistakes=[
                    {
                        "rule_id": "X",
                        "category": "x",
                        "snippet": "x",
                        "source": "bogus",
                    }
                ],
            )
