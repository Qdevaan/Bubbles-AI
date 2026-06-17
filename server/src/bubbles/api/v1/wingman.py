# Purpose: Wingman live coaching endpoints: accepts real-time transcript turns and streams AI suggestions.
"""Real-time wingman advice loop (``process_transcript_wingman``).

Per turn: persist the incoming turn, and — for a turn from the *other* party —
build a small amount of context (recent memories + known entities + walked
graph relations + persona + per-meeting scenario, hard time-capped), ask the
wingman model for one short piece of advice, return it, and persist the
advice + queue follow-up work (knowledge extraction, memory embeddings,
rolling summarisation) in the background.

A ``user``-role turn is the fast path: persist it and return ``WAITING`` (the
client only wants advice on what the *other* side said), matching ``server_v2``.

Roleplay mode (``mode == "roleplay"``): when ``target_entity_id`` is set, the
prompt switches to first-person embodiment of that entity (legacy parity).
"""

from __future__ import annotations

from collections.abc import Coroutine
from time import perf_counter
from typing import TYPE_CHECKING, Any
from uuid import UUID

from arq.connections import ArqRedis
from fastapi import APIRouter, Request

from bubbles.ai import wingman_context
from bubbles.ai.prompts.loader import render
from bubbles.ai.providers.base import ChatMessage, Role
from bubbles.ai.sanitize import sanitize_ai_disclaimer
from bubbles.api.v1._schemas import WingmanTurnRequest, WingmanTurnResponse
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import NotFound
from bubbles.core.logging import get_logger
from bubbles.db.repo import gamification as gamification_repo
from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.db.repo import sessions as sessions_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import ArqDep, EmbeddingsDep, PoolDep, RouterDep
from bubbles.workers.enqueue import (
    enqueue_compute_embeddings,
    enqueue_extract_knowledge,
    enqueue_rolling_summarize,
)

if TYPE_CHECKING:
    import asyncpg

    from bubbles.core.concurrency import FireAndForget

log = get_logger(__name__)
router = APIRouter(tags=["wingman"])

_EXTRACT_EVERY_N_TURNS = 5
_ROLLING_SUMMARY_EVERY_N_TURNS = 20


def _advice_messages(
    transcript: str,
    *,
    mode: str,
    persona_hint: str,
    ctx: wingman_context.WingmanContext,
) -> list[ChatMessage]:
    system = render(
        "wingman/advice.jinja",
        mode=mode,
        is_roleplay=ctx.is_roleplay,
        persona_hint=persona_hint or "",
        persona_block=ctx.persona_block,
        scenario_block=ctx.scenario_block,
        entity_block=ctx.entity_block,
        memory_context=ctx.memory_context,
        entity_context=ctx.entity_context,
        graph_facts=ctx.graph_facts,
    )
    user_prompt = (
        transcript
        if ctx.is_roleplay
        else f"The other person just said: {transcript}"
    )
    return [
        ChatMessage(role=Role.system, content=system),
        ChatMessage(role=Role.user, content=user_prompt),
    ]


async def _persist_advice_and_followups(
    pool: asyncpg.Pool,
    arq: ArqRedis | None,
    *,
    session_id: UUID,
    user_id: UUID,
    advice_text: str,
    provider: str,
    latency_ms: int,
    tokens_used: int,
    finish_reason: str | None,
) -> None:
    try:
        async with UnitOfWork(pool) as uow:
            await session_logs_repo.append(
                uow.conn,
                session_id=session_id,
                role="llm",
                content=advice_text,
                model_used=provider or None,
                latency_ms=latency_ms,
                tokens_used=tokens_used or None,
                finish_reason=finish_reason,
            )
            n = await session_logs_repo.turn_count(uow.conn, session_id=session_id)
            transcript = await session_logs_repo.assemble_transcript(
                uow.conn, session_id=session_id, last_n=40
            )
            # Small per-turn XP (daily-capped) + nudge the "use wingman turns" quest.
            await gamification_repo.add_xp(
                uow.conn,
                user_id=user_id,
                amount=2,
                source_type="wingman_turn",
                source_id=f"wt_{session_id}_{n}",
                description="Wingman advice turn",
            )
            await gamification_repo.bump_quest_progress_by_action(
                uow.conn, user_id=user_id, action_type="use_wingman_turns", delta=1
            )
        if arq is not None:
            if n % _EXTRACT_EVERY_N_TURNS == 0 and transcript:
                await enqueue_extract_knowledge(
                    arq, user_id=str(user_id), session_id=str(session_id), transcript=transcript
                )
            if n > 0 and n % _ROLLING_SUMMARY_EVERY_N_TURNS == 0:
                await enqueue_rolling_summarize(
                    arq, user_id=str(user_id), session_id=str(session_id), turn_index=n
                )
            await enqueue_compute_embeddings(arq, user_id=str(user_id))
    except Exception as exc:
        log.warning("wingman_followup_failed", error=str(exc), session_id=str(session_id))


