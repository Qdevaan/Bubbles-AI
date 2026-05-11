"""Extraction tasks parse JSON and wire through router.complete."""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence

import pytest

from bubbles.ai.extraction import extract_entities, generate_summary, generate_title
from bubbles.ai.providers.base import ChatMessage, Chunk, Completion, ResponseFormat, Usage
from bubbles.ai.router import LLMRouter, TaskChain
from bubbles.core.errors import UpstreamUnavailable


class _Stub:
    def __init__(self, text: str) -> None:
        self.name = "stub"
        self.default_model = "m"
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
            usage=Usage(1, 1, 2),
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
        yield Chunk(text=self._text, finish_reason="stop", usage=Usage(1, 1, 2))


def _router(text: str) -> LLMRouter:
    return LLMRouter([_Stub(text)], [TaskChain("wingman.json", ("stub",))])


async def test_extract_entities_parses_json() -> None:
    r = _router(
        '{"entities": [{"canonical_name": "alice", "entity_type": "person"}], "relations": []}'
    )
    out = await extract_entities(r, "Alice met Bob.")
    assert out["entities"][0]["canonical_name"] == "alice"


async def test_generate_title_returns_string() -> None:
    r = _router('{"title": "Catch-up with Alice"}')
    title = await generate_title(r, "talked about a project")
    assert title == "Catch-up with Alice"


async def test_generate_summary_returns_string() -> None:
    r = _router('{"summary": "They discussed the launch."}')
    out = await generate_summary(r, "...")
    assert out == "They discussed the launch."


async def test_invalid_json_raises_upstream() -> None:
    r = _router("not json")
    with pytest.raises(UpstreamUnavailable):
        await extract_entities(r, "x")
