"""Optional Logtail (Better Stack) HTTP log shipper.

Wraps a stdlib ``Handler`` that posts batched JSON lines to Logtail's HTTP
ingest endpoint. The handler is non-blocking — it enqueues records onto a
background asyncio task. If the loop isn't running yet (early startup) the
record is dropped to avoid serialised IO on the critical path.

For production, prefer running ``vector`` / ``promtail`` next to the app
container. This module exists for environments without a sidecar shipper.
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import Coroutine
from typing import Any

import httpx

_INGEST_URL = "https://in.logs.betterstack.com/"


class LogtailHandler(logging.Handler):
    def __init__(self, source_token: str, *, batch_size: int = 50) -> None:
        super().__init__()
        self._token = source_token
        self._batch_size = batch_size
        self._queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=10_000)
        self._worker_task: asyncio.Task[None] | None = None

    def emit(self, record: logging.LogRecord) -> None:
        try:
            payload = json.loads(self.format(record))
        except json.JSONDecodeError:
            payload = {"message": record.getMessage(), "level": record.levelname}
        try:
            loop = asyncio.get_event_loop()
            if not loop.is_running():
                return
            self._queue.put_nowait(payload)
            if self._worker_task is None or self._worker_task.done():
                self._worker_task = loop.create_task(self._run())
        except (RuntimeError, asyncio.QueueFull):
            return

    async def _run(self) -> None:
        async with httpx.AsyncClient(timeout=5.0) as client:
            while True:
                try:
                    first = await asyncio.wait_for(self._queue.get(), timeout=1.0)
                except TimeoutError:
                    continue
                batch: list[dict[str, Any]] = [first]
                while len(batch) < self._batch_size:
                    try:
                        batch.append(self._queue.get_nowait())
                    except asyncio.QueueEmpty:
                        break
                await self._post(client, batch)

    async def _post(self, client: httpx.AsyncClient, batch: list[dict[str, Any]]) -> None:
        try:
            await client.post(
                _INGEST_URL,
                headers={"Authorization": f"Bearer {self._token}"},
                json=batch,
            )
        except httpx.HTTPError:
            return


def attach_if_configured(token: str | None) -> None:
    if not token:
        return
    handler = LogtailHandler(source_token=token)
    handler.setLevel(logging.INFO)
    logging.getLogger().addHandler(handler)


def _typed_create_task(coro: Coroutine[Any, Any, None]) -> asyncio.Task[None]:
    """Helper kept for type-narrowing in unit tests."""
    return asyncio.create_task(coro)
