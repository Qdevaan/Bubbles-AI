# Purpose: Background job that runs sentiment analysis on session turns and flags emotional tone shifts.
"""Score per-turn sentiment for a session's stored turns, then re-run analytics.

Reads ``session_logs`` rows that don't have a ``sentiment_score`` yet (user /
others turns only — LLM advice turns aren't user sentiment), asks the
``analytics.sentiment`` chain to score them in batches, writes
``sentiment_score`` / ``sentiment_label`` back, then re-enqueues
``compute_session_analytics`` (with a distinct job id so it isn't deduped) so
the metrics row picks up ``avg_sentiment_score`` / ``dominant_sentiment`` /
``sentiment_trend``.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any
from uuid import UUID

from bubbles.ai.extraction import score_turn_sentiments
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.db.uow import UnitOfWork
from bubbles.workers.enqueue import enqueue_session_analytics

if TYPE_CHECKING:
    from bubbles.workers.arq_settings import WorkerCtx

log = get_logger(__name__)

_BATCH = 25  # turns per LLM call


async def run(ctx: dict[str, Any], *, user_id: str, session_id: str) -> dict[str, int]:
    bub: WorkerCtx = ctx["bubbles"]
    sess_uuid = UUID(session_id)

    async with bub.pool.acquire() as con:
        pending = await session_logs_repo.unscored_turns(con, session_id=sess_uuid, limit=400)
    if not pending:
        return {"scored": 0}

    scored = 0
    for start in range(0, len(pending), _BATCH):
        batch = [
            {"turn_index": r["turn_index"], "role": r["role"], "content": r["content"]}
            for r in pending[start : start + _BATCH]
        ]
        try:
            scores = await score_turn_sentiments(bub.ai.router, batch)
        except UpstreamUnavailable as exc:
            log.warning("sentiment_scan_upstream", session=session_id, error=str(exc))
            break
        if not scores:
            continue
        async with UnitOfWork(bub.pool) as uow:
            scored += await session_logs_repo.update_sentiments(
                uow.conn, session_id=sess_uuid, scores=scores
            )

    if scored:
        redis = ctx.get("redis")
        if redis is not None:
            async with bub.pool.acquire() as con:
                transcript = await session_logs_repo.assemble_transcript(con, session_id=sess_uuid)
            await enqueue_session_analytics(
                redis,
                user_id=user_id,
                session_id=session_id,
                transcript=transcript,
                job_suffix="post_sentiment",
            )
    log.info("sentiment_scan_done", session=session_id, scored=scored)
    return {"scored": scored}
