"""Dashboard route integration tests."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.core.ratelimit import RateLimitResult
from bubbles.deps import get_pool, get_ratelimiter

pytestmark = pytest.mark.integration


class _FakeLimiter:
    async def check(
        self, key: str, *, capacity: int, refill_per_s: float, cost: int = 1
    ) -> RateLimitResult:
        return RateLimitResult(allowed=True, tokens_left=float(capacity), retry_after_s=0)


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[get_ratelimiter] = lambda: _FakeLimiter()
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email="t@t", role="authenticated"
    )


@pytest.mark.asyncio
async def test_dashboard_30d_returns_daily_granularity(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/dashboard?range=30d")
    assert r.status_code == 200
    body = r.json()
    assert body["range"] == "30d"
    assert body["granularity"] == "daily"
    assert len(body["series"]["xp_per_bucket"]) == 30
    assert all(p["value"] == 0 for p in body["series"]["xp_per_bucket"])
    assert body["summary"]["current_streak"] == 0
    assert body["summary"]["level"] == 1


@pytest.mark.asyncio
async def test_dashboard_90d_returns_weekly(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/dashboard?range=90d")
    assert r.status_code == 200
    body = r.json()
    assert body["granularity"] == "weekly"
    # 90 days / 7 = ~13 buckets
    assert 12 <= len(body["series"]["xp_per_bucket"]) <= 14


@pytest.mark.asyncio
async def test_dashboard_365d_returns_monthly(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/dashboard?range=365d")
    assert r.status_code == 200
    body = r.json()
    assert body["granularity"] == "monthly"
    assert 11 <= len(body["series"]["xp_per_bucket"]) <= 13


@pytest.mark.asyncio
async def test_dashboard_bad_range_returns_400(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/dashboard?range=7d")
    assert r.status_code == 400


@pytest.mark.asyncio
async def test_dashboard_owner_scoped(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID, other_user_id: UUID
) -> None:
    # Seed XP for the OTHER user; current user should still see zero.
    now = datetime.now(UTC)
    async with pool.acquire() as conn, conn.transaction():
        await conn.execute(
            "INSERT INTO xp_transactions (user_id, amount, source_type, created_at) "
            "VALUES ($1, 500, 'test', $2)",
            other_user_id,
            now - timedelta(days=1),
        )
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/dashboard?range=30d")
    body = r.json()
    assert body["summary"]["total_xp"]["current"] == 0


@pytest.mark.asyncio
async def test_dashboard_summary_includes_xp_delta(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    now = datetime.now(UTC)
    async with pool.acquire() as conn, conn.transaction():
        await conn.execute(
            "INSERT INTO xp_transactions (user_id, amount, source_type, created_at) "
            "VALUES ($1, 100, 'test', $2)",
            user_id,
            now - timedelta(days=5),
        )
        await conn.execute(
            "INSERT INTO xp_transactions (user_id, amount, source_type, created_at) "
            "VALUES ($1, 50, 'test', $2)",
            user_id,
            now - timedelta(days=45),
        )
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/dashboard?range=30d")
    body = r.json()
    assert body["summary"]["total_xp"]["current"] == 100
    assert body["summary"]["total_xp"]["previous"] == 50
    assert body["summary"]["total_xp"]["delta_pct"] == 100.0
