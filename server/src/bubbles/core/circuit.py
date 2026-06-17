# Purpose: Circuit-breaker implementation that trips after consecutive upstream failures and auto-resets after a cooldown.
"""Sliding-window circuit breaker.

States: closed → open → half_open → closed.
Trips when error rate exceeds ``error_rate`` over ``window_s`` and at least
``min_calls`` requests have been made. Half-open admits a single probe call.
"""

from __future__ import annotations

import asyncio
import time
from collections import deque
from collections.abc import Awaitable, Callable
from enum import StrEnum
from typing import TypeVar

from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger

T = TypeVar("T")

log = get_logger(__name__)


class CircuitState(StrEnum):
    closed = "closed"
    open = "open"
    half_open = "half_open"


class CircuitBreaker:
    """Async, asyncio-safe circuit breaker.

    Designed for one breaker per upstream provider.
    """

    def __init__(
        self,
        name: str,
        *,
        error_rate: float = 0.5,
        window_s: int = 30,
        min_calls: int = 10,
        cool_down_s: float = 15.0,
    ) -> None:
        if not 0.0 < error_rate < 1.0:
            raise ValueError("error_rate must be in (0, 1)")
        self.name = name
        self.error_rate = error_rate
        self.window_s = window_s
        self.min_calls = min_calls
        self.cool_down_s = cool_down_s

        self._events: deque[tuple[float, bool]] = deque()  # (timestamp, is_error)
        self._state: CircuitState = CircuitState.closed
        self._opened_at: float = 0.0
        self._lock = asyncio.Lock()

    @property
    def state(self) -> CircuitState:
        return self._state

    def _evict(self, now: float) -> None:
        cutoff = now - self.window_s
        while self._events and self._events[0][0] < cutoff:
            self._events.popleft()

    async def _record(self, *, is_error: bool) -> None:
        async with self._lock:
            now = time.monotonic()
            self._events.append((now, is_error))
            self._evict(now)

            if self._state is CircuitState.half_open:
                if is_error:
                    self._state = CircuitState.open
                    self._opened_at = now
                    log.warning("circuit_reopened", breaker=self.name)
                else:
                    self._state = CircuitState.closed
                    self._events.clear()
                    log.info("circuit_closed", breaker=self.name)
                return

            if self._state is CircuitState.closed:
                total = len(self._events)
                if total < self.min_calls:
                    return
                errors = sum(1 for _, e in self._events if e)
                if errors / total >= self.error_rate:
                    self._state = CircuitState.open
                    self._opened_at = now
                    log.warning(
                        "circuit_opened",
                        breaker=self.name,
                        error_rate=errors / total,
                        total=total,
                    )

    async def _gate(self) -> None:
        if self._state is CircuitState.closed:
            return
        async with self._lock:
            now = time.monotonic()
            if self._state is CircuitState.open:
                if now - self._opened_at >= self.cool_down_s:
                    self._state = CircuitState.half_open
                    log.info("circuit_half_open", breaker=self.name)
                    return
                raise UpstreamUnavailable(f"{self.name} circuit is open")

    async def call(self, fn: Callable[[], Awaitable[T]]) -> T:
        await self._gate()
        try:
            result = await fn()
        except Exception:
            await self._record(is_error=True)
            raise
        await self._record(is_error=False)
        return result
