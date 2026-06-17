# Purpose: Repository for achievement/badge records: insert new awards and query a user's unlocked badges.
"""achievements / user_achievements repo."""

from __future__ import annotations

from uuid import UUID

import asyncpg

from bubbles.db.models import Achievement, UserBadge

_A_COLS = """
    a.id, a.code, a.title, a.description, a.icon, a.category,
    a.criteria_type, a.criteria_value, a.xp_reward, a.tier, a.created_at
"""


def _achievement(row: asyncpg.Record) -> Achievement:
    return Achievement(
        id=row["id"],
        code=row["code"],
        title=row["title"],
        description=row["description"],
        icon=row["icon"] or "🏆",
        category=row["category"] or "general",
        criteria_type=row["criteria_type"],
        criteria_value=row["criteria_value"],
        xp_reward=row["xp_reward"] or 0,
        tier=row["tier"],
        created_at=row["created_at"],
    )


async def list_for_user(conn: asyncpg.Connection, *, user_id: UUID) -> list[UserBadge]:
    rows = await conn.fetch(
        f"""
        SELECT {_A_COLS}, ua.awarded_at
        FROM user_achievements ua
        JOIN achievements a ON a.id = ua.achievement_id
        WHERE ua.user_id = $1
        ORDER BY ua.awarded_at DESC
        """,
        user_id,
    )
    return [UserBadge(achievement=_achievement(r), awarded_at=r["awarded_at"]) for r in rows]


async def list_unearned(conn: asyncpg.Connection, *, user_id: UUID) -> list[Achievement]:
    """Achievement definitions the user has not been awarded yet."""
    rows = await conn.fetch(
        f"""
        SELECT {_A_COLS}, NULL::timestamptz AS awarded_at
        FROM achievements a
        WHERE NOT EXISTS (
            SELECT 1 FROM user_achievements ua
            WHERE ua.achievement_id = a.id AND ua.user_id = $1
        )
        """,
        user_id,
    )
    return [_achievement(r) for r in rows]


async def award(conn: asyncpg.Connection, *, user_id: UUID, achievement_id: UUID) -> bool:
    """Insert a ``user_achievements`` row. Returns ``False`` if already present."""
    row = await conn.fetchrow(
        """
        INSERT INTO user_achievements (user_id, achievement_id)
        VALUES ($1, $2)
        ON CONFLICT (user_id, achievement_id) DO NOTHING
        RETURNING id
        """,
        user_id,
        achievement_id,
    )
    return row is not None
