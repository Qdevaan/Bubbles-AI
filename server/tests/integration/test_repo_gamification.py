"""Gamification repo integration tests."""

from __future__ import annotations

from datetime import date
from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import gamification as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def test_init_and_add_xp(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        first = await repo.get_or_init_gamification(uow.conn, user_id)
        bumped = await repo.add_xp(uow.conn, user_id=user_id, amount=50)
    assert first.total_xp == 0
    assert bumped.total_xp == 50


async def test_redeem_reward_insufficient_xp(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        await repo.get_or_init_gamification(uow.conn, user_id)
        reward_id_row = await uow.conn.fetchrow(
            "INSERT INTO rewards (title, cost_xp) VALUES ('voucher', 100) RETURNING id"
        )
    reward_id = reward_id_row["id"]
    async with UnitOfWork(pool) as uow:
        with pytest.raises(ValueError, match="insufficient"):
            await repo.redeem_reward(uow.conn, user_id=user_id, reward_id=reward_id)


async def test_redeem_reward_succeeds(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        await repo.add_xp(uow.conn, user_id=user_id, amount=200)
        row = await uow.conn.fetchrow(
            "INSERT INTO rewards (title, cost_xp) VALUES ('voucher', 100) RETURNING id"
        )
    reward_id = row["id"]
    async with UnitOfWork(pool) as uow:
        ur = await repo.redeem_reward(uow.conn, user_id=user_id, reward_id=reward_id)
    assert ur.cost_xp == 100


async def test_assign_and_progress_quest(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        qd_row = await uow.conn.fetchrow(
            """
            INSERT INTO quest_definitions (title, action_type, target, xp_reward)
            VALUES ('three sessions', 'session_count', 3, 30)
            RETURNING id
            """
        )
        uq = await repo.assign_quest(
            uow.conn,
            user_id=user_id,
            quest_id=qd_row["id"],
            target=3,
            assigned_date=date.today(),
        )
        for _ in range(3):
            updated = await repo.increment_quest_progress(uow.conn, user_quest_id=uq.id)
    assert updated is not None
    assert updated.is_completed is True
    assert updated.progress == 3
