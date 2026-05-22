"""/v1/scenarios route integration tests."""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence
from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.ai.providers.base import ChatMessage, Chunk, Completion, ResponseFormat, Usage
from bubbles.ai.router import LLMRouter, TaskChain
from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.core.ratelimit import RateLimitResult
from bubbles.deps import get_pool, get_ratelimiter, get_router

pytestmark = pytest.mark.integration

_SCENARIO_JSON = (
    '{"scenarios": [{"target_person": "sarah", "title": "Ask for a raise",'
    ' "situation": "You meet your manager.", "goal": "Negotiate",'
    ' "success_criteria": "Made the ask", "difficulty": "medium",'
    ' "role_mode": "busy", "opening_line": "You wanted to see me?",'
    ' "source_refs": []}]}'
)


class _Stub:
    name = "stub"
    default_model = "m"

    async def complete(
        self,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
        response_format: ResponseFormat = "text",
        timeout_s: float = 25.0,
    ) -> Completion:
        return Completion(
            text=_SCENARIO_JSON, finish_reason="stop", usage=Usage(3, 5, 8), raw={"model": "stub"}
        )

    async def stream(
        self,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
        timeout_s: float = 25.0,
    ) -> AsyncIterator[Chunk]:
        yield Chunk(text=_SCENARIO_JSON, finish_reason="stop", usage=Usage(3, 5, 8))


class _FakeLimiter:
    async def check(
        self, key: str, *, capacity: int, refill_per_s: float, cost: int = 1
    ) -> RateLimitResult:
        return RateLimitResult(allowed=True, tokens_left=float(capacity), retry_after_s=0)


def _router() -> LLMRouter:
    return LLMRouter([_Stub()], [TaskChain("scenario.generate", ("stub",))])


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[get_router] = _router
    app.dependency_overrides[get_ratelimiter] = lambda: _FakeLimiter()
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )


async def _entity(pool: asyncpg.Pool, owner: UUID, name: str = "sarah") -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO entities (user_id, canonical_name, display_name, entity_type) "
            "VALUES ($1, $2, $2, 'person') RETURNING id",
            owner,
            name,
        )
    assert row is not None
    eid: UUID = row["id"]
    return eid


async def test_generate_then_list(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    eid = await _entity(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        gen = await ac.post("/v1/scenarios/generate", json={"target_entity_id": str(eid)})
        lst = await ac.get("/v1/scenarios")
    assert gen.status_code == 201
    assert gen.json()["title"] == "Ask for a raise"
    assert gen.json()["status"] == "suggested"
    body = lst.json()
    assert len(body) == 1
    assert body[0]["target_entity_id"] == str(eid)


async def test_generate_rejects_other_users_entity(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    other = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", other)
    eid = await _entity(pool, other)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post("/v1/scenarios/generate", json={"target_entity_id": str(eid)})
    assert r.status_code == 403


async def test_start_creates_roleplay_session(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    eid = await _entity(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        gen = await ac.post("/v1/scenarios/generate", json={"target_entity_id": str(eid)})
        sid = gen.json()["id"]
        started = await ac.post(f"/v1/scenarios/{sid}/start")
        again = await ac.post(f"/v1/scenarios/{sid}/start")
    assert started.status_code == 200
    body = started.json()
    assert body["scenario"]["status"] == "started"
    session_id = body["session_id"]
    async with pool.acquire() as con:
        mode = await con.fetchval("SELECT mode FROM sessions WHERE id = $1", UUID(session_id))
    assert mode == "roleplay"
    assert again.status_code == 409


async def test_dismiss_then_gone_from_feed(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    eid = await _entity(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        gen = await ac.post("/v1/scenarios/generate", json={"target_entity_id": str(eid)})
        sid = gen.json()["id"]
        dis = await ac.post(f"/v1/scenarios/{sid}/dismiss")
        lst = await ac.get("/v1/scenarios")
    assert dis.status_code == 200
    assert dis.json()["status"] == "dismissed"
    assert lst.json() == []


async def test_start_unknown_scenario_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(f"/v1/scenarios/{uuid4()}/start")
    assert r.status_code == 404
