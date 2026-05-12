"""Gamification repo integration tests."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
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


async def test_add_xp_with_source_id_is_idempotent(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        first = await repo.add_xp(
            uow.conn, user_id=user_id, amount=30, source_type="session_complete", source_id="sx"
        )
        again = await repo.add_xp(
            uow.conn, user_id=user_id, amount=30, source_type="session_complete", source_id="sx"
        )
        ledger = await uow.conn.fetch(
            "SELECT amount FROM xp_transactions WHERE user_id=$1", user_id
        )
    assert first.total_xp == 30
    assert again.total_xp == 30  # no second bump
    assert len(ledger) == 1  # no second ledger row


async def test_get_or_assign_daily_quests_assigns_then_is_stable(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    async with UnitOfWork(pool) as uow:
        for i in range(5):
            await uow.conn.execute(
                "INSERT INTO quest_definitions (title, action_type, target, xp_reward)"
                " VALUES ($1, 'session_count', 1, 10)",
                f"q{i}",
            )
        await repo.get_or_init_gamification(uow.conn, user_id)
        today = date.today()
        first = await repo.get_or_assign_daily_quests(uow.conn, user_id=user_id, on_date=today)
        second = await repo.get_or_assign_daily_quests(uow.conn, user_id=user_id, on_date=today)
        later = await repo.get_or_assign_daily_quests(
            uow.conn, user_id=user_id, on_date=today + timedelta(days=1)
        )
    assert len(first) == 3
    assert {q.id for q in first} == {q.id for q in second}  # same rows
    assert {q.id for q in first}.isdisjoint({q.id for q in later})  # fresh assignment


async def test_get_or_assign_daily_quests_no_defs_returns_empty(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    async with UnitOfWork(pool) as uow:
        await repo.get_or_init_gamification(uow.conn, user_id)
        out = await repo.get_or_assign_daily_quests(uow.conn, user_id=user_id, on_date=date.today())
    assert out == []


async def test_owned_reward_ids(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        await repo.add_xp(uow.conn, user_id=user_id, amount=500)
        r = await uow.conn.fetchrow(
            "INSERT INTO rewards (title, cost_xp) VALUES ('badge', 100) RETURNING id"
        )
        await repo.redeem_reward(uow.conn, user_id=user_id, reward_id=r["id"])
        owned = await repo.owned_reward_ids(uow.conn, user_id=user_id)
    assert owned == {r["id"]}


async def test_leaderboard_and_ranks(pool: asyncpg.Pool, user_id: UUID) -> None:
    other = UUID(int=user_id.int ^ 1)  # deterministic distinct uuid
    async with UnitOfWork(pool) as uow:
        await uow.conn.execute("INSERT INTO auth.users (id) VALUES ($1)", other)
        # caller: 100 total, opted in; other: 300 total, opted in
        await repo.add_xp(uow.conn, user_id=user_id, amount=100)
        await repo.add_xp(uow.conn, user_id=other, amount=300)
        await repo.set_leaderboard_opt_in(uow.conn, user_id=user_id, opt_in=True)
        await repo.set_leaderboard_opt_in(uow.conn, user_id=other, opt_in=True)
        top = await repo.leaderboard_top(uow.conn, limit=10)
        my_all_rank = await repo.rank_all_time(uow.conn, user_id=user_id)
        # period: both add_xp calls wrote xp_transactions rows with created_at = now()
        now = datetime.now(UTC)
        per = await repo.leaderboard_period(uow.conn, since=now - timedelta(days=1), limit=10)
        my_per_rank = await repo.rank_period(
            uow.conn, user_id=user_id, since=now - timedelta(days=1)
        )
    assert [r["user_id"] for r in top][:2] == [other, user_id]  # 300 before 100
    assert my_all_rank == 2
    assert {r["user_id"] for r in per} == {user_id, other}
    assert my_per_rank == 2
