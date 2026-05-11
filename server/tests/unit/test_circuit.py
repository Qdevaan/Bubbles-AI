"""Circuit breaker."""

from __future__ import annotations

import asyncio

import pytest

from bubbles.core.circuit import CircuitBreaker, CircuitState
from bubbles.core.errors import UpstreamUnavailable


async def test_breaker_opens_on_high_error_rate() -> None:
    cb = CircuitBreaker("test", error_rate=0.5, window_s=10, min_calls=4, cool_down_s=0.05)

    async def fail() -> None:
        raise RuntimeError("boom")

    for _ in range(4):
        with pytest.raises(RuntimeError):
            await cb.call(fail)
    assert cb.state is CircuitState.open

    with pytest.raises(UpstreamUnavailable):
        await cb.call(fail)


async def test_breaker_recovers_via_half_open() -> None:
    cb = CircuitBreaker("test", error_rate=0.5, window_s=10, min_calls=2, cool_down_s=0.01)

    async def fail() -> None:
        raise RuntimeError("boom")

    async def ok() -> int:
        return 7

    for _ in range(2):
        with pytest.raises(RuntimeError):
            await cb.call(fail)
    opened: CircuitState = cb.state
    assert opened == CircuitState.open

    await asyncio.sleep(0.02)
    assert await cb.call(ok) == 7
    closed: CircuitState = cb.state
    assert closed == CircuitState.closed


async def test_breaker_rejects_invalid_rate() -> None:
    with pytest.raises(ValueError):
        CircuitBreaker("x", error_rate=0)
    with pytest.raises(ValueError):
        CircuitBreaker("x", error_rate=1)
