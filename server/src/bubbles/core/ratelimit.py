# Purpose: Token-bucket rate limiter backed by Redis; enforces per-user request quotas on expensive endpoints.
"""Atomic Redis token-bucket rate limiter.

One Lua script per call → one round-trip → atomic bucket update.
Returns ``RateLimitResult`` with ``allowed`` and ``retry_after``.
"""

from __future__ import annotations

import time
from dataclasses import dataclass

import redis.asyncio as redis_async

# capacity, refill_per_s, requested, now_ms
# returns: allowed (0|1), tokens_left (float), retry_after_ms
_TOKEN_BUCKET_LUA = """
local key = KEYS[1]
local capacity   = tonumber(ARGV[1])
local refill     = tonumber(ARGV[2])
local cost       = tonumber(ARGV[3])
local now_ms     = tonumber(ARGV[4])

local data = redis.call('HMGET', key, 'tokens', 'ts')
local tokens = tonumber(data[1])
local ts     = tonumber(data[2])

if tokens == nil then
    tokens = capacity
    ts = now_ms
end

local elapsed = math.max(0, now_ms - ts) / 1000.0
tokens = math.min(capacity, tokens + elapsed * refill)

local allowed = 0
local retry_after_ms = 0

if tokens >= cost then
    tokens = tokens - cost
    allowed = 1
else
    local deficit = cost - tokens
    retry_after_ms = math.ceil((deficit / refill) * 1000)
end

redis.call('HSET', key, 'tokens', tokens, 'ts', now_ms)
redis.call('PEXPIRE', key, math.ceil((capacity / refill) * 1000) + 1000)

return {allowed, tostring(tokens), retry_after_ms}
"""


@dataclass(frozen=True)
class RateLimitResult:
    allowed: bool
    tokens_left: float
    retry_after_s: int


class RateLimiter:
    """Async token-bucket limiter backed by Redis."""

    def __init__(self, redis: redis_async.Redis) -> None:
        self._redis = redis
        self._script = redis.register_script(_TOKEN_BUCKET_LUA)

    async def check(
        self,
        key: str,
        *,
        capacity: int,
        refill_per_s: float,
        cost: int = 1,
    ) -> RateLimitResult:
        now_ms = int(time.time() * 1000)
        result = await self._script(
            keys=[key],
            args=[capacity, refill_per_s, cost, now_ms],
        )
        allowed = bool(int(result[0]))
        tokens_left = float(result[1])
        retry_after_ms = int(result[2])
        return RateLimitResult(
            allowed=allowed,
            tokens_left=tokens_left,
            retry_after_s=max(1, (retry_after_ms + 999) // 1000) if not allowed else 0,
        )
