"""LLM router fallback + chain wiring."""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence

import pytest

from bubbles.ai.providers.base import ChatMessage, Chunk, Completion, ResponseFormat, Usage
from bubbles.ai.router import LLMRouter, TaskChain
from bubbles.core.errors import UpstreamUnavailable


class FakeProvider:
    def __init__(
        self,
        name: str,
        *,
        complete_text: str | None = None,
        complete_error: bool = False,
        stream_chunks: list[str] | None = None,
        stream_error: bool = False,
    ) -> None:
        self.name = name
        self.default_model = "fake"
        self._text = complete_text
        self._complete_error = complete_error
        self._stream = stream_chunks or []
        self._stream_error = stream_error

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
        if self._complete_error:
            raise UpstreamUnavailable(f"{self.name} down")
        return Completion(
            text=self._text or "",
            finish_reason="stop",
            usage=Usage(prompt_tokens=1, completion_tokens=1, total_tokens=2),
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
        if self._stream_error:
            raise UpstreamUnavailable(f"{self.name} stream down")
        for token in self._stream:
            yield Chunk(text=token)
        yield Chunk(text="", finish_reason="stop", usage=Usage(2, 2, 4))


async def test_complete_uses_first_healthy_provider() -> None:
    a = FakeProvider("a", complete_text="A")
    b = FakeProvider("b", complete_text="B")
    router = LLMRouter([a, b], [TaskChain("t", ("a", "b"))])
    out = await router.complete("t", [ChatMessage(role="user", content="x")])  # type: ignore[arg-type]
    assert out.text == "A"
    assert router.last_fallback_depth == 0


async def test_complete_falls_through_on_failure() -> None:
    a = FakeProvider("a", complete_error=True)
    b = FakeProvider("b", complete_text="B")
    router = LLMRouter([a, b], [TaskChain("t", ("a", "b"))])
    out = await router.complete("t", [ChatMessage(role="user", content="x")])  # type: ignore[arg-type]
    assert out.text == "B"
    assert router.last_fallback_depth == 1


async def test_complete_exhausted_chain_raises() -> None:
    a = FakeProvider("a", complete_error=True)
    b = FakeProvider("b", complete_error=True)
    router = LLMRouter([a, b], [TaskChain("t", ("a", "b"))], breaker_min_calls=99)
    with pytest.raises(UpstreamUnavailable):
        await router.complete("t", [ChatMessage(role="user", content="x")])  # type: ignore[arg-type]


async def test_stream_falls_through_on_first_chunk_error() -> None:
    a = FakeProvider("a", stream_error=True)
    b = FakeProvider("b", stream_chunks=["he", "llo"])
    router = LLMRouter([a, b], [TaskChain("t", ("a", "b"))])
    parts: list[str] = []
    async for chunk in router.stream("t", [ChatMessage(role="user", content="x")]):  # type: ignore[arg-type]
        if chunk.text:
            parts.append(chunk.text)
    assert "".join(parts) == "hello"
    assert router.last_fallback_depth == 1


async def test_unknown_task_raises() -> None:
    router = LLMRouter([FakeProvider("a")], [TaskChain("known", ("a",))])
    with pytest.raises(KeyError):
        await router.complete("missing", [ChatMessage(role="user", content="x")])  # type: ignore[arg-type]
