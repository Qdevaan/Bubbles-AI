"""Consultant route — auth bypass, mocked LLM router."""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence
from typing import Any
from uuid import UUID

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.ai.providers.base import ChatMessage, Chunk, Completion, ResponseFormat, Usage
from bubbles.ai.router import LLMRouter, TaskChain
from bubbles.api.v1 import consultant as consultant_routes
from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.deps import get_router


class _Stub:
    name = "stub"
    default_model = "m"

    def __init__(self, text: str = "ok") -> None:
        self._text = text

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
            text=self._text,
            finish_reason="stop",
            usage=Usage(2, 2, 4),
            raw={"model": "stub-m"},
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
        yield Chunk(text="he")
        yield Chunk(text="llo", finish_reason="stop", usage=Usage(2, 2, 4))


def _build_router(text: str = "answer-text") -> LLMRouter:
    return LLMRouter(
        [_Stub(text)],
        [
            TaskChain("consultant.complete", ("stub",)),
            TaskChain("consultant.stream", ("stub",)),
        ],
    )


def _override(app: FastAPI, *, router: LLMRouter) -> None:
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id="11111111-1111-1111-1111-111111111111", email=None, role="authenticated"
    )
    app.dependency_overrides[get_router] = lambda: router


async def _client(app: FastAPI) -> AsyncClient:
    transport = ASGITransport(app=app)
    return AsyncClient(transport=transport, base_url="http://t")


async def test_ask_consultant_non_stream(app: FastAPI) -> None:
    _override(app, router=_build_router("hello world"))
    async with await _client(app) as ac:
        resp = await ac.post(
            "/v1/ask_consultant",
            params={"stream": "false"},
            json={"question": "hi"},
        )
    assert resp.status_code == 200
    body = resp.json()
    assert body["answer"] == "hello world"
    assert body["fallback_depth"] == 0


async def test_ask_consultant_stream_returns_sse(app: FastAPI) -> None:
    _override(app, router=_build_router())
    async with await _client(app) as ac:
        resp = await ac.post("/v1/ask_consultant", json={"question": "hi"})
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/event-stream")
    body = resp.text
    assert "event: token" in body
    assert "event: done" in body


async def test_ask_alias_returns_json(app: FastAPI) -> None:
    _override(app, router=_build_router("alias-answer"))
    async with await _client(app) as ac:
        resp = await ac.post("/v1/ask", json={"question": "hi"})
    assert resp.status_code == 200
    assert resp.json()["answer"] == "alias-answer"


async def test_ask_consultant_requires_auth(app: FastAPI) -> None:
    # No override -> default current_user dependency runs and fails on missing token.
    app.dependency_overrides[get_router] = lambda: _build_router()
    async with await _client(app) as ac:
        resp = await ac.post(
            "/v1/ask_consultant",
            params={"stream": "false"},
            json={"question": "hi"},
        )
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "unauthorized"


async def test_consultant_batch(app: FastAPI) -> None:
    _override(app, router=_build_router("batched"))
    async with await _client(app) as ac:
        resp = await ac.post(
            "/v1/ask_consultant/batch",
            json={"questions": ["a", "b", "c"]},
        )
    assert resp.status_code == 200
    answers = resp.json()["answers"]
    assert len(answers) == 3
    assert all(a["answer"] == "batched" for a in answers)


async def test_consultant_bumps_quests_when_pool_present(
    app: FastAPI, monkeypatch: pytest.MonkeyPatch
) -> None:
    _override(app, router=_build_router())
    calls: list[tuple[UUID, int]] = []

    async def _spy(_pool: Any, *, user_id: UUID, n: int = 1) -> None:
        calls.append((user_id, n))

    monkeypatch.setattr(consultant_routes, "_bump_consultant_quests", _spy)
    app.state.db = object()  # _maybe_bump_quests only fires when the pool is up
    try:
        async with await _client(app) as ac:
            await ac.post("/v1/ask_consultant", params={"stream": "false"}, json={"question": "hi"})
            await ac.post("/v1/ask", json={"question": "hi"})
            await ac.post("/v1/ask_consultant/batch", json={"questions": ["a", "b"]})
    finally:
        del app.state.db
    assert calls == [
        (UUID("11111111-1111-1111-1111-111111111111"), 1),
        (UUID("11111111-1111-1111-1111-111111111111"), 1),
        (UUID("11111111-1111-1111-1111-111111111111"), 2),
    ]


async def test_consultant_skips_quest_bump_when_no_pool(
    app: FastAPI, monkeypatch: pytest.MonkeyPatch
) -> None:
    _override(app, router=_build_router())
    called = False

    async def _spy(_pool: Any, *, user_id: UUID, n: int = 1) -> None:
        nonlocal called
        called = True

    monkeypatch.setattr(consultant_routes, "_bump_consultant_quests", _spy)
    async with await _client(app) as ac:
        resp = await ac.post(
            "/v1/ask_consultant", params={"stream": "false"}, json={"question": "hi"}
        )
    assert resp.status_code == 200
    assert called is False
