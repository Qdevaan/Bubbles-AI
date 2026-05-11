"""Seed default quest definitions if none exist."""

from __future__ import annotations

from typing import Any

from bubbles.core.logging import get_logger
from bubbles.db.uow import UnitOfWork

log = get_logger(__name__)


_DEFAULTS: list[dict[str, Any]] = [
    {
        "title": "Daily reflection",
        "description": "Hold one consultant session today.",
        "action_type": "session_count",
        "target": 1,
        "xp_reward": 20,
        "focus_area": "reflection",
        "difficulty": "easy",
    },
    {
        "title": "Three turns",
        "description": "Have three back-and-forth turns in any session.",
        "action_type": "user_turn_count",
        "target": 3,
        "xp_reward": 15,
        "focus_area": "engagement",
        "difficulty": "easy",
    },
    {
        "title": "Polish your grammar",
        "description": "Resolve five flagged mistakes.",
        "action_type": "mistakes_resolved",
        "target": 5,
        "xp_reward": 25,
        "focus_area": "grammar",
        "difficulty": "medium",
    },
]


async def run(ctx: dict[str, Any]) -> int:
    bub = ctx["bubbles"]
    inserted = 0
    async with UnitOfWork(bub.pool) as uow:
        existing = await uow.conn.fetchval("SELECT COUNT(*)::int FROM quest_definitions")
        if existing and existing > 0:
            return 0
        for q in _DEFAULTS:
            await uow.conn.execute(
                """
                INSERT INTO quest_definitions
                    (title, description, action_type, target, xp_reward,
                     focus_area, difficulty, is_active)
                VALUES ($1, $2, $3, $4, $5, $6, $7, true)
                """,
                q["title"],
                q["description"],
                q["action_type"],
                q["target"],
                q["xp_reward"],
                q["focus_area"],
                q["difficulty"],
            )
            inserted += 1
    log.info("seed_quests_done", inserted=inserted)
    return inserted
