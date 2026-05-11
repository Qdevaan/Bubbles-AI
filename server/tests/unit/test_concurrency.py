"""Bounded concurrency."""

from __future__ import annotations

import asyncio

import pytest

from bubbles.core.concurrency import FireAndForget, gather_bounded


async def test_gather_bounded_caps_inflight() -> None:
    inflight = 0
    peak = 0
    lock = asyncio.Lock()

    async def task() -> int:
        nonlocal inflight, peak
        async with lock:
            inflight += 1
            peak = max(peak, inflight)
        await asyncio.sleep(0.01)
        async with lock:
            inflight -= 1
        return 1

    results = await gather_bounded((task() for _ in range(20)), limit=4)
    assert sum(results) == 20
    assert peak <= 4


async def test_gather_bounded_invalid_limit() -> None:
    with pytest.raises(ValueError):
        await gather_bounded([], limit=0)


async def test_fire_and_forget_drains() -> None:
    bg = FireAndForget()
    counter = 0

    async def work() -> None:
        nonlocal counter
        await asyncio.sleep(0.001)
        counter += 1

    for _ in range(5):
        bg.spawn(work())
    await bg.drain(timeout_s=1.0)
    assert counter == 5
