"""Gemini provider wire-protocol tests."""

from __future__ import annotations

import json

import httpx
import pytest
import respx

from bubbles.ai.providers.base import ChatMessage, Role
from bubbles.ai.providers.gemini import GeminiProvider
from bubbles.core.errors import UpstreamUnavailable


def _make() -> GeminiProvider:
    return GeminiProvider(
        api_key="k",
        client=httpx.AsyncClient(timeout=5.0),
        default_model="gemini-2.5-flash",
    )


@respx.mock
async def test_complete_parses_text_and_usage() -> None:
    respx.post(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    ).mock(
        return_value=httpx.Response(
            200,
            json={
                "candidates": [
                    {
                        "content": {"parts": [{"text": "hi"}]},
                        "finishReason": "STOP",
                    }
                ],
                "usageMetadata": {
                    "promptTokenCount": 3,
                    "candidatesTokenCount": 1,
                    "totalTokenCount": 4,
                },
            },
        )
    )
    p = _make()
    out = await p.complete([ChatMessage(role=Role.user, content="hi?")])
    assert out.text == "hi"
    assert out.finish_reason == "STOP"
    assert out.usage.total_tokens == 4


@respx.mock
async def test_complete_5xx_raises() -> None:
    respx.post(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    ).mock(return_value=httpx.Response(500))
    p = _make()
    with pytest.raises(UpstreamUnavailable):
        await p.complete([ChatMessage(role=Role.user, content="x")])


@respx.mock
async def test_embed_returns_vector() -> None:
    respx.post(
        "https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent"
    ).mock(return_value=httpx.Response(200, json={"embedding": {"values": [0.1, 0.2, 0.3]}}))
    p = _make()
    vec = await p.embed("hi")
    assert vec == [0.1, 0.2, 0.3]


@respx.mock
async def test_stream_yields_text() -> None:
    chunk_a = {"candidates": [{"content": {"parts": [{"text": "he"}]}}]}
    chunk_b = {
        "candidates": [
            {
                "content": {"parts": [{"text": "llo"}]},
                "finishReason": "STOP",
            }
        ]
    }
    body = (
        f"data: {json.dumps(chunk_a)}\n" f"data: {json.dumps(chunk_b)}\n" "data: [DONE]\n\n"
    ).encode()
    respx.post(
        "https://generativelanguage.googleapis.com/v1beta/models/"
        "gemini-2.5-flash:streamGenerateContent"
    ).mock(
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
    assert finish == "STOP"
