# Purpose: Background job that maintains a rolling summary of the user's session history for the memory store.
"""Rolling-summary job — every N turns, summarise recent session_logs.

Reads the last ``_TAIL_TURNS`` turns from ``session_logs``, asks the wingman
to generate a short summary, and appends ``\\n---\\n[Turn N] {summary}`` to
``sessions.summary``. Best-effort: a failed LLM call returns ``{"updated": 0}``
without touching the row, so the wingman path never sees the failure.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from bubbles.ai.extraction import generate_summary
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.db.uow import UnitOfWork

log = get_logger(__name__)

_TAIL_TURNS = 40


async def run(
    ctx: dict[str, Any],
    *,
    user_id: str,
    session_id: str,
    turn_index: int,
) -> dict[str, int]:
    bub = ctx["bubbles"]
    sid = UUID(session_id)
    async with UnitOfWork(bub.pool) as uow:
        partial = await session_logs_repo.assemble_transcript(
            uow.conn, session_id=sid, last_n=_TAIL_TURNS
        )
    if not partial.strip():
        return {"updated": 0}

    try:
        summary = (await generate_summary(bub.ai.router, partial)).strip()
    except UpstreamUnavailable as exc:
        log.warning(
            "rolling_summarize_upstream", error=str(exc), session_id=session_id, user_id=user_id
        )
        return {"updated": 0}
    if not summary:
        return {"updated": 0}

    fragment = f"[Turn {turn_index}] {summary}"
    async with UnitOfWork(bub.pool) as uow:
        result = await uow.conn.execute(
            """
            UPDATE sessions
            SET summary = CASE
                WHEN summary IS NULL OR summary = '' THEN $2
                ELSE summary || E'\n---\n' || $2
            END
            WHERE id = $1 AND deleted_at IS NULL
            """,
            sid,
            fragment,
        )
    updated = 1 if result.endswith(" 1") else 0
    return {"updated": updated}
