"""Job idempotency claim/release."""

from __future__ import annotations

import pytest

fakeredis = pytest.importorskip("fakeredis.aioredis")

from bubbles.workers.idempotency import claim, release  # noqa: E402


async def test_claim_returns_true_first_time() -> None:
    r = fakeredis.FakeRedis()
    assert await claim(r, job_id="j1") is True


async def test_claim_blocks_duplicate() -> None:
    r = fakeredis.FakeRedis()
    assert await claim(r, job_id="j2") is True
    assert await claim(r, job_id="j2") is False


async def test_release_allows_reclaim() -> None:
    r = fakeredis.FakeRedis()
    await claim(r, job_id="j3")
    await release(r, job_id="j3")
    assert await claim(r, job_id="j3") is True
