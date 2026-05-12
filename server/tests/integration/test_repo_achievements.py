"""achievements / user_achievements repo integration tests."""

from __future__ import annotations

from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import achievements as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def test_list_for_user_empty(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        badges = await repo.list_for_user(uow.conn, user_id=user_id)
    assert badges == []


async def test_list_for_user_returns_earned_badges_newest_first(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    async with UnitOfWork(pool) as uow:
        a1 = await uow.conn.fetchrow(
            "INSERT INTO achievements (code, title, criteria_type, criteria_value)"
            " VALUES ('streak_3', 'On a roll', 'streak_days', 3) RETURNING id"
        )
        a2 = await uow.conn.fetchrow(
            "INSERT INTO achievements (code, title, criteria_type, criteria_value)"
            " VALUES ('xp_1000', 'Grinder', 'total_xp', 1000) RETURNING id"
        )
        await uow.conn.execute(
            "INSERT INTO user_achievements (user_id, achievement_id, awarded_at)"
            " VALUES ($1, $2, now() - interval '2 days')",
            user_id,
            a1["id"],
        )
        await uow.conn.execute(
            "INSERT INTO user_achievements (user_id, achievement_id, awarded_at)"
            " VALUES ($1, $2, now())",
            user_id,
            a2["id"],
        )
        badges = await repo.list_for_user(uow.conn, user_id=user_id)
    assert [b.achievement.code for b in badges] == ["xp_1000", "streak_3"]
    assert badges[0].achievement.title == "Grinder"
    assert badges[0].awarded_at >= badges[1].awarded_at
