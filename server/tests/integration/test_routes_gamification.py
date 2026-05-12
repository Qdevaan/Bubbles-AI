"""Gamification HTTP route integration tests."""

from __future__ import annotations

from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.deps import get_pool

pytestmark = pytest.mark.integration


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )


async def _new_user(pool: asyncpg.Pool) -> UUID:
    uid = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", uid)
    return uid


async def test_get_profile_fresh_user(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/gamification/{user_id}")
    assert r.status_code == 200
    body = r.json()
    assert body["user_id"] == str(user_id)
    assert body["xp"] == 0
    assert body["level"] == 1
    assert body["xp_progress_pct"] == 0.0
    assert body["badges"] == []
    assert body["recent_xp"] == []


async def test_get_profile_reflects_xp_and_badge(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    from bubbles.db.repo import gamification as grepo
    from bubbles.db.uow import UnitOfWork

    async with UnitOfWork(pool) as uow:
        await grepo.add_xp(uow.conn, user_id=user_id, amount=150, source_type="m", source_id="x")
        a = await uow.conn.fetchrow(
            "INSERT INTO achievements (code, title, criteria_type, criteria_value)"
            " VALUES ('xp_100', 'Centurion', 'total_xp', 100) RETURNING id"
        )
        await uow.conn.execute(
            "INSERT INTO user_achievements (user_id, achievement_id) VALUES ($1, $2)",
            user_id,
            a["id"],
        )
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/gamification/{user_id}")
    body = r.json()
    assert body["xp"] == 150
    assert body["level"] == 2  # xp_for_level(2) == 100
    assert len(body["badges"]) == 1
    assert body["badges"][0]["code"] == "xp_100"
    assert len(body["recent_xp"]) == 1
    assert body["recent_xp"][0]["amount"] == 150


async def test_get_profile_other_user_403(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    other = await _new_user(pool)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/gamification/{other}")
    assert r.status_code == 403


async def _seed_quest_defs(pool: asyncpg.Pool, n: int = 4) -> None:
    async with pool.acquire() as con:
        for i in range(n):
            await con.execute(
                "INSERT INTO quest_definitions (title, action_type, target, xp_reward)"
                " VALUES ($1, 'session_count', 1, 10)",
                f"q{i}",
            )


async def test_get_quests_assigns_then_stable(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    await _seed_quest_defs(pool, 4)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r1 = await ac.get(f"/v1/quests/{user_id}")
        r2 = await ac.get(f"/v1/quests/{user_id}")
    assert r1.status_code == 200
    b1, b2 = r1.json(), r2.json()
    assert b1["total_quests_today"] == 3
    assert len(b1["quests"]) == 3
    assert {q["id"] for q in b1["quests"]} == {q["id"] for q in b2["quests"]}
    assert b1["daily_reset_at"].endswith("+00:00") or b1["daily_reset_at"].endswith("Z")
    assert b1["total_completed_today"] == 0


async def test_get_quests_other_user_403(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    other = await _new_user(pool)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/quests/{other}")
    assert r.status_code == 403


async def _seed_rewards(pool: asyncpg.Pool) -> tuple[UUID, UUID]:
    async with pool.acquire() as con:
        cheap = await con.fetchrow(
            "INSERT INTO rewards (title, cost_xp, sort_order) VALUES ('sticker', 50, 1) RETURNING id"
        )
        dear = await con.fetchrow(
            "INSERT INTO rewards (title, cost_xp, sort_order) VALUES ('trophy', 5000, 2) RETURNING id"
        )
    return cheap["id"], dear["id"]


async def test_rewards_catalog_shows_affordability_and_ownership(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    from bubbles.db.repo import gamification as grepo
    from bubbles.db.uow import UnitOfWork

    cheap_id, dear_id = await _seed_rewards(pool)
    async with UnitOfWork(pool) as uow:
        await grepo.add_xp(uow.conn, user_id=user_id, amount=200)
        await grepo.redeem_reward(uow.conn, user_id=user_id, reward_id=cheap_id)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/rewards/{user_id}")
    assert r.status_code == 200
    body = r.json()
    assert body["balance_xp"] == 150  # 200 earned - 50 spent
    by_id = {x["id"]: x for x in body["rewards"]}
    assert by_id[str(cheap_id)]["owned"] is True
    assert by_id[str(cheap_id)]["affordable"] is True  # 150 >= 50
    assert by_id[str(dear_id)]["owned"] is False
    assert by_id[str(dear_id)]["affordable"] is False  # 150 < 5000


async def test_redeem_happy_path(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    from bubbles.db.repo import gamification as grepo
    from bubbles.db.uow import UnitOfWork

    cheap_id, _ = await _seed_rewards(pool)
    async with UnitOfWork(pool) as uow:
        await grepo.add_xp(uow.conn, user_id=user_id, amount=200)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(f"/v1/rewards/{user_id}/redeem", json={"reward_id": str(cheap_id)})
    assert r.status_code == 200
    body = r.json()
    assert body["reward_id"] == str(cheap_id)
    assert body["cost_xp"] == 50
    assert body["balance_xp"] == 150


async def test_redeem_insufficient_xp_400(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _, dear_id = await _seed_rewards(pool)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(f"/v1/rewards/{user_id}/redeem", json={"reward_id": str(dear_id)})
    assert r.status_code == 400
    assert "insufficient" in r.json()["error"]["message"].lower()


async def test_redeem_unknown_reward_400(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(f"/v1/rewards/{user_id}/redeem", json={"reward_id": str(uuid4())})
    assert r.status_code == 400


async def test_rewards_other_user_403(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    other = await _new_user(pool)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r1 = await ac.get(f"/v1/rewards/{other}")
        r2 = await ac.post(f"/v1/rewards/{other}/redeem", json={"reward_id": str(uuid4())})
    assert r1.status_code == 403
    assert r2.status_code == 403
