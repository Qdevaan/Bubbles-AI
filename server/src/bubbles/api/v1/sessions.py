"""Session lifecycle routes."""

from __future__ import annotations

from uuid import UUID

from arq.connections import ArqRedis
from fastapi import APIRouter, Response, status

from bubbles.api.v1._schemas import (
    EndSessionRequest,
    LogTurnRequest,
    SaveSessionRequest,
    SessionContextRequest,
    SessionOut,
    SessionReplayResponse,
    StartSessionRequest,
    SuggestReplyRequest,
    SuggestReplyResponse,
    TurnOut,
)
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import NotFound
from bubbles.core.logging import get_logger
from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.db.repo import sessions as sessions_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import ArqDep, PoolDep, RouterDep
from bubbles.workers.enqueue import (
    enqueue_compute_embeddings,
    enqueue_extract_knowledge,
    enqueue_session_analytics,
)

log = get_logger(__name__)
router = APIRouter(tags=["sessions"])


async def _enqueue_post_session_jobs(
    arq: ArqRedis, *, user_id: str, session_id: str, transcript: str
) -> None:
    """Best-effort: a queue hiccup must not fail the ``end_session`` write."""
    try:
        await enqueue_session_analytics(
            arq, user_id=user_id, session_id=session_id, transcript=transcript
        )
        await enqueue_extract_knowledge(
            arq, user_id=user_id, session_id=session_id, transcript=transcript
        )
        await enqueue_compute_embeddings(arq, user_id=user_id)
    except Exception as exc:
        log.warning("post_session_enqueue_failed", error=str(exc), session_id=session_id)


def _to_out(s: object) -> SessionOut:
    # Narrow type to the repo's Session dataclass without coupling the schema
    # module to the DB layer.
    return SessionOut.model_validate(s, from_attributes=True)


@router.post("/start_session", response_model=SessionOut, status_code=status.HTTP_201_CREATED)
async def start_session(
    body: StartSessionRequest,
    user: CurrentUserDep,
    pool: PoolDep,
) -> SessionOut:
    async with UnitOfWork(pool) as uow:
        sess = await sessions_repo.start(
            uow.conn,
            user_id=UUID(user.id),
            title=body.title,
            session_type=body.session_type,
            mode=body.mode,
            persona=body.persona,
            is_ephemeral=body.is_ephemeral,
            idempotency_key=body.idempotency_key,
            session_context=body.session_context,
        )
    return _to_out(sess)


@router.post("/save_session", response_model=SessionOut)
async def save_session(
    body: SaveSessionRequest,
    user: CurrentUserDep,
    pool: PoolDep,
) -> SessionOut:
    async with transaction(pool) as conn:
        sess = await sessions_repo.get(conn, body.session_id)
    if sess is None:
        raise NotFound("session not found")
    require_ownership(user, str(sess.user_id))
    return _to_out(sess)


@router.post("/end_session", response_model=SessionOut)
async def end_session(
    body: EndSessionRequest,
    user: CurrentUserDep,
    pool: PoolDep,
    arq: ArqDep,
) -> SessionOut:
    async with transaction(pool) as conn:
        existing = await sessions_repo.get(conn, body.session_id)
    if existing is None:
        raise NotFound("session not found")
    require_ownership(user, str(existing.user_id))
    async with UnitOfWork(pool) as uow:
        ended = await sessions_repo.end(uow.conn, session_id=body.session_id, summary=body.summary)
    if ended is None:
        raise NotFound("session not found")
    # Stored turns are authoritative; fall back to a client-supplied transcript.
    async with transaction(pool) as conn:
        row_transcript = await session_logs_repo.assemble_transcript(
            conn, session_id=body.session_id
        )
    transcript = row_transcript or (body.transcript or "")
    if arq is not None and transcript:
        await _enqueue_post_session_jobs(
            arq,
            user_id=str(existing.user_id),
            session_id=str(body.session_id),
            transcript=transcript,
        )
    return _to_out(ended)


@router.post("/log_turn", response_model=TurnOut, status_code=status.HTTP_201_CREATED)
async def log_turn(
    body: LogTurnRequest,
    user: CurrentUserDep,
    pool: PoolDep,
) -> TurnOut:
    async with transaction(pool) as conn:
        sess = await sessions_repo.get(conn, body.session_id)
    if sess is None:
        raise NotFound("session not found")
    require_ownership(user, str(sess.user_id))
    async with UnitOfWork(pool) as uow:
        log = await session_logs_repo.append(
            uow.conn,
            session_id=body.session_id,
            role=body.role,
            content=body.content,
            speaker_label=body.speaker_label,
            confidence=body.confidence,
        )
    return TurnOut.model_validate(session_logs_repo.to_out_dict(log))


@router.get("/session_replay/{session_id}", response_model=SessionReplayResponse)
async def session_replay(
    session_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
    limit: int = 500,
    offset: int = 0,
) -> SessionReplayResponse:
    async with transaction(pool) as conn:
        sess = await sessions_repo.get(conn, session_id)
        if sess is None:
            raise NotFound("session not found")
        require_ownership(user, str(sess.user_id))
        logs = await session_logs_repo.list_for_session(
            conn, session_id=session_id, limit=min(max(limit, 1), 1000), offset=max(offset, 0)
        )
    return SessionReplayResponse(
        session_id=session_id,
        turns=[TurnOut.model_validate(session_logs_repo.to_out_dict(log)) for log in logs],
    )


@router.post("/sessions/{session_id}/context", response_model=SessionOut)
async def post_session_context(
    session_id: UUID,
    body: SessionContextRequest,
    user: CurrentUserDep,
    pool: PoolDep,
) -> SessionOut:
    async with transaction(pool) as conn:
        sess = await sessions_repo.get(conn, session_id)
    if sess is None:
        raise NotFound("session not found")
    require_ownership(user, str(sess.user_id))
    async with UnitOfWork(pool) as uow:
        await uow.conn.execute(
            "UPDATE sessions SET session_context = $2 WHERE id = $1",
            session_id,
            body.context,
        )
        updated = await sessions_repo.get(uow.conn, session_id)
    assert updated is not None
    return _to_out(updated)


@router.post("/suggest_reply", response_model=SuggestReplyResponse)
async def suggest_reply(
    body: SuggestReplyRequest,
    user: CurrentUserDep,
    pool: PoolDep,
    llm_router: RouterDep,
) -> SuggestReplyResponse:
    async with transaction(pool) as conn:
        sess = await sessions_repo.get(conn, body.session_id)
    if sess is None:
        raise NotFound("session not found")
    require_ownership(user, str(sess.user_id))

    from bubbles.ai.providers.base import ChatMessage, Role

    completion = await llm_router.complete(
        "wingman.short",
        [
            ChatMessage(
                role=Role.system,
                content="Suggest one short empathetic reply (one sentence).",
            ),
            ChatMessage(role=Role.user, content=body.last_user_text),
        ],
    )
    provider = completion.raw.get("model", "") if isinstance(completion.raw, dict) else ""
    return SuggestReplyResponse(suggestion=completion.text.strip(), provider=str(provider))


@router.delete("/sessions/{session_id}", status_code=204, response_class=Response)
async def delete_session(
    session_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> Response:
    async with transaction(pool) as conn:
        sess = await sessions_repo.get(conn, session_id)
    if sess is None:
        raise NotFound("session not found")
    require_ownership(user, str(sess.user_id))
    async with UnitOfWork(pool) as uow:
        ok = await sessions_repo.soft_delete(uow.conn, session_id=session_id, user_id=UUID(user.id))
    if not ok:
        raise NotFound("session not found")
    return Response(status_code=204)
