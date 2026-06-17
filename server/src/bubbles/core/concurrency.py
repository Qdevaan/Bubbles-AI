# Purpose: Async concurrency helpers: bounded semaphores and task-group wrappers for background job fan-out.
"""Bounded concurrency helpers."""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Coroutine, Iterable
from typing import Any, TypeVar

T = TypeVar("T")


async def gather_bounded(
    awaitables: Iterable[Awaitable[T]],
    *,
    limit: int,
) -> list[T]:
    """Run awaitables concurrently with a hard concurrency cap.

    Preserves input order. Surfaces the first exception (others cancelled).
    """
    if limit < 1:
        raise ValueError("limit must be >= 1")
    sem = asyncio.Semaphore(limit)

    async def _run(aw: Awaitable[T]) -> T:
        async with sem:
            return await aw

    return await asyncio.gather(*(_run(a) for a in awaitables))


class FireAndForget:
    """Track background tasks so they aren't garbage-collected mid-flight."""

    def __init__(self) -> None:
        self._tasks: set[asyncio.Task[Any]] = set()

    def spawn(
        self,
        coro: Coroutine[Any, Any, Any],
        *,
        name: str | None = None,
    ) -> asyncio.Task[Any]:
        task: asyncio.Task[Any] = asyncio.create_task(coro, name=name)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)
        return task

    async def drain(self, timeout_s: float = 30.0) -> None:
        if not self._tasks:
            return
        await asyncio.wait(self._tasks, timeout=timeout_s)
        for task in self._tasks:
            if not task.done():
                task.cancel()
