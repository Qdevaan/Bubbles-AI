"""Memory repo integration tests."""

from __future__ import annotations

from uuid import UUID, uuid4

import asyncpg
import pytest

from bubbles.db.repo import memories as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def test_get_returns_row_even_when_archived(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        m = await repo.insert(uow.conn, user_id=user_id, content="hello")
    async with pool.acquire() as con:
        got = await repo.get(con, m.id)
    assert got is not None
    assert got.id == m.id
    assert got.content == "hello"

    async with UnitOfWork(pool) as uow:
        ok = await repo.soft_delete(uow.conn, memory_id=m.id, user_id=user_id)
    assert ok is True
    async with pool.acquire() as con:
        got2 = await repo.get(con, m.id)
    assert got2 is not None
    assert got2.is_archived is True

    # second soft_delete is a no-op (already archived)
    async with UnitOfWork(pool) as uow:
        ok2 = await repo.soft_delete(uow.conn, memory_id=m.id, user_id=user_id)
    assert ok2 is False


async def test_get_unknown_id_returns_none(pool: asyncpg.Pool) -> None:
    async with pool.acquire() as con:
        assert await repo.get(con, uuid4()) is None
