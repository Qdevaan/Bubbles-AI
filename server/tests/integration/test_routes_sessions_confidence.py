"""POST /v1/sessions/{id}/confidence integration tests."""

from __future__ import annotations

from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.db.repo import sessions as sessions_repo
from bubbles.db.uow import UnitOfWork
from bubbles.deps import RateLimiterDep, get_pool

pytestmark = pytest.mark.integration


class _FakeLimiter:
    async def check(self, key: str, *, capacity: int, refill_per_s: float) -> object:
        class _RL:
            allowed = True
            retry_after_s = 0.0

        return _RL()


class _BlockingLimiter:
    async def check(self, key: str, *, capacity: int, refill_per_s: float) -> object:
        class _RL:
            allowed = False
            retry_after_s = 5.0

        return _RL()


def _override(
    app: FastAPI, pool: asyncpg.Pool, uid: UUID, *, limiter: object | None = None
) -> None:
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email="t@t", role="authenticated"
    )
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[RateLimiterDep] = lambda: limiter or _FakeLimiter()


async def _seed_session(pool: asyncpg.Pool, *, user_id: UUID) -> UUID:
    async with UnitOfWork(pool) as uow:
        session = await sessions_repo.start(
            uow.conn, user_id=user_id, title="t", mode="live_wingman"
        )
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO session_logs (session_id, turn_index, role, content)"
            " VALUES ($1, 0, 'user', 'x')",
            session.id,
        )
        await conn.execute(
            "INSERT INTO session_logs (session_id, turn_index, role, content)"
            " VALUES ($1, 1, 'user', 'y')",
            session.id,
        )
    return session.id


@pytest.mark.asyncio
async def test_set_confidence_happy_path(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    sid = await _seed_session(pool, user_id=user_id)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/sessions/{sid}/confidence",
            json={
                "confidence_by_turn": [
                    {"turn_index": 0, "score": 0.8},
                    {"turn_index": 1, "score": 0.4},
                ]
            },
        )
    assert r.status_code == 200
    assert r.json() == {"updated": 2}

    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT turn_index, confidence FROM session_logs WHERE session_id = $1 "
            "ORDER BY turn_index",
            sid,
        )
    assert [(r["turn_index"], float(r["confidence"])) for r in rows] == [(0, 0.8), (1, 0.4)]


@pytest.mark.asyncio
async def test_set_confidence_404_unknown_session(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/sessions/{uuid4()}/confidence",
            json={"confidence_by_turn": [{"turn_index": 0, "score": 0.5}]},
        )
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_set_confidence_403_cross_user(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID, other_user_id: UUID
) -> None:
    sid = await _seed_session(pool, user_id=other_user_id)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/sessions/{sid}/confidence",
            json={"confidence_by_turn": [{"turn_index": 0, "score": 0.5}]},
        )
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_set_confidence_429_rate_limited(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    sid = await _seed_session(pool, user_id=user_id)
    _override(app, pool, user_id, limiter=_BlockingLimiter())
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/sessions/{sid}/confidence",
            json={"confidence_by_turn": [{"turn_index": 0, "score": 0.5}]},
        )
    assert r.status_code == 429


@pytest.mark.asyncio
async def test_set_confidence_ignores_unknown_turn_index_still_200(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    sid = await _seed_session(pool, user_id=user_id)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/sessions/{sid}/confidence",
            json={
                "confidence_by_turn": [
                    {"turn_index": 0, "score": 0.7},
                    {"turn_index": 99, "score": 0.3},  # unknown turn
                ]
            },
        )
    assert r.status_code == 200
    assert r.json() == {"updated": 1}
