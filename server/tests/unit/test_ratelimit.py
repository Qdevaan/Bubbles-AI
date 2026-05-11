"""Token-bucket rate limiter against fakeredis."""

from __future__ import annotations

from typing import Any

import pytest

fakeredis = pytest.importorskip("fakeredis.aioredis")

from bubbles.core.ratelimit import RateLimiter  # noqa: E402


def _client() -> Any:
    return fakeredis.FakeRedis()


async def test_allows_within_capacity() -> None:
    rl = RateLimiter(_client())
    res = await rl.check("u:1", capacity=3, refill_per_s=1)
    assert res.allowed is True
    assert res.tokens_left == pytest.approx(2.0, abs=0.05)


async def test_rejects_over_capacity() -> None:
    rl = RateLimiter(_client())
    for _ in range(3):
        await rl.check("u:2", capacity=3, refill_per_s=1)
    res = await rl.check("u:2", capacity=3, refill_per_s=1)
    assert res.allowed is False
    assert res.retry_after_s >= 1
