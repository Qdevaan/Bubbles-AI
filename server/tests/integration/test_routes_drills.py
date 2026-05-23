"""Drill routes integration tests — queue, review, retire."""

from __future__ import annotations

from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.core.ratelimit import RateLimitResult
from bubbles.db.repo import drill_cards as repo
from bubbles.db.repo.drill_cards import NewMistakeForCard
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
        id=str(uid), email=None, role="authenticated"
    )


def _override_other(app: FastAPI, pool: asyncpg.Pool, other_uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[get_ratelimiter] = lambda: _FakeLimiter()
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(other_uid), email=None, role="authenticated"
    )


async def _seed_card(pool: asyncpg.Pool, *, user_id: UUID, rule_id: str = "LLM_ARTICLE") -> UUID:
    async with pool.acquire() as conn, conn.transaction():
        await repo.upsert_from_mistakes(
            conn,
            user_id=user_id,
            mistakes=[
                NewMistakeForCard(
                    mistake_id=uuid4(),
                    rule_id=rule_id,
                    category="article",
                    snippet="I went to store.",
                    suggestion="I went to the store.",
                )
            ],
        )
        row = await conn.fetchrow(
            "SELECT id FROM drill_cards WHERE user_id = $1 AND rule_id = $2",
            user_id,
            rule_id,
        )
        assert row is not None
        return UUID(str(row["id"]))


async def _new_user(pool: asyncpg.Pool) -> UUID:
    uid = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", uid)
    return uid


@pytest.mark.asyncio
async def test_queue_returns_due_cards_for_owner_only(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    other_uid = await _new_user(pool)
    card_id = await _seed_card(pool, user_id=user_id)

    # Owner sees their due card.
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r_owner = await ac.get("/v1/drills/queue")
    assert r_owner.status_code == 200
    body = r_owner.json()
    assert body["total_due"] == 1
    assert len(body["items"]) == 1
    assert body["items"][0]["rule_id"] == "LLM_ARTICLE"
    assert body["items"][0]["id"] == str(card_id)

    # Other user sees nothing.
    _override_other(app, pool, other_uid)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r_other = await ac.get("/v1/drills/queue")
    assert r_other.status_code == 200
    assert r_other.json() == {"items": [], "total_due": 0}


@pytest.mark.asyncio
async def test_queue_include_upcoming_falls_back_when_due_empty(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    card_id = await _seed_card(pool, user_id=user_id)
    async with pool.acquire() as conn, conn.transaction():
        await conn.execute(
            "UPDATE drill_cards SET due_at = now() + interval '2 days' WHERE id = $1",
            card_id,
        )

    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r_no = await ac.get("/v1/drills/queue")
        r_up = await ac.get("/v1/drills/queue?include_upcoming=true")

    assert r_no.json()["items"] == []
    body = r_up.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["id"] == str(card_id)


@pytest.mark.asyncio
async def test_review_correct_awards_xp_and_advances_box(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    card_id = await _seed_card(pool, user_id=user_id)

    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/drills/{card_id}/review",
            json={"result": "correct"},
        )
    assert r.status_code == 200
    body = r.json()
    assert body["card"]["box"] == 2
    assert body["xp_awarded"] == 15
    assert body["transition"] == "1->2"

    # Same transition again is idempotent — XP not double-awarded.
    async with pool.acquire() as conn, conn.transaction():
        await conn.execute(
            "UPDATE drill_cards SET due_at = now(), box = 1 WHERE id = $1",
            card_id,
        )
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r2 = await ac.post(
            f"/v1/drills/{card_id}/review",
            json={"result": "correct"},
        )
    body2 = r2.json()
    assert body2["card"]["box"] == 2
    assert body2["xp_awarded"] == 0  # already awarded for 1->2 on this card
    assert body2["transition"] == "1->2"


@pytest.mark.asyncio
async def test_review_wrong_awards_showup_xp_and_resets(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    card_id = await _seed_card(pool, user_id=user_id)

    # Advance to box 2 first.
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        await ac.post(f"/v1/drills/{card_id}/review", json={"result": "correct"})

    async with pool.acquire() as conn, conn.transaction():
        await conn.execute(
            "UPDATE drill_cards SET due_at = now() WHERE id = $1", card_id
        )

    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/drills/{card_id}/review",
            json={"result": "wrong"},
        )
    body = r.json()
    assert body["card"]["box"] == 1
    assert body["xp_awarded"] == 5
    assert body["transition"] == "2->1"


@pytest.mark.asyncio
async def test_review_box_five_correct_awards_zero(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    card_id = await _seed_card(pool, user_id=user_id)
    async with pool.acquire() as conn, conn.transaction():
        await conn.execute(
            "UPDATE drill_cards SET box = 5, due_at = now() WHERE id = $1", card_id
        )

    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/drills/{card_id}/review",
            json={"result": "correct"},
        )
    body = r.json()
    assert body["card"]["box"] == 5
    assert body["xp_awarded"] == 0
    assert body["transition"] == "5->5"


@pytest.mark.asyncio
async def test_retire_then_review_409(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    card_id = await _seed_card(pool, user_id=user_id)

    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r1 = await ac.post(f"/v1/drills/{card_id}/retire")
    assert r1.status_code == 200
    assert r1.json()["retired_at"] is not None

    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r2 = await ac.post(f"/v1/drills/{card_id}/retire")
    assert r2.status_code == 409

    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r3 = await ac.post(
            f"/v1/drills/{card_id}/review",
            json={"result": "correct"},
        )
    assert r3.status_code == 409


@pytest.mark.asyncio
async def test_review_404_unknown_card(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/drills/{uuid4()}/review",
            json={"result": "correct"},
        )
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_review_403_cross_user(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    other_uid = await _new_user(pool)
    card_id = await _seed_card(pool, user_id=user_id)

    _override_other(app, pool, other_uid)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/drills/{card_id}/review",
            json={"result": "correct"},
        )
    assert r.status_code == 403
