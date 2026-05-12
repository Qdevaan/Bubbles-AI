"""H6: daily XP cap, streak increments + milestone bonus, achievement worker."""

from __future__ import annotations

from datetime import date, timedelta
from types import SimpleNamespace
from typing import Any
from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import gamification as gamification_repo
from bubbles.workers.jobs import detect_achievements

pytestmark = pytest.mark.integration


# --- daily XP cap ----------------------------------------------------------


async def test_add_xp_daily_cap_clamps_automated_sources(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as con:
        g1 = await gamification_repo.add_xp(
            con, user_id=user_id, amount=400, source_type="session", source_id="s1"
        )
        assert g1.total_xp == 400
        # 200 more requested, only 100 of the daily cap left -> clamped to 100.
        g2 = await gamification_repo.add_xp(
            con, user_id=user_id, amount=200, source_type="session", source_id="s2"
        )
        assert g2.total_xp == 500
        # Further capped awards add nothing.
        g3 = await gamification_repo.add_xp(
            con, user_id=user_id, amount=50, source_type="extraction", source_id="e1"
        )
        assert g3.total_xp == 500
        # Exempt source bypasses the cap entirely.
        g4 = await gamification_repo.add_xp(
            con, user_id=user_id, amount=1000, source_type="quest", source_id="q1", capped=False
        )
        assert g4.total_xp == 1500


# --- streaks ---------------------------------------------------------------


async def test_update_streak_consecutive_and_idempotent(pool: asyncpg.Pool, user_id: UUID) -> None:
    day = date(2026, 5, 12)
    async with pool.acquire() as con:
        g1 = await gamification_repo.update_streak(con, user_id=user_id, today=day)
        assert (g1.current_streak, g1.longest_streak) == (1, 1)
        # Same day again — no change.
        g1b = await gamification_repo.update_streak(con, user_id=user_id, today=day)
        assert g1b.current_streak == 1
        # Next day — +1.
        g2 = await gamification_repo.update_streak(
            con, user_id=user_id, today=day + timedelta(days=1)
        )
        assert (g2.current_streak, g2.longest_streak) == (2, 2)
        # Three-day gap — reset to 1 (longest preserved).
        g3 = await gamification_repo.update_streak(
            con, user_id=user_id, today=day + timedelta(days=5)
        )
        assert (g3.current_streak, g3.longest_streak) == (1, 2)


async def test_update_streak_uses_freeze_on_one_day_gap(pool: asyncpg.Pool, user_id: UUID) -> None:
    day = date(2026, 5, 12)
    async with pool.acquire() as con:
        await con.execute(
            """
            INSERT INTO user_gamification (user_id, current_streak, longest_streak,
                streak_freezes, last_active_date)
            VALUES ($1, 4, 4, 1, $2)
            """,
            user_id,
            day,
        )
        # last_active = day, today = day+2 -> one missed day, one freeze available.
        g = await gamification_repo.update_streak(
            con, user_id=user_id, today=day + timedelta(days=2)
        )
        assert g.current_streak == 5
        assert g.streak_freezes == 0


async def test_update_streak_milestone_awards_bonus_xp(pool: asyncpg.Pool, user_id: UUID) -> None:
    day = date(2026, 5, 12)
    async with pool.acquire() as con:
        await con.execute(
            """
            INSERT INTO user_gamification (user_id, current_streak, longest_streak,
                streak_freezes, last_active_date)
            VALUES ($1, 6, 6, 1, $2)
            """,
            user_id,
            day,
        )
        g = await gamification_repo.update_streak(
            con, user_id=user_id, today=day + timedelta(days=1)
        )
        assert g.current_streak == 7
        assert g.total_xp == 50  # 7-day milestone bonus
        bonus_rows = await con.fetch(
            "SELECT amount, source_type FROM xp_transactions WHERE user_id = $1", user_id
        )
    assert [(r["amount"], r["source_type"]) for r in bonus_rows] == [(50, "streak_milestone")]


# --- achievement worker ----------------------------------------------------


async def test_detect_achievements_awards_and_is_idempotent(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    async with pool.acquire() as con:
        await con.execute(
            """
            INSERT INTO user_gamification (user_id, total_xp, last_active_date)
            VALUES ($1, 150, CURRENT_DATE)
            """,
            user_id,
        )
        ach_id = await con.fetchval(
            """
            INSERT INTO achievements (title, criteria_type, criteria_value, xp_reward)
            VALUES ('Centurion', 'total_xp', 100, 25) RETURNING id
            """
        )
        # An unmet achievement that must NOT be awarded.
        await con.execute(
            """
            INSERT INTO achievements (title, criteria_type, criteria_value, xp_reward)
            VALUES ('Marathoner', 'sessions_total', 10, 0)
            """
        )

    ctx: dict[str, Any] = {"bubbles": SimpleNamespace(pool=pool)}
    r1 = await detect_achievements.run(ctx, user_id=str(user_id))
    assert r1 == {"awarded": 1}
    r2 = await detect_achievements.run(ctx, user_id=str(user_id))
    assert r2 == {"awarded": 0}

    async with pool.acquire() as con:
        owned = await con.fetch(
            "SELECT achievement_id FROM user_achievements WHERE user_id = $1", user_id
        )
        g = await gamification_repo.get_or_init_gamification(con, user_id)
    assert [r["achievement_id"] for r in owned] == [ach_id]
    assert g.total_xp == 175  # 150 + 25 reward (exempt from cap)
