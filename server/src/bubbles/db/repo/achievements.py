"""achievements / user_achievements repo (read-only for now)."""

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
