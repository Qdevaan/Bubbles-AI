"""SSE encoding + chunk → SSE wrapper."""

from __future__ import annotations

import json
from collections.abc import AsyncIterator

from bubbles.ai.providers.base import Chunk, Usage
from bubbles.ai.streaming import encode_event, sse_from_chunks


def test_encode_event_format() -> None:
    out = encode_event("token", {"t": "hi"})
    assert out == b'event: token\ndata: {"t":"hi"}\n\n'


async def _gen(*chunks: Chunk) -> AsyncIterator[Chunk]:
    for c in chunks:
        yield c


async def test_sse_wraps_chunks_and_emits_done() -> None:
    chunks = _gen(
        Chunk(text="he"),
        Chunk(text="llo"),
        Chunk(text="", finish_reason="stop", usage=Usage(2, 2, 4)),
    )
    parts: list[bytes] = []
    async for piece in sse_from_chunks(chunks, heartbeat_s=10.0):
        parts.append(piece)
    body = b"".join(parts).decode()
    assert 'event: token\ndata: {"t":"he"}' in body
    assert 'event: token\ndata: {"t":"llo"}' in body
    last = parts[-1].decode()
    assert last.startswith("event: done\n")
    payload = json.loads(last.split("data: ", 1)[1].strip())
    assert payload["finish"] == "stop"
    assert payload["completion_tokens"] == 2
