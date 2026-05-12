"""Post-session analytics: title, summary, highlights, metrics row, coaching report."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any
from uuid import UUID

from bubbles.ai.extraction import (
    extract_highlights,
    generate_coaching_report,
    generate_summary,
    generate_title,
    prepare_transcript,
)
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.core.transcript import parse_transcript
from bubbles.db.repo import analytics as analytics_repo
from bubbles.db.uow import UnitOfWork

if TYPE_CHECKING:
    from bubbles.workers.arq_settings import WorkerCtx

log = get_logger(__name__)

_TONE_KEYS = (
    "tone_aggression",
    "tone_empathy",
    "tone_analytical",
    "tone_confidence",
    "tone_clarity",
)


def _as_float(value: Any) -> float | None:
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def _as_str(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _as_str_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(v).strip() for v in value if str(v).strip()][:5]


def _as_int(value: Any) -> int:
    try:
        return int(value) if value is not None else 0
    except (TypeError, ValueError):
        return 0


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
    coaching: dict[str, Any] | None = None

    # Metrics use the raw transcript (accurate turn/word counts); the LLM
    # prompts use a budget-fitted version (whole conversation, condensed if long).
    stats = parse_transcript(transcript)
    try:
        prepared = await prepare_transcript(bub.ai.router, transcript)
    except UpstreamUnavailable as exc:
        log.warning("transcript_prepare_upstream", error=str(exc))
        prepared = transcript

    try:
        title = await generate_title(bub.ai.router, prepared)
    except UpstreamUnavailable as exc:
        log.warning("title_upstream", error=str(exc))
    try:
        summary = await generate_summary(bub.ai.router, prepared)
    except UpstreamUnavailable as exc:
        log.warning("summary_upstream", error=str(exc))
    try:
        h_payload = await extract_highlights(bub.ai.router, prepared)
        h_raw = h_payload.get("highlights") or []
        highlights = [h for h in h_raw if isinstance(h, dict)][:5]
    except UpstreamUnavailable as exc:
        log.warning("highlights_upstream", error=str(exc))
    try:
        coaching = await generate_coaching_report(bub.ai.router, prepared)
    except UpstreamUnavailable as exc:
        log.warning("coaching_upstream", error=str(exc))

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

        sess_row = await uow.conn.fetchrow(
            "SELECT start_time, ended_at, end_time FROM sessions WHERE id = $1", sess_uuid
        )
        duration: float | None = None
        if sess_row is not None and sess_row["start_time"] is not None:
            end_ts = sess_row["ended_at"] or sess_row["end_time"]
            if end_ts is not None:
                duration = max(0.0, (end_ts - sess_row["start_time"]).total_seconds())
        memories_saved = (
            await uow.conn.fetchval("SELECT count(*) FROM memory WHERE session_id = $1", sess_uuid)
            or 0
        )
        events_extracted = (
            await uow.conn.fetchval("SELECT count(*) FROM events WHERE session_id = $1", sess_uuid)
            or 0
        )
        await analytics_repo.upsert_session_analytics(
            uow.conn,
            session_id=sess_uuid,
            user_id=user_uuid,
            total_turns=stats.total_turns,
            user_turns=stats.user_turns,
            others_turns=stats.others_turns,
            llm_turns=stats.llm_turns,
            user_word_count=stats.user_words,
            assistant_word_count=stats.assistant_words,
            total_duration_seconds=duration,
            memories_saved=int(memories_saved),
            events_extracted=int(events_extracted),
            highlights_created=len(highlights),
            topic_summary=summary or None,
        )

        if coaching is not None:
            report_content = {
                k: _as_int(coaching.get(k)) for k in _TONE_KEYS if coaching.get(k) is not None
            }
            await analytics_repo.upsert_coaching_report(
                uow.conn,
                session_id=sess_uuid,
                user_id=user_uuid,
                model_used="analytics.coaching",
                user_talk_pct=_as_float(coaching.get("user_talk_pct")),
                others_talk_pct=_as_float(coaching.get("others_talk_pct")),
                key_topics=_as_str_list(coaching.get("key_topics")),
                key_decisions=_as_str_list(coaching.get("key_decisions")),
                action_items=_as_str_list(coaching.get("action_items")),
                follow_up_people=_as_str_list(coaching.get("follow_up_people")),
                filler_words=_as_str_list(coaching.get("filler_words")),
                filler_word_count=_as_int(coaching.get("filler_word_count")),
                tone_summary=_as_str(coaching.get("tone_summary")),
                engagement_trend=_as_str(coaching.get("engagement_trend")),
                suggestions=_as_str_list(coaching.get("suggestions")),
                strengths=_as_str_list(coaching.get("strengths")),
                areas_of_improvement=_as_str_list(coaching.get("areas_of_improvement")),
                report_text=_as_str(coaching.get("report_text")),
                report_content=report_content,
            )

    log.info(
        "session_analytics_done",
        session=session_id,
        title_set=bool(title),
        summary_set=bool(summary),
        highlights=len(highlights),
        coaching=coaching is not None,
        turns=stats.total_turns,
    )
    return {
        "title": title,
        "summary": summary,
        "highlights": len(highlights),
        "coaching": coaching is not None,
        "turns": stats.total_turns,
    }
