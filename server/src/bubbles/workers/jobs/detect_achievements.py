"""Award any achievements whose criteria the user now meets.

Enqueued after activity that can change a user's stats (e.g. ``end_session``).
Idempotent: ``user_achievements`` has a unique ``(user_id, achievement_id)``
and the XP reward is deduped on its ledger ``source_id``.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING, Any
from uuid import UUID

from bubbles.core.gamification import level_for_xp
from bubbles.core.logging import get_logger
from bubbles.db.repo import achievements as achievements_repo
from bubbles.db.repo import gamification as gamification_repo
from bubbles.db.uow import UnitOfWork

if TYPE_CHECKING:
    import asyncpg

    from bubbles.workers.arq_settings import WorkerCtx

log = get_logger(__name__)

# criteria_type (lowercased) -> how to read it from the computed stats dict.
_CRITERIA: dict[str, Callable[[dict[str, int]], int]] = {
    "total_xp": lambda s: s["total_xp"],
    "xp_total": lambda s: s["total_xp"],
    "xp": lambda s: s["total_xp"],
    "level": lambda s: s["level"],
    "current_streak": lambda s: s["current_streak"],
    "streak": lambda s: s["current_streak"],
    "streak_days": lambda s: s["current_streak"],
    "longest_streak": lambda s: s["longest_streak"],
    "sessions_total": lambda s: s["sessions"],
    "sessions_count": lambda s: s["sessions"],
    "session_count": lambda s: s["sessions"],
    "memories_total": lambda s: s["memories"],
    "memories_count": lambda s: s["memories"],
    "memory_count": lambda s: s["memories"],
    "entities_total": lambda s: s["entities"],
    "entities_count": lambda s: s["entities"],
    "entity_count": lambda s: s["entities"],
    "quests_completed": lambda s: s["quests_completed"],
    "mistakes_total": lambda s: s["mistakes"],
}


async def _compute_stats(conn: asyncpg.Connection, user_id: UUID) -> dict[str, int]:
    g = await gamification_repo.get_or_init_gamification(conn, user_id)
    sessions = await conn.fetchval(
        "SELECT count(*)::int FROM sessions WHERE user_id = $1 AND deleted_at IS NULL", user_id
    )
    memories = await conn.fetchval(
        "SELECT count(*)::int FROM memory WHERE user_id = $1 AND is_archived = false", user_id
    )
    entities = await conn.fetchval(
        "SELECT count(*)::int FROM entities WHERE user_id = $1 AND is_archived = false", user_id
    )
    quests_completed = await conn.fetchval(
        "SELECT count(*)::int FROM user_quests WHERE user_id = $1 AND is_completed = true", user_id
    )
    mistakes = await conn.fetchval(
        "SELECT count(*)::int FROM user_mistakes WHERE user_id = $1", user_id
    )
    return {
        "total_xp": g.total_xp,
        "level": level_for_xp(g.total_xp),
        "current_streak": g.current_streak,
        "longest_streak": g.longest_streak,
        "sessions": int(sessions or 0),
        "memories": int(memories or 0),
        "entities": int(entities or 0),
        "quests_completed": int(quests_completed or 0),
        "mistakes": int(mistakes or 0),
    }


async def run(ctx: dict[str, Any], *, user_id: str) -> dict[str, int]:
    bub: WorkerCtx = ctx["bubbles"]
    user_uuid = UUID(user_id)
    awarded = 0
    async with UnitOfWork(bub.pool) as uow:
        candidates = await achievements_repo.list_unearned(uow.conn, user_id=user_uuid)
        if not candidates:
            return {"awarded": 0}
        stats = await _compute_stats(uow.conn, user_uuid)
        for ach in candidates:
            getter = _CRITERIA.get((ach.criteria_type or "").lower())
            if getter is None or getter(stats) < ach.criteria_value:
                continue
            if not await achievements_repo.award(
                uow.conn, user_id=user_uuid, achievement_id=ach.id
            ):
                continue
            awarded += 1
            if ach.xp_reward > 0:
                await gamification_repo.add_xp(
                    uow.conn,
                    user_id=user_uuid,
                    amount=ach.xp_reward,
                    source_type="achievement",
                    source_id=str(ach.id),
                    description=f"Achievement: {ach.title}",
                    capped=False,
                )
    if awarded:
        log.info("achievements_awarded", user=user_id, count=awarded)
    return {"awarded": awarded}
