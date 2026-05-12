"""Real-time wingman advice loop (``process_transcript_wingman``).

Per turn: persist the incoming turn, and — for a turn from the *other* party —
build a small amount of context (recent memories + known entities, hard
time-capped), ask the wingman model for one short piece of advice, return it,
and persist the advice + queue follow-up work (knowledge extraction, memory
embeddings) in the background.

A ``user``-role turn is the fast path: persist it and return ``WAITING`` (the
client only wants advice on what the *other* side said), matching ``server_v2``.
"""

from __future__ import annotations

import asyncio
from collections.abc import Coroutine
from time import perf_counter
from typing import TYPE_CHECKING, Any
from uuid import UUID

from arq.connections import ArqRedis
from fastapi import APIRouter, Request

from bubbles.ai.prompts.loader import render
from bubbles.ai.providers.base import ChatMessage, Role
from bubbles.api.v1._schemas import WingmanTurnRequest, WingmanTurnResponse
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import NotFound
from bubbles.core.logging import get_logger
from bubbles.db.repo import entities as entities_repo
from bubbles.db.repo import memories as memories_repo
from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.db.repo import sessions as sessions_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import ArqDep, EmbeddingsDep, PoolDep, RouterDep
from bubbles.workers.enqueue import enqueue_compute_embeddings, enqueue_extract_knowledge

if TYPE_CHECKING:
    import asyncpg

    from bubbles.ai.embeddings import EmbeddingService
    from bubbles.core.concurrency import FireAndForget

log = get_logger(__name__)
router = APIRouter(tags=["wingman"])

_CONTEXT_BUDGET_S = 0.5
_EXTRACT_EVERY_N_TURNS = 5


async def _build_context(
    pool: asyncpg.Pool, embeddings: EmbeddingService, *, user_id: UUID, text: str
) -> tuple[str, str]:
    """(memory_context, entity_context) — best effort, hard-capped, never raises."""
    try:
        return await asyncio.wait_for(
            _gather_context(pool, embeddings, user_id=user_id, text=text),
            timeout=_CONTEXT_BUDGET_S,
        )
    except Exception as exc:
        log.info("wingman_context_skipped", error=str(exc))
        return "", ""


async def _gather_context(
    pool: asyncpg.Pool, embeddings: EmbeddingService, *, user_id: UUID, text: str
) -> tuple[str, str]:
    async with transaction(pool) as conn:
        try:
            vec = await embeddings.embed(text)
            mems = await memories_repo.similar(conn, user_id=user_id, query_vector=vec, limit=5)
        except Exception:
            mems = await memories_repo.list_for_user(conn, user_id=user_id, limit=5)
        ents = await entities_repo.list_for_user(conn, user_id=user_id, limit=8)
    mem_ctx = "\n".join(f"- {m.content.strip()}" for m in mems if m.content.strip())
    ent_ctx = "\n".join(f"- {e.display_name or e.canonical_name} ({e.entity_type})" for e in ents)
    return mem_ctx, ent_ctx


def _advice_messages(
    transcript: str, *, mode: str, persona: str, memory_ctx: str, entity_ctx: str
) -> list[ChatMessage]:
    system = render(
        "wingman/advice.jinja",
        mode=mode,
        persona_hint=persona or "",
        memory_context=memory_ctx,
        entity_context=entity_ctx,
    )
    return [
        ChatMessage(role=Role.system, content=system),
        ChatMessage(role=Role.user, content=transcript),
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
        if arq is not None:
            if n % _EXTRACT_EVERY_N_TURNS == 0 and transcript:
                await enqueue_extract_knowledge(
                    arq, user_id=str(user_id), session_id=str(session_id), transcript=transcript
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

    memory_ctx, entity_ctx = await _build_context(
        pool, embeddings, user_id=user_id, text=body.transcript
    )
    messages = _advice_messages(
        body.transcript,
        mode=body.mode,
        persona=body.persona,
        memory_ctx=memory_ctx,
        entity_ctx=entity_ctx,
    )
    t0 = perf_counter()
    completion = await llm_router.complete("wingman.advice", messages)
    latency_ms = int((perf_counter() - t0) * 1000)
    provider = completion.raw.get("model", "") if isinstance(completion.raw, dict) else ""
    advice_text = completion.text.strip() or "WAITING"

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
