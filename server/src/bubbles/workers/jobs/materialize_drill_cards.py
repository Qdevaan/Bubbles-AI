# Purpose: Background job that converts grammar errors and session mistakes into spaced-repetition drill flashcards.
"""materialize_drill_cards worker — turns this session's mistakes into drill cards.

Fired from the ``end_session`` fan-out alongside ``generate_scenarios``.
For every ``user_mistakes`` row tagged with the just-ended session id we
upsert one ``drill_cards`` row keyed by ``(user_id, rule_id, category)``,
prepending the snippet to the card's ``examples`` JSONB array (cap 10).

A no-op when the session has no mistakes. Idempotent at the ARQ level via
the ``materialize_drills:{user_id}:{session_id}`` job-id passed by the
``enqueue_materialize_drill_cards`` helper.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from bubbles.core.logging import get_logger
from bubbles.db.repo import drill_cards as drill_repo
from bubbles.db.repo import grammar as grammar_repo
from bubbles.db.repo.drill_cards import NewMistakeForCard
from bubbles.db.uow import UnitOfWork, transaction

__all__ = ["run"]

log = get_logger(__name__)


async def run(
    ctx: dict[str, Any], *, user_id: str, session_id: str
) -> dict[str, int]:
    """Upsert drill cards for this session's mistakes. Returns ``{"materialized": N}``."""
    bub = ctx["bubbles"]
    uid = UUID(user_id)
    sid = UUID(session_id)
    async with transaction(bub.pool) as conn:
        rows = await grammar_repo.list_for_session(conn, session_id=sid)
    if not rows:
        log.info("materialize_drills_noop", user=user_id, session=session_id)
        return {"materialized": 0}

    inputs = [
        NewMistakeForCard(
            mistake_id=r.id,
            rule_id=r.rule_id,
            category=r.category,
            snippet=r.snippet,
            suggestion=r.suggestion,
        )
        for r in rows
    ]
    async with UnitOfWork(bub.pool) as uow:
        touched = await drill_repo.upsert_from_mistakes(
            uow.conn, user_id=uid, mistakes=inputs
        )
    log.info(
        "materialize_drills_done",
        user=user_id,
        session=session_id,
        mistakes=len(inputs),
        cards_touched=touched,
    )
    return {"materialized": touched}
