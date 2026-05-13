"""Sessions repo integration tests."""

from __future__ import annotations

from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import sessions as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def test_start_and_get(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        sess = await repo.start(uow.conn, user_id=user_id, title="hi")
    assert sess.user_id == user_id
    assert sess.status == "active"

    async with pool.acquire() as con:
        fetched = await repo.get(con, sess.id)
    assert fetched is not None
    assert fetched.title == "hi"


async def test_start_idempotent(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        a = await repo.start(uow.conn, user_id=user_id, title="x", idempotency_key="key-1")
    async with UnitOfWork(pool) as uow:
        b = await repo.start(uow.conn, user_id=user_id, title="y", idempotency_key="key-1")
    assert a.id == b.id
    assert b.title == "x"  # second call returns the original


async def test_end_and_soft_delete(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        sess = await repo.start(uow.conn, user_id=user_id, title="t")
    async with UnitOfWork(pool) as uow:
        ended = await repo.end(uow.conn, session_id=sess.id, summary="done")
    assert ended is not None
    assert ended.status == "ended"
    assert ended.summary == "done"

    async with UnitOfWork(pool) as uow:
        ok = await repo.soft_delete(uow.conn, session_id=sess.id, user_id=user_id)
    assert ok is True

    async with pool.acquire() as con:
        gone = await repo.get(con, sess.id)
    assert gone is None


async def test_start_is_multiplayer_persists(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        solo = await repo.start(uow.conn, user_id=user_id, title="solo")
        party = await repo.start(uow.conn, user_id=user_id, title="party", is_multiplayer=True)
    async with pool.acquire() as con:
        rows = {
            r["id"]: r["is_multiplayer"]
            for r in await con.fetch(
                "SELECT id, is_multiplayer FROM sessions WHERE id = ANY($1::uuid[])",
                [solo.id, party.id],
            )
        }
    assert rows[solo.id] is False
    assert rows[party.id] is True
    assert solo.is_multiplayer is False
    assert party.is_multiplayer is True
