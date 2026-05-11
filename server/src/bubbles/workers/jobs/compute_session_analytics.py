"""Generate post-session analytics: title, summary, highlights."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any
from uuid import UUID

from bubbles.ai.extraction import (
    extract_highlights,
    generate_summary,
    generate_title,
)
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
    session_id: str,
    transcript: str,
) -> dict[str, Any]:
    bub: WorkerCtx = ctx["bubbles"]
    sess_uuid = UUID(session_id)
    user_uuid = UUID(user_id)

    title = ""
    summary = ""
    highlights: list[dict[str, Any]] = []

    try:
        title = await generate_title(bub.ai.router, transcript)
    except UpstreamUnavailable as exc:
        log.warning("title_upstream", error=str(exc))
    try:
        summary = await generate_summary(bub.ai.router, transcript)
    except UpstreamUnavailable as exc:
        log.warning("summary_upstream", error=str(exc))
    try:
        h_payload = await extract_highlights(bub.ai.router, transcript)
        h_raw = h_payload.get("highlights") or []
        highlights = [h for h in h_raw if isinstance(h, dict)][:5]
    except UpstreamUnavailable as exc:
        log.warning("highlights_upstream", error=str(exc))

    async with UnitOfWork(bub.pool) as uow:
        await uow.conn.execute(
            """
            UPDATE sessions
            SET title = COALESCE(NULLIF($2, ''), title),
                summary = COALESCE(NULLIF($3, ''), summary)
            WHERE id = $1 AND user_id = $4
            """,
            sess_uuid,
            title,
            summary,
            user_uuid,
        )
        for h in highlights:
            content = (h.get("body") or h.get("title") or "").strip()
            if not content:
                continue
            await uow.conn.execute(
                """
                INSERT INTO highlights
                    (user_id, session_id, highlight_type, title, body, content)
                VALUES ($1, $2, $3, $4, $5, $6)
                """,
                user_uuid,
                sess_uuid,
                str(h.get("type") or "insight"),
                str(h.get("title") or "")[:120] or None,
                str(h.get("body") or "")[:600] or None,
                content[:2000],
            )

    log.info(
        "session_analytics_done",
        session=session_id,
        title_set=bool(title),
        summary_set=bool(summary),
        highlights=len(highlights),
    )
    return {"title": title, "summary": summary, "highlights": len(highlights)}
