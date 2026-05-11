"""OpenAI-compatible provider (Cerebras/Groq) — wire-protocol tests via respx."""

from __future__ import annotations

import json

import httpx
import pytest
import respx

from bubbles.ai.providers._oai_compat import OAICompatProvider
from bubbles.ai.providers.base import ChatMessage, Role
from bubbles.core.errors import UpstreamUnavailable

_BASE = "https://api.example/v1"


def _make() -> OAICompatProvider:
    return OAICompatProvider(
        name="example",
        base_url=_BASE,
        api_key="key",
        client=httpx.AsyncClient(timeout=5.0),
        default_model="m",
    )


@respx.mock
async def test_complete_parses_message_and_usage() -> None:
    respx.post(f"{_BASE}/chat/completions").mock(
        return_value=httpx.Response(
            200,
            json={
                "choices": [{"message": {"content": "hi"}, "finish_reason": "stop"}],
                "usage": {"prompt_tokens": 4, "completion_tokens": 1, "total_tokens": 5},
            },
        )
    )
    p = _make()
    out = await p.complete([ChatMessage(role=Role.user, content="ping")])
    assert out.text == "hi"
    assert out.finish_reason == "stop"
    assert out.usage.total_tokens == 5


@respx.mock
async def test_complete_raises_on_5xx() -> None:
    respx.post(f"{_BASE}/chat/completions").mock(return_value=httpx.Response(503))
    p = _make()
    with pytest.raises(UpstreamUnavailable):
        await p.complete([ChatMessage(role=Role.user, content="x")])


def _sse_chunks(*chunks: dict[str, object]) -> bytes:
    return ("\n".join(f"data: {json.dumps(c)}" for c in chunks) + "\ndata: [DONE]\n\n").encode()


@respx.mock
async def test_stream_yields_tokens() -> None:
    body = _sse_chunks(
        {
            "choices": [{"delta": {"content": "he"}, "finish_reason": None, "index": 0}],
        },
        {
            "choices": [{"delta": {"content": "llo"}, "finish_reason": None, "index": 0}],
        },
        {
            "choices": [{"delta": {}, "finish_reason": "stop", "index": 0}],
            "usage": {"prompt_tokens": 2, "completion_tokens": 2, "total_tokens": 4},
        },
    )
    respx.post(f"{_BASE}/chat/completions").mock(
        return_value=httpx.Response(
            200, content=body, headers={"content-type": "text/event-stream"}
        )
    )
    p = _make()
    parts: list[str] = []
    finish: str | None = None
    async for chunk in p.stream([ChatMessage(role=Role.user, content="x")]):
        if chunk.text:
            parts.append(chunk.text)
        if chunk.finish_reason:
            finish = chunk.finish_reason
    assert "".join(parts) == "hello"
    assert finish == "stop"
