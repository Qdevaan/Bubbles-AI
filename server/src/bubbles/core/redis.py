# Purpose: Async Redis client factory and connection-pool lifecycle management (aioredis).
"""Async Redis client wrapper."""

from __future__ import annotations

import redis.asyncio as redis_async

from bubbles.core.logging import get_logger
from bubbles.settings import Settings

log = get_logger(__name__)


def make_redis(settings: Settings) -> redis_async.Redis:
    """Construct a Redis client. Caller is responsible for closing it."""
    url = settings.redis_url.get_secret_value()
    client: redis_async.Redis = redis_async.from_url(  # type: ignore[no-untyped-call]
        url,
        encoding="utf-8",
        decode_responses=False,
        socket_connect_timeout=5,
        socket_keepalive=True,
        retry_on_timeout=True,
        health_check_interval=30,
    )
    return client


async def ping(client: redis_async.Redis) -> bool:
    try:
        return bool(await client.ping())
    except Exception as exc:
        log.warning("redis_ping_failed", error=str(exc))
        return False
