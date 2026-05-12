"""DELETE /v1/memories/{id} route integration tests."""

from __future__ import annotations

from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.db.repo import memories as memories_repo
from bubbles.db.uow import UnitOfWork
from bubbles.deps import get_pool

pytestmark = pytest.mark.integration


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )


async def test_delete_memory_204_then_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with UnitOfWork(pool) as uow:
        m = await memories_repo.insert(uow.conn, user_id=user_id, content="remember this")
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r1 = await ac.delete(f"/v1/memories/{m.id}")
        r2 = await ac.delete(f"/v1/memories/{m.id}")
    assert r1.status_code == 204
    assert r2.status_code == 404


async def test_delete_unknown_memory_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.delete(f"/v1/memories/{uuid4()}")
    assert r.status_code == 404


async def test_delete_other_users_memory_403(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    other = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", other)
    async with UnitOfWork(pool) as uow:
        m = await memories_repo.insert(uow.conn, user_id=other, content="theirs")
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.delete(f"/v1/memories/{m.id}")
    assert r.status_code == 403
