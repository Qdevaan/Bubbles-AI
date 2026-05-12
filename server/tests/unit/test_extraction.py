"""Extraction tasks parse JSON and wire through router.complete."""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence

import pytest

from bubbles.ai.extraction import (
    _TRANSCRIPT_BUDGET_CHARS,
    _split_on_line_boundaries,
    extract_entities,
    generate_summary,
    generate_title,
    prepare_transcript,
)
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


def _empty_router() -> LLMRouter:
    return LLMRouter([], [TaskChain("wingman.json", ())])


def test_split_on_line_boundaries() -> None:
    text = "".join(f"line {i}\n" for i in range(100))  # ~ 900 chars
    chunks = _split_on_line_boundaries(text, 200)
    assert len(chunks) > 1
    assert "".join(chunks) == text
    assert all(c.endswith("\n") for c in chunks)
    assert all(len(c) <= 200 + len("line 99\n") for c in chunks)


async def test_prepare_transcript_short_passthrough() -> None:
    r = _router('{"summary": "should not be called"}')
    text = "User: hi\nOthers: hello\n"
    assert await prepare_transcript(r, text) == text


async def test_prepare_transcript_condenses_long() -> None:
    r = _router('{"summary": "SEG"}')
    long_text = "".join(f"User: turn {i} blah blah blah\n" for i in range(4000))
    assert len(long_text) > _TRANSCRIPT_BUDGET_CHARS
    out = await prepare_transcript(r, long_text)
    assert len(out) <= _TRANSCRIPT_BUDGET_CHARS
    assert out.startswith("[Segment 1] SEG")
    assert "[Segment 2] SEG" in out


async def test_prepare_transcript_falls_back_to_raw_on_upstream() -> None:
    r = _empty_router()  # router.complete raises UpstreamUnavailable -> segment fallback
    long_text = "".join(f"User: turn {i}\n" for i in range(5000))
    assert len(long_text) > _TRANSCRIPT_BUDGET_CHARS
    out = await prepare_transcript(r, long_text)
    assert len(out) <= _TRANSCRIPT_BUDGET_CHARS
    assert "[Segment 1] User: turn 0" in out  # raw (clipped) segment text, not a summary
