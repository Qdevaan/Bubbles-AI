# Purpose: Background job that re-runs entity extraction on old sessions missing knowledge-graph entries.
"""One-off backfill: populate ``session_entities`` for sessions that predate it.

Alembic ``0002`` added ``session_entities``; it's filled going forward by the
``extract_knowledge`` job. Sessions created before that have no rows. We can
only backfill sessions that have a stored transcript (``session_logs`` rows —
i.e. sessions from H2 onward); truly old sessions have no transcript anywhere
and are skipped. An operator enqueues this via ``enqueue_backfill_session_entities``
(or ``arq``) and can re-run it until ``sessions_processed`` is 0.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from bubbles.core.logging import get_logger
from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.workers.jobs import extract_knowledge

if TYPE_CHECKING:
    from bubbles.workers.arq_settings import WorkerCtx

log = get_logger(__name__)


async def run(ctx: dict[str, Any], *, limit: int = 200) -> dict[str, int]:
    bub: WorkerCtx = ctx["bubbles"]
    async with bub.pool.acquire() as con:
        rows = await con.fetch(
            """
            SELECT s.id, s.user_id
            FROM sessions s
            WHERE s.deleted_at IS NULL
              AND EXISTS (SELECT 1 FROM session_logs sl WHERE sl.session_id = s.id)
              AND NOT EXISTS (SELECT 1 FROM session_entities se WHERE se.session_id = s.id)
            ORDER BY s.created_at DESC
            LIMIT $1
            """,
            limit,
        )
    processed = 0
    for r in rows:
        async with bub.pool.acquire() as con:
            transcript = await session_logs_repo.assemble_transcript(con, session_id=r["id"])
        if not transcript.strip():
            continue
        await extract_knowledge.run(
            ctx, user_id=str(r["user_id"]), session_id=str(r["id"]), transcript=transcript
        )
        processed += 1
    log.info("backfill_session_entities_done", sessions_processed=processed, scanned=len(rows))
    return {"sessions_processed": processed, "scanned": len(rows)}
