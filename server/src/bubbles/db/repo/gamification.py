"""Gamification repo: user_gamification + quests + rewards."""

from __future__ import annotations

from datetime import date
from uuid import UUID

import asyncpg

from bubbles.db.models import (
    QuestDefinition,
    Reward,
    UserGamification,
    UserQuest,
    UserReward,
)

_GAMIF_COLS = """
    user_id, total_xp, level, current_streak, longest_streak, streak_freezes,
    last_active_date, xp_spent, leaderboard_opt_in, updated_at
"""

_QUEST_DEF_COLS = """
    id, title, description, quest_type, action_type, target, xp_reward,
    is_active, focus_area, difficulty, mission_type, brief
"""

_USER_QUEST_COLS = """
    id, user_id, quest_id, progress, target, is_completed, xp_awarded,
    assigned_date, completed_at, created_at
"""

_REWARD_COLS = """
    id, title, description, icon, category, cost_xp, sort_order, is_active
"""

_USER_REWARD_COLS = "id, user_id, reward_id, cost_xp, unlocked_at"


def _gamif(row: asyncpg.Record) -> UserGamification:
    return UserGamification(
        user_id=row["user_id"],
        total_xp=row["total_xp"] or 0,
        level=row["level"] or 1,
        current_streak=row["current_streak"] or 0,
        longest_streak=row["longest_streak"] or 0,
        streak_freezes=row["streak_freezes"] or 0,
        last_active_date=row["last_active_date"],
        xp_spent=row["xp_spent"] or 0,
        leaderboard_opt_in=row["leaderboard_opt_in"] or False,
        updated_at=row["updated_at"],
    )


def _quest_def(row: asyncpg.Record) -> QuestDefinition:
    brief = row["brief"]
    if isinstance(brief, str):
        import json

        brief = json.loads(brief)
    return QuestDefinition(
        id=row["id"],
        title=row["title"],
        description=row["description"],
        quest_type=row["quest_type"] or "daily",
        action_type=row["action_type"],
        target=row["target"],
        xp_reward=row["xp_reward"] or 0,
        is_active=row["is_active"] or False,
        focus_area=row["focus_area"],
        difficulty=row["difficulty"] or "medium",
        mission_type=row["mission_type"] or "action",
        brief=brief,
    )


def _user_quest(row: asyncpg.Record) -> UserQuest:
    return UserQuest(
        id=row["id"],
        user_id=row["user_id"],
        quest_id=row["quest_id"],
        progress=row["progress"] or 0,
        target=row["target"],
        is_completed=row["is_completed"] or False,
        xp_awarded=row["xp_awarded"] or False,
        assigned_date=row["assigned_date"],
        completed_at=row["completed_at"],
        created_at=row["created_at"],
    )


def _reward(row: asyncpg.Record) -> Reward:
    return Reward(
        id=row["id"],
        title=row["title"],
        description=row["description"],
        icon=row["icon"] or "🎁",
        category=row["category"] or "general",
        cost_xp=row["cost_xp"],
        sort_order=row["sort_order"] or 0,
        is_active=row["is_active"] or False,
    )


def _user_reward(row: asyncpg.Record) -> UserReward:
    return UserReward(
        id=row["id"],
        user_id=row["user_id"],
        reward_id=row["reward_id"],
        cost_xp=row["cost_xp"],
        unlocked_at=row["unlocked_at"],
    )


# --- gamification state -----------------------------------------------------


async def get_or_init_gamification(conn: asyncpg.Connection, user_id: UUID) -> UserGamification:
    row = await conn.fetchrow(
        f"""
        INSERT INTO user_gamification (user_id)
        VALUES ($1)
        ON CONFLICT (user_id) DO UPDATE SET updated_at = user_gamification.updated_at
        RETURNING {_GAMIF_COLS}
        """,
        user_id,
    )
    assert row is not None
    return _gamif(row)


async def add_xp(conn: asyncpg.Connection, *, user_id: UUID, amount: int) -> UserGamification:
    if amount < 0:
        raise ValueError("amount must be non-negative")
    row = await conn.fetchrow(
        f"""
        INSERT INTO user_gamification (user_id, total_xp, last_active_date, updated_at)
        VALUES ($1, $2, CURRENT_DATE, NOW())
        ON CONFLICT (user_id) DO UPDATE SET
            total_xp = user_gamification.total_xp + EXCLUDED.total_xp,
            last_active_date = CURRENT_DATE,
            updated_at = NOW()
        RETURNING {_GAMIF_COLS}
        """,
        user_id,
        amount,
    )
    assert row is not None
    return _gamif(row)


