"""Job-level idempotency via Redis SETNX.

A job that's already been started (or finished) within the dedupe window
returns ``False`` so the caller can short-circuit. Uses ``SET NX EX`` for
atomicity.
"""

from __future__ import annotations

import redis.asyncio as redis_async


async def claim(
    redis: redis_async.Redis,
    *,
    job_id: str,
    ttl_s: int = 24 * 3600,
) -> bool:
    """Return ``True`` iff this is the first claim for ``job_id``."""
    key = f"job:dedupe:{job_id}"
    ok = await redis.set(key, b"1", nx=True, ex=ttl_s)
    return bool(ok)


async def release(redis: redis_async.Redis, *, job_id: str) -> None:
    await redis.delete(f"job:dedupe:{job_id}")
