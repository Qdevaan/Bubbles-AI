"""Server-Sent Events helpers for streaming endpoints.

Wire format: ``event: <name>\ndata: <json>\n\n``. Heartbeats are sent as
``event: ping`` every ``heartbeat_s`` to keep proxies from idling the
connection. The buffered text is exposed so the route can write to the
prompt cache after the stream completes.
"""

from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncIterator
from dataclasses import dataclass

from bubbles.ai.providers.base import Chunk


def encode_event(event: str, data: object) -> bytes:
    payload = json.dumps(data, separators=(",", ":"), ensure_ascii=False)
    return f"event: {event}\ndata: {payload}\n\n".encode()


@dataclass(slots=True)
class StreamResult:
    text: str
    finish_reason: str | None
    prompt_tokens: int
    completion_tokens: int


async def sse_from_chunks(
    chunks: AsyncIterator[Chunk],
    *,
    heartbeat_s: float = 15.0,
) -> AsyncIterator[bytes]:
    """Wrap an LLM chunk iterator as SSE bytes with heartbeats."""
    buf: list[str] = []
    finish: str | None = None
    prompt_tokens = completion_tokens = 0

    queue: asyncio.Queue[Chunk | None] = asyncio.Queue()

    async def producer() -> None:
        try:
            async for chunk in chunks:
                await queue.put(chunk)
        finally:
            await queue.put(None)

    task = asyncio.create_task(producer())
    try:
        while True:
            try:
                item = await asyncio.wait_for(queue.get(), timeout=heartbeat_s)
            except TimeoutError:
                yield encode_event("ping", {"t": "hb"})
                continue
            if item is None:
                break
            if item.text:
                buf.append(item.text)
                yield encode_event("token", {"t": item.text})
            if item.finish_reason:
                finish = item.finish_reason
            if item.usage is not None:
                prompt_tokens = item.usage.prompt_tokens
                completion_tokens = item.usage.completion_tokens
    finally:
        task.cancel()

    final = StreamResult(
        text="".join(buf),
        finish_reason=finish,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
    )
    yield encode_event(
        "done",
        {
            "finish": final.finish_reason,
            "prompt_tokens": final.prompt_tokens,
            "completion_tokens": final.completion_tokens,
        },
    )
