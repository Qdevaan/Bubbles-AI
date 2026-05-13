"""``/suggest_reply``: 3-candidate parity with the legacy ``server_v2`` shape."""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence
from typing import Any
from uuid import UUID

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.ai.providers.base import ChatMessage, Chunk, Completion, ResponseFormat, Usage
from bubbles.ai.router import LLMRouter, TaskChain
from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.deps import get_arq, get_embeddings, get_pool, get_router

pytestmark = pytest.mark.integration

_JSON = '{"suggestions": ["sounds great", "tell me more", "I hear you"]}'


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
            text=_JSON, finish_reason="stop", usage=Usage(3, 5, 8), raw={"model": "stub-m"}
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
        yield Chunk(text=_JSON, finish_reason="stop", usage=Usage(3, 5, 8))


class _StubEmb:
    async def embed(self, text: str) -> Sequence[float]:
        raise RuntimeError("no embeddings in tests")


def _router() -> LLMRouter:
    return LLMRouter([_Stub()], [TaskChain("wingman.json", ("stub",))])


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[get_arq] = lambda: None
    app.dependency_overrides[get_router] = _router
    app.dependency_overrides[get_embeddings] = lambda: _StubEmb()
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


async def test_suggest_reply_returns_three_candidates(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/suggest_reply",
            json={
                "session_id": str(sid),
                "partner_utterance": "what have you been up to?",
                "tone": "casual",
                "is_draft": False,
            },
        )
    assert r.status_code == 200
    body = r.json()
    assert body["suggestions"] == ["sounds great", "tell me more", "I hear you"]
    assert body["provider"] == "stub-m"


async def test_suggest_reply_without_session_is_allowed(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/suggest_reply",
            json={"partner_utterance": "hi", "tone": "formal"},
        )
    assert r.status_code == 200
    assert len(r.json()["suggestions"]) == 3


async def test_suggest_reply_legacy_last_user_text_alias(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    """Older clients still send ``last_user_text``; the endpoint accepts it."""
    _override(app, pool, user_id)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/suggest_reply",
            json={"session_id": str(sid), "last_user_text": "what's new?"},
        )
    assert r.status_code == 200
    assert r.json()["suggestions"] == ["sounds great", "tell me more", "I hear you"]


async def test_suggest_reply_handles_bad_json(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    """If the LLM returns garbage, the endpoint degrades to an empty list."""
    class _BadStub(_Stub):
        async def complete(self, *a: Any, **kw: Any) -> Completion:
            return Completion(
                text="not json at all", finish_reason="stop", usage=Usage(0, 0, 0), raw={}
            )

    def _bad_router() -> LLMRouter:
        return LLMRouter([_BadStub()], [TaskChain("wingman.json", ("stub",))])

    _override(app, pool, user_id)
    app.dependency_overrides[get_router] = _bad_router
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/suggest_reply",
            json={"partner_utterance": "?"},
        )
    assert r.status_code == 200
    assert r.json()["suggestions"] == []