async def set_leaderboard_opt_in(
    conn: asyncpg.Connection, *, user_id: UUID, opt_in: bool
) -> UserGamification:
    row = await conn.fetchrow(
        f"""
        UPDATE user_gamification SET leaderboard_opt_in = $2, updated_at = NOW()
        WHERE user_id = $1
        RETURNING {_GAMIF_COLS}
        """,
        user_id,
        opt_in,
    )
    if row is None:
        # First touch — create row first.
        await get_or_init_gamification(conn, user_id)
        return await set_leaderboard_opt_in(conn, user_id=user_id, opt_in=opt_in)
    return _gamif(row)


async def leaderboard_top(conn: asyncpg.Connection, *, limit: int = 50) -> list[asyncpg.Record]:
    rows = await conn.fetch(
        """
        SELECT user_id, total_xp, level, current_streak
        FROM user_gamification
        WHERE leaderboard_opt_in = true
        ORDER BY total_xp DESC
        LIMIT $1
        """,
        limit,
    )
    return list(rows)


# --- quests -----------------------------------------------------------------


async def list_active_quest_defs(conn: asyncpg.Connection) -> list[QuestDefinition]:
    rows = await conn.fetch(
        f"SELECT {_QUEST_DEF_COLS} FROM quest_definitions WHERE is_active = true"
    )
    return [_quest_def(r) for r in rows]


async def list_user_quests(
    conn: asyncpg.Connection, *, user_id: UUID, on_date: date | None = None
) -> list[UserQuest]:
    rows = await conn.fetch(
        f"""
        SELECT {_USER_QUEST_COLS}
        FROM user_quests
        WHERE user_id = $1
          AND ($2::date IS NULL OR assigned_date = $2)
        ORDER BY created_at DESC
        """,
        user_id,
        on_date,
    )
    return [_user_quest(r) for r in rows]


async def assign_quest(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    quest_id: UUID,
    target: int,
    assigned_date: date,
) -> UserQuest:
    row = await conn.fetchrow(
        f"""
        INSERT INTO user_quests (user_id, quest_id, target, assigned_date)
        VALUES ($1, $2, $3, $4)
        RETURNING {_USER_QUEST_COLS}
        """,
        user_id,
        quest_id,
        target,
        assigned_date,
    )
    assert row is not None
    return _user_quest(row)


async def increment_quest_progress(
    conn: asyncpg.Connection,
    *,
    user_quest_id: UUID,
    delta: int = 1,
) -> UserQuest | None:
    row = await conn.fetchrow(
        f"""
        UPDATE user_quests
        SET progress = LEAST(progress + $2, target),
            is_completed = (progress + $2) >= target,
            completed_at = CASE WHEN (progress + $2) >= target AND completed_at IS NULL
                                THEN NOW() ELSE completed_at END
        WHERE id = $1
        RETURNING {_USER_QUEST_COLS}
        """,
        user_quest_id,
        delta,
    )
    return _user_quest(row) if row is not None else None


# --- rewards ----------------------------------------------------------------


async def list_active_rewards(conn: asyncpg.Connection) -> list[Reward]:
    rows = await conn.fetch(
        f"""
        SELECT {_REWARD_COLS} FROM rewards
        WHERE is_active = true
        ORDER BY sort_order ASC, cost_xp ASC
        """
    )
    return [_reward(r) for r in rows]


async def redeem_reward(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    reward_id: UUID,
) -> UserReward:
    """Atomic redeem: deduct XP and record. Errors if insufficient XP."""
    cost_row = await conn.fetchrow(
        "SELECT cost_xp, is_active FROM rewards WHERE id = $1",
        reward_id,
    )
    if cost_row is None or not cost_row["is_active"]:
        raise ValueError("reward not available")
    cost: int = cost_row["cost_xp"]

    deducted = await conn.fetchrow(
        """
        UPDATE user_gamification
        SET xp_spent = xp_spent + $2, updated_at = NOW()
        WHERE user_id = $1 AND total_xp - xp_spent >= $2
        RETURNING user_id
        """,
        user_id,
        cost,
    )
    if deducted is None:
        raise ValueError("insufficient XP")

    row = await conn.fetchrow(
        f"""
        INSERT INTO user_rewards (user_id, reward_id, cost_xp)
        VALUES ($1, $2, $3)
        RETURNING {_USER_REWARD_COLS}
        """,
        user_id,
        reward_id,
        cost,
    )
    assert row is not None
    return _user_reward(row)
