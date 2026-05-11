"""Embed memories that have content but no vector yet."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any
from uuid import UUID

from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.db.uow import UnitOfWork

if TYPE_CHECKING:
    from bubbles.workers.arq_settings import WorkerCtx

log = get_logger(__name__)


async def run(
    ctx: dict[str, Any],
    *,
    user_id: str,
    limit: int = 50,
) -> int:
    bub: WorkerCtx = ctx["bubbles"]
    user_uuid = UUID(user_id)
    embedded = 0
    async with UnitOfWork(bub.pool) as uow:
        rows = await uow.conn.fetch(
            """
            SELECT id, content
            FROM memory
            WHERE user_id = $1
              AND embedding IS NULL
              AND is_archived = false
            ORDER BY created_at DESC
            LIMIT $2
            """,
            user_uuid,
            limit,
        )
        for row in rows:
            try:
                vec = await bub.ai.embeddings.embed(row["content"])
            except (UpstreamUnavailable, ValueError) as exc:
                log.warning("embed_skip", id=str(row["id"]), error=str(exc))
                continue
            formatted = "[" + ",".join(f"{v:.6f}" for v in vec) + "]"
            await uow.conn.execute(
                "UPDATE memory SET embedding = $2::vector WHERE id = $1",
                row["id"],
                formatted,
            )
            embedded += 1
    log.info("compute_embeddings_done", user=user_id, embedded=embedded)
    return embedded
