"""Chaos / degradation behaviour.

Verifies the system fails *gracefully*:
- missing infra (DB/Redis/router not on app.state) → 503, not 500
- LLM chain exhausted → 503 with Retry-After is NOT set (UpstreamUnavailable
  is not RateLimited), body has the upstream_unavailable code
- Redis down during a cache read → silent miss, no exception
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence

from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.ai.providers.base import ChatMessage, Chunk, Completion, ResponseFormat
from bubbles.ai.router import LLMRouter, TaskChain
from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.core.cache import Cache
from bubbles.core.errors import UpstreamUnavailable
from bubbles.deps import get_router


class _RaisingAsyncIter:
    """Async iterator whose first ``__anext__`` raises UpstreamUnavailable."""

    def __aiter__(self) -> _RaisingAsyncIter:
        return self

    async def __anext__(self) -> Chunk:
        raise UpstreamUnavailable("dead provider")


class _DeadProvider:
    name = "dead"
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
        raise UpstreamUnavailable("dead provider")

    def stream(
        self,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
        timeout_s: float = 25.0,
    ) -> AsyncIterator[Chunk]:
        return _RaisingAsyncIter()


async def _client(app: FastAPI) -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://t")


async def test_missing_router_returns_503(app: FastAPI) -> None:
    # No lifespan, no app.state.router → dep raises UpstreamUnavailable.
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id="11111111-1111-1111-1111-111111111111", email=None, role="authenticated"
    )
    async with await _client(app) as ac:
        resp = await ac.post(
            "/v1/ask_consultant", params={"stream": "false"}, json={"question": "hi"}
        )
    assert resp.status_code == 503
    assert resp.json()["error"]["code"] == "upstream_unavailable"


async def test_provider_chain_exhausted_returns_503(app: FastAPI) -> None:
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id="11111111-1111-1111-1111-111111111111", email=None, role="authenticated"
    )
    dead = LLMRouter(
        [_DeadProvider()],
        [TaskChain("consultant.complete", ("dead",))],
        breaker_min_calls=99,
    )
    app.dependency_overrides[get_router] = lambda: dead
    async with await _client(app) as ac:
        resp = await ac.post(
            "/v1/ask_consultant", params={"stream": "false"}, json={"question": "hi"}
        )
    assert resp.status_code == 503
    body = resp.json()
    assert body["error"]["code"] == "upstream_unavailable"
    # UpstreamUnavailable is not RateLimited → no Retry-After header.
    assert "retry-after" not in {k.lower() for k in resp.headers}


class _BrokenRedis:
    """Every op raises — simulates Redis down."""

    async def get(self, key: str) -> bytes | None:
        raise ConnectionError("redis down")

    async def set(self, key: str, value: bytes, *, ex: int | None = None) -> None:
        raise ConnectionError("redis down")

    async def delete(self, key: str) -> None:
        raise ConnectionError("redis down")


async def test_cache_degrades_silently_when_redis_down() -> None:
    cache = Cache(_BrokenRedis())  # type: ignore[arg-type]
    # No exception — read returns None, write is a no-op.
    assert await cache.get_raw("k") is None
    await cache.set_raw("k", b"v", ttl=10)
    assert await cache.get_json("k") is None
