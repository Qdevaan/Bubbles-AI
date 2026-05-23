"""generate_scenarios worker — tops up a user's roleplay scenario feed.

Enqueued from the end_session fan-out. Self-throttling: a no-op when the
feed already holds ``_TARGET_FEED`` suggested scenarios.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from bubbles.ai import scenarios as scenario_gen
from bubbles.core.logging import get_logger
from bubbles.db.repo import scenarios as scenarios_repo
from bubbles.db.uow import UnitOfWork, transaction

__all__ = ["run", "scenario_gen"]

log = get_logger(__name__)

_TARGET_FEED = 5


async def run(ctx: dict[str, Any], *, user_id: str) -> int:
    """Generate scenarios until the feed reaches ``_TARGET_FEED``. Returns count created."""
    bub = ctx["bubbles"]
    uid = UUID(user_id)
    async with transaction(bub.pool) as conn:
        active = await scenarios_repo.count_active(conn, user_id=uid)
    gap = _TARGET_FEED - active
    if gap <= 0:
        return 0
    async with transaction(bub.pool) as conn:
        drafts = await scenario_gen.generate(conn, bub.ai.router, user_id=uid, count=gap)
    if not drafts:
        return 0
    async with UnitOfWork(bub.pool) as uow:
        created = await scenarios_repo.create_many(uow.conn, user_id=uid, rows=drafts)
    log.info("generate_scenarios_done", user=user_id, created=len(created))
    return len(created)
