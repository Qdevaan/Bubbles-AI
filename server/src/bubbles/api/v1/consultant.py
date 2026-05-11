"""Consultant routes — streaming SSE by default, JSON when ``stream=false``."""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import APIRouter, Query
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
from bubbles.deps import RouterDep

router = APIRouter(tags=["consultant"])

log = get_logger(__name__)


def _build_messages(question: str, persona: str | None) -> list[ChatMessage]:
    system = render("consultant/system.jinja", persona_block="", scenario_header="")
    if persona:
        system = system + f"\n\nPersona hint: {persona}"
    return [
        ChatMessage(role=Role.system, content=system),
        ChatMessage(role=Role.user, content=question),
    ]


@router.post("/ask_consultant", response_model=None)
async def ask_consultant(
    body: ConsultantRequest,
    user: CurrentUserDep,
    llm_router: RouterDep,
    stream: Annotated[bool, Query()] = True,
) -> StreamingResponse | ConsultantAnswer:
    messages = _build_messages(body.question, body.persona)
    log.info("consultant_ask", user=user.id, stream=stream)

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
    user: CurrentUserDep,
    llm_router: RouterDep,
) -> ConsultantAnswer:
    """Legacy alias used by older clients."""
    messages = _build_messages(body.question, body.persona)
    log.info("consultant_ask_alias", user=user.id)
    completion = await llm_router.complete("consultant.complete", messages)
    return ConsultantAnswer(
        answer=completion.text,
        provider=str((completion.raw or {}).get("model", "")),
        fallback_depth=llm_router.last_fallback_depth,
    )


@router.post("/ask_consultant/batch", response_model=ConsultantBatchAnswer)
async def ask_consultant_batch(
    body: ConsultantBatchRequest,
    user: CurrentUserDep,
    llm_router: RouterDep,
) -> ConsultantBatchAnswer:
    log.info("consultant_batch", user=user.id, n=len(body.questions))

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
