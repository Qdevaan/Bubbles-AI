"""Two-tier cache: per-process TTLCache (L1) + Redis (L2).

Values are JSON-encoded. Keys must be opaque strings produced by ``hashing``.
"""

from __future__ import annotations

import json
from collections.abc import Awaitable, Callable
from typing import TypeVar

import redis.asyncio as redis_async
from cachetools import TTLCache

from bubbles.core.logging import get_logger

T = TypeVar("T")

log = get_logger(__name__)


class Cache:
    """Two-tier cache. Safe to share across coroutines."""

    def __init__(
        self,
        redis: redis_async.Redis,
        *,
        l1_max: int = 1024,
        l1_ttl: int = 60,
    ) -> None:
        self._redis = redis
        self._l1: TTLCache[str, bytes] = TTLCache(maxsize=l1_max, ttl=l1_ttl)

    async def get_raw(self, key: str) -> bytes | None:
        hit: bytes | None = self._l1.get(key)
        if hit is not None:
            return hit
        try:
            raw = await self._redis.get(key)
        except Exception as exc:
            log.warning("cache_get_failed", key=key, error=str(exc))
            return None
        if raw is None:
            return None
        value: bytes = raw if isinstance(raw, bytes) else bytes(raw)
        self._l1[key] = value
        return value

    async def set_raw(self, key: str, value: bytes, *, ttl: int) -> None:
        self._l1[key] = value
        try:
            await self._redis.set(key, value, ex=ttl)
        except Exception as exc:
            log.warning("cache_set_failed", key=key, error=str(exc))

    async def delete(self, key: str) -> None:
        self._l1.pop(key, None)
        try:
            await self._redis.delete(key)
        except Exception as exc:
            log.warning("cache_delete_failed", key=key, error=str(exc))

    async def get_json(self, key: str) -> object | None:
        raw = await self.get_raw(key)
        if raw is None:
            return None
        try:
            decoded: object = json.loads(raw)
        except json.JSONDecodeError:
            log.warning("cache_corrupt", key=key)
            await self.delete(key)
            return None
        return decoded

    async def set_json(self, key: str, value: object, *, ttl: int) -> None:
        await self.set_raw(key, json.dumps(value, separators=(",", ":")).encode(), ttl=ttl)

    async def get_or_set_json(
        self,
        key: str,
        factory: Callable[[], Awaitable[object]],
        *,
        ttl: int,
    ) -> object:
        cached = await self.get_json(key)
        if cached is not None:
            return cached
        value = await factory()
        await self.set_json(key, value, ttl=ttl)
        return value
