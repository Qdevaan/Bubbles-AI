"""Prompt-response cache.

Keys are blake3 hashes of (model, template_id, rendered_context). Streamed
responses are buffered and only stored on full completion to avoid
poisoning the cache with truncated text.
"""

from __future__ import annotations

from typing import Any

from bubbles.core.cache import Cache
from bubbles.core.hashing import cache_key


def make_key(*, model: str, template_id: str, context: Any) -> str:
    return cache_key("prompt", model, template_id, context)


async def get(cache: Cache, key: str) -> str | None:
    raw = await cache.get_raw(key)
    return raw.decode("utf-8") if raw is not None else None


async def set_(cache: Cache, key: str, text: str, *, ttl: int = 3600) -> None:
    await cache.set_raw(key, text.encode("utf-8"), ttl=ttl)


async def get_json(cache: Cache, key: str) -> object | None:
    return await cache.get_json(key)


async def set_json(cache: Cache, key: str, value: object, *, ttl: int = 86400) -> None:
    await cache.set_json(key, value, ttl=ttl)
