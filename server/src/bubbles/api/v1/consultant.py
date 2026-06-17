# Purpose: Consultant chat endpoints: starts a Q&A session and streams AI responses via SSE.
"""Consultant routes — streaming SSE by default, JSON when ``stream=false``."""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import TYPE_CHECKING, Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Request
from fastapi.responses import StreamingResponse

from bubbles.ai.prompts.loader import render
from bubbles.ai.providers.base import ChatMessage, Role
from bubbles.ai.streaming import sse_from_chunks
from bubbles.api.v1._schemas import (
    ConsultantAnswer,
    ConsultantBatchAnswer,
    ConsultantBatchRequest,
    ConsultantRequest,
)
from bubbles.auth.current_user import CurrentUserDep
from bubbles.core.concurrency import gather_bounded
from bubbles.core.logging import get_logger
from bubbles.db.repo import gamification as gamification_repo
from bubbles.db.uow import UnitOfWork
from bubbles.deps import RouterDep

if TYPE_CHECKING:
    import asyncpg

    from bubbles.core.concurrency import FireAndForget

router = APIRouter(tags=["consultant"])

log = get_logger(__name__)

# Quest actions a consultant Q&A advances (v2 parity: it counted both).
_CONSULTANT_QUEST_ACTIONS = ("ask_consultant", "save_memory")


def _build_messages(question: str, persona: str | None) -> list[ChatMessage]:
    system = render("consultant/system.jinja", persona_block="", scenario_header="")
    if persona:
        system = system + f"\n\nPersona hint: {persona}"
    return [
        ChatMessage(role=Role.system, content=system),
        ChatMessage(role=Role.user, content=question),
    ]


async def _bump_consultant_quests(pool: asyncpg.Pool, *, user_id: UUID, n: int = 1) -> None:
    """Best-effort: nudge consultant-related daily quests after a Q&A."""
    try:
        async with UnitOfWork(pool) as uow:
            for action in _CONSULTANT_QUEST_ACTIONS:
                await gamification_repo.bump_quest_progress_by_action(
                    uow.conn, user_id=user_id, action_type=action, delta=n
                )
    except Exception as exc:  # never let quest bookkeeping break the answer
        log.warning("consultant_quest_bump_failed", error=str(exc), user_id=str(user_id))


async def _maybe_bump_quests(request: Request, *, user_id: UUID, n: int = 1) -> None:
    """Fire the consultant quest nudge if the DB pool is up; best-effort, never raises."""
    pool: asyncpg.Pool | None = getattr(request.app.state, "db", None)
    if pool is None:
        return
    bg: FireAndForget | None = getattr(request.app.state, "bg", None)
    coro = _bump_consultant_quests(pool, user_id=user_id, n=n)
    if bg is not None:
        bg.spawn(coro)
    else:  # no background runner — run it inline (it's two quick UPDATEs)
        await coro


@router.post("/ask_consultant", response_model=None)
async def ask_consultant(
    body: ConsultantRequest,
    request: Request,
    user: CurrentUserDep,
    llm_router: RouterDep,
    stream: Annotated[bool, Query()] = True,
) -> StreamingResponse | ConsultantAnswer:
    messages = _build_messages(body.question, body.persona)
    log.info("consultant_ask", user=user.id, stream=stream)
    await _maybe_bump_quests(request, user_id=UUID(user.id))

    if not stream:
        completion = await llm_router.complete("consultant.complete", messages)
        return ConsultantAnswer(
            answer=completion.text,
            provider=str((completion.raw or {}).get("model", "")),
            fallback_depth=llm_router.last_fallback_depth,
        )

    async def event_source() -> AsyncIterator[bytes]:
        chunks = llm_router.stream("consultant.stream", messages)
        async for piece in sse_from_chunks(chunks):
            yield piece

    return StreamingResponse(
        event_source(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@router.post("/ask", response_model=ConsultantAnswer)
async def ask_alias(
    body: ConsultantRequest,
    request: Request,
    user: CurrentUserDep,
    llm_router: RouterDep,
) -> ConsultantAnswer:
    """Legacy alias used by older clients."""
    messages = _build_messages(body.question, body.persona)
    log.info("consultant_ask_alias", user=user.id)
    await _maybe_bump_quests(request, user_id=UUID(user.id))
    completion = await llm_router.complete("consultant.complete", messages)
    return ConsultantAnswer(
        answer=completion.text,
        provider=str((completion.raw or {}).get("model", "")),
        fallback_depth=llm_router.last_fallback_depth,
    )


@router.post("/ask_consultant/batch", response_model=ConsultantBatchAnswer)
async def ask_consultant_batch(
    body: ConsultantBatchRequest,
    request: Request,
    user: CurrentUserDep,
    llm_router: RouterDep,
) -> ConsultantBatchAnswer:
    log.info("consultant_batch", user=user.id, n=len(body.questions))
    await _maybe_bump_quests(request, user_id=UUID(user.id), n=len(body.questions))

    async def _one(question: str) -> ConsultantAnswer:
        messages = _build_messages(question, persona=None)
        completion = await llm_router.complete("consultant.complete", messages)
        return ConsultantAnswer(
            answer=completion.text,
            provider=str((completion.raw or {}).get("model", "")),
            fallback_depth=llm_router.last_fallback_depth,
        )

    answers = await gather_bounded((_one(q) for q in body.questions), limit=4)
    return ConsultantBatchAnswer(answers=answers)
