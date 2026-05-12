"""check_user_turn enqueues the LanguageTool grammar_scan job (H1)."""

from __future__ import annotations

import json
from collections.abc import AsyncIterator, Sequence
from typing import Any

from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.ai.providers.base import ChatMessage, Chunk, Completion, ResponseFormat, Usage
from bubbles.ai.router import LLMRouter, TaskChain
from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.deps import get_arq, get_pool, get_router

_USER_ID = "11111111-1111-1111-1111-111111111111"


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
            text=json.dumps({"is_correct": True, "corrected": None, "mistakes": []}),
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
        yield Chunk(text="x", finish_reason="stop", usage=Usage(1, 1, 2))


class FakeArq:
    def __init__(self) -> None:
        self.calls: list[tuple[tuple[Any, ...], dict[str, Any]]] = []

    async def enqueue_job(self, *args: Any, **kwargs: Any) -> str:
        self.calls.append((args, kwargs))
        return str(kwargs.get("_job_id", "job"))


def _router() -> LLMRouter:
    return LLMRouter([_Stub()], [TaskChain("wingman.json", ("stub",))])


def _override(app: FastAPI, *, arq: FakeArq | None) -> None:
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=_USER_ID, email=None, role="authenticated"
    )
    app.dependency_overrides[get_router] = _router
    app.dependency_overrides[get_pool] = lambda: object()  # unused: no mistakes path
    app.dependency_overrides[get_arq] = lambda: arq


async def _client(app: FastAPI) -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://t")


async def test_check_user_turn_enqueues_grammar_scan(app: FastAPI) -> None:
    arq = FakeArq()
    _override(app, arq=arq)
    async with await _client(app) as ac:
        resp = await ac.post("/v1/check_user_turn", json={"text": "i has a apple"})
    assert resp.status_code == 200
    assert len(arq.calls) == 1
    (_, kwargs) = arq.calls[0]
    assert kwargs["_job_name"] == "grammar_scan"
    assert kwargs["user_id"] == _USER_ID
    assert kwargs["session_id"] is None
    assert kwargs["text"] == "i has a apple"


async def test_check_user_turn_ok_when_queue_down(app: FastAPI) -> None:
    _override(app, arq=None)
    async with await _client(app) as ac:
        resp = await ac.post("/v1/check_user_turn", json={"text": "hello there"})
    assert resp.status_code == 200
