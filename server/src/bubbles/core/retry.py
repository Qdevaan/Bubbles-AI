"""Retry policies built on tenacity."""

from __future__ import annotations

import inspect
from collections.abc import Awaitable, Callable
from typing import TypeVar, cast

import httpx
from tenacity import (
    AsyncRetrying,
    retry_if_exception_type,
    stop_after_attempt,
    stop_after_delay,
    wait_exponential_jitter,
)

T = TypeVar("T")

_RETRYABLE_HTTP_STATUSES = frozenset({408, 425, 429, 500, 502, 503, 504})


def is_retryable_http_error(exc: BaseException) -> bool:
    if isinstance(exc, httpx.TransportError | httpx.TimeoutException):
        return True
    if isinstance(exc, httpx.HTTPStatusError):
        return exc.response.status_code in _RETRYABLE_HTTP_STATUSES
    return False


def http_retry(
    *,
    attempts: int = 3,
    max_delay_s: float = 8.0,
) -> AsyncRetrying:
    """Async retry suited to HTTP API calls."""
    return AsyncRetrying(
        stop=stop_after_attempt(attempts) | stop_after_delay(max_delay_s),
        wait=wait_exponential_jitter(initial=0.1, max=2.0, jitter=0.2),
        retry=retry_if_exception_type((httpx.TransportError, httpx.TimeoutException)),
        reraise=True,
    )


async def with_retry(
    func: Callable[[], T | Awaitable[T]],
    *,
    attempts: int = 3,
    max_delay_s: float = 8.0,
    retry_on: tuple[type[BaseException], ...] = (
        httpx.TransportError,
        httpx.TimeoutException,
    ),
) -> T:
    """One-shot async retry helper for callables."""
    last: T
    async for attempt in AsyncRetrying(
        stop=stop_after_attempt(attempts) | stop_after_delay(max_delay_s),
        wait=wait_exponential_jitter(initial=0.1, max=2.0, jitter=0.2),
        retry=retry_if_exception_type(retry_on),
        reraise=True,
    ):
        with attempt:
            result = func()
            if inspect.isawaitable(result):
                last = await cast(Awaitable[T], result)
            else:
                last = result
    return last
