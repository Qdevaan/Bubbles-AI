"""DELETE /v1/sessions/{id} route integration tests."""

from __future__ import annotations

from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.deps import get_pool

pytestmark = pytest.mark.integration


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )


async def _make_session(pool: asyncpg.Pool, owner: UUID) -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'active') RETURNING id",
            owner,
        )
    assert row is not None
    sid: UUID = row["id"]
    return sid


async def test_delete_session_204_then_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r1 = await ac.delete(f"/v1/sessions/{sid}")
        r2 = await ac.delete(f"/v1/sessions/{sid}")
        # save_session reads the session and must now 404 (soft-deleted)
        r3 = await ac.post("/v1/save_session", json={"session_id": str(sid), "transcript": "x"})
    assert r1.status_code == 204
    assert r2.status_code == 404
    assert r3.status_code == 404


async def test_delete_unknown_session_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.delete(f"/v1/sessions/{uuid4()}")
    assert r.status_code == 404


async def test_delete_other_users_session_403(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    other = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", other)
    sid = await _make_session(pool, other)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.delete(f"/v1/sessions/{sid}")
    assert r.status_code == 403