async def _run_bg(bg: FireAndForget | None, coro: Coroutine[Any, Any, None]) -> None:
    """Hand work to the app's background runner; run inline if there isn't one."""
    if bg is not None:
        bg.spawn(coro)
    else:
        await coro


@router.post("/process_transcript_wingman", response_model=WingmanTurnResponse)
async def process_transcript_wingman(
    body: WingmanTurnRequest,
    request: Request,
    user: CurrentUserDep,
    pool: PoolDep,
    arq: ArqDep,
    llm_router: RouterDep,
    embeddings: EmbeddingsDep,
) -> WingmanTurnResponse:
    user_id = UUID(user.id)
    bg: FireAndForget | None = getattr(request.app.state, "bg", None)

    session_id: UUID | None = body.session_id
    if session_id is not None:
        async with transaction(pool) as conn:
            sess = await sessions_repo.get(conn, session_id)
        if sess is None:
            raise NotFound("session not found")
        require_ownership(user, str(sess.user_id))

    # Persist the incoming turn (synchronous — one fast insert, gives us the index).
    turn_index: int | None = None
    if session_id is not None:
        async with UnitOfWork(pool) as uow:
            log_row = await session_logs_repo.append(
                uow.conn,
                session_id=session_id,
                role=body.speaker_role,
                content=body.transcript,
                speaker_label=body.speaker_label,
                confidence=body.confidence,
            )
        turn_index = log_row.turn_index

    # Fast path: a user turn just gets stored; advice is only for the other side.
    if body.speaker_role == "user":
        if arq is not None:
            try:
                await enqueue_compute_embeddings(arq, user_id=str(user_id))
            except Exception as exc:
                log.warning("wingman_embed_enqueue_failed", error=str(exc))
        return WingmanTurnResponse(advice="WAITING", provider="", turn_index=turn_index)

    ctx = await wingman_context.build(
        pool,
        embeddings,
        user_id=user_id,
        transcript=body.transcript,
        session_id=session_id,
        mode=body.mode,
        target_entity_id=body.target_entity_id,
    )
    messages = _advice_messages(
        body.transcript,
        mode=body.mode,
        persona_hint=body.persona,
        ctx=ctx,
    )
    t0 = perf_counter()
    completion = await llm_router.complete("wingman.advice", messages)
    latency_ms = int((perf_counter() - t0) * 1000)
    provider = completion.raw.get("model", "") if isinstance(completion.raw, dict) else ""
    advice_text = completion.text.strip() or "WAITING"
    advice_text = sanitize_ai_disclaimer(advice_text, is_roleplay=ctx.is_roleplay)

    if session_id is not None and advice_text != "WAITING":
        await _run_bg(
            bg,
            _persist_advice_and_followups(
                pool,
                arq,
                session_id=session_id,
                user_id=user_id,
                advice_text=advice_text,
                provider=str(provider),
                latency_ms=latency_ms,
                tokens_used=completion.usage.total_tokens,
                finish_reason=completion.finish_reason,
            ),
        )

    return WingmanTurnResponse(advice=advice_text, provider=str(provider), turn_index=turn_index)
