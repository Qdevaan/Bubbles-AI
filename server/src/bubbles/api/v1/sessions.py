"""Session lifecycle routes."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from arq.connections import ArqRedis
from fastapi import APIRouter, Response, status

from bubbles.api.v1._schemas import (
    EndSessionRequest,
    LogTurnRequest,
    SaveSessionRequest,
    SaveSessionResponse,
    SessionContextRequest,
    SessionOut,
    SessionReplayResponse,
    SetTurnConfidenceRequest,
    SetTurnConfidenceResponse,
    StartSessionRequest,
    SuggestReplyRequest,
    SuggestReplyResponse,
    TurnOut,
)
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import NotFound, RateLimited
from bubbles.core.logging import get_logger
from bubbles.db.repo import gamification as gamification_repo
from bubbles.db.repo import scenarios as scenarios_repo
from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.db.repo import sessions as sessions_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import ArqDep, EmbeddingsDep, PoolDep, RateLimiterDep, RouterDep
from bubbles.workers.enqueue import (
    enqueue_compute_embeddings,
    enqueue_detect_achievements,
    enqueue_extract_knowledge,
    enqueue_generate_scenarios,
    enqueue_materialize_drill_cards,
    enqueue_score_scenario,
    enqueue_sentiment_scan,
    enqueue_session_analytics,
)

log = get_logger(__name__)
router = APIRouter(tags=["sessions"])


async def _enqueue_post_session_jobs(
    arq: ArqRedis,
    *,
    user_id: str,
    session_id: str,
    transcript: str,
    scenario_id: str | None = None,
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
        await enqueue_detect_achievements(arq, user_id=user_id)
        # Score per-turn sentiment, then it re-runs compute_session_analytics so
        # the metrics row picks up avg_sentiment_score / dominant_sentiment.
        await enqueue_sentiment_scan(arq, user_id=user_id, session_id=session_id)
        # Top up the user's personalized roleplay scenario feed.
        await enqueue_generate_scenarios(arq, user_id=user_id)
        # Turn this session's grammar mistakes into spaced-repetition drill cards.
        await enqueue_materialize_drill_cards(arq, user_id=user_id, session_id=session_id)
        # If this session was a roleplay started from a scenario, grade it.
        if scenario_id is not None:
            await enqueue_score_scenario(arq, scenario_id=scenario_id)
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
            is_multiplayer=body.is_multiplayer,
            idempotency_key=body.idempotency_key,
            session_context=body.session_context,
        )
    # Daily streak ticks on first activity of the day. Separate transaction so a
    # streak hiccup can't roll back (or block) the session create.
    try:
        async with UnitOfWork(pool) as uow2:
            await gamification_repo.update_streak(uow2.conn, user_id=UUID(user.id))
    except Exception as exc:
        log.warning("update_streak_failed", error=str(exc), user_id=user.id)
    return _to_out(sess)


@router.post("/save_session", response_model=SaveSessionResponse)
async def save_session(
    body: SaveSessionRequest,
    user: CurrentUserDep,
    pool: PoolDep,
    arq: ArqDep,
) -> SaveSessionResponse:
    """Batch-upload a completed conversation in one shot (legacy/Flutter path).

    Attaches ``logs`` to an existing or new session, ends the session, and
    enqueues the same post-session jobs as ``end_session``. ``is_ephemeral``
    short-circuits with a 200 *before* any DB write — matching v2's contract
    so the Flutter client's offline buffer can be cheaply discarded.
    """
    if body.is_ephemeral:
        return SaveSessionResponse(status="ephemeral_skipped", session=None)

    user_id = UUID(user.id)

    # 1. Resolve target session — attach to caller's existing one, or create.
    if body.session_id is not None:
        async with transaction(pool) as conn:
            existing = await sessions_repo.get(conn, body.session_id)
        if existing is None:
            raise NotFound("session not found")
        require_ownership(user, str(existing.user_id))
        session = existing
    else:
        title = body.title or f"Live Session {datetime.now(UTC):%Y-%m-%d %H:%M}"
        async with UnitOfWork(pool) as uow:
            session = await sessions_repo.start(
                uow.conn,
                user_id=user_id,
                title=title,
                mode=body.mode,
                idempotency_key=body.idempotency_key,
            )

    # 2. Persist batch turns (turn_index auto-assigned by append()).
    if body.logs:
        async with UnitOfWork(pool) as uow:
            for entry in body.logs:
                await session_logs_repo.append(
                    uow.conn,
                    session_id=session.id,
                    role=entry.speaker,
                    content=entry.text,
                    speaker_label=entry.speaker_label,
                    confidence=entry.confidence,
                )

    # 3. Mark the session ended (summary populated by extract_knowledge / digest jobs).
    async with UnitOfWork(pool) as uow:
        ended = await sessions_repo.end(uow.conn, session_id=session.id)

    # 4. Stored turns are authoritative; fall back to body.transcript only if empty.
    async with transaction(pool) as conn:
        row_transcript = await session_logs_repo.assemble_transcript(conn, session_id=session.id)
    transcript = row_transcript or body.transcript

    if arq is not None and transcript:
        await _enqueue_post_session_jobs(
            arq,
            user_id=str(user_id),
            session_id=str(session.id),
            transcript=transcript,
        )

    return SaveSessionResponse(status="saved", session=_to_out(ended or session))


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
        async with transaction(pool) as conn:
            linked = await scenarios_repo.get_by_session(conn, session_id=body.session_id)
        await _enqueue_post_session_jobs(
            arq,
            user_id=str(existing.user_id),
            session_id=str(body.session_id),
            transcript=transcript,
            scenario_id=str(linked.id) if linked is not None else None,
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


_TONE_LABELS = {
    "formal": "formal and polished",
    "semi-formal": "professional but warm",
    "casual": "casual and friendly",
}


@router.post("/suggest_reply", response_model=SuggestReplyResponse)
async def suggest_reply(
    body: SuggestReplyRequest,
    user: CurrentUserDep,
    pool: PoolDep,
    llm_router: RouterDep,
    embeddings: EmbeddingsDep,
) -> SuggestReplyResponse:
    # session_id is optional — ephemeral sessions/draft mode skip ownership check.
    if body.session_id is not None:
        async with transaction(pool) as conn:
            sess = await sessions_repo.get(conn, body.session_id)
        if sess is None:
            raise NotFound("session not found")
        require_ownership(user, str(sess.user_id))

    utterance = (body.partner_utterance or body.last_user_text or "").strip()
    if not utterance:
        return SuggestReplyResponse(suggestions=[], provider="")

    from bubbles.ai import wingman_context
    from bubbles.ai.prompts.loader import render
    from bubbles.ai.providers.base import ChatMessage, Role

    ctx = await wingman_context.build(
        pool,
        embeddings,
        user_id=UUID(user.id),
        transcript=utterance,
        session_id=body.session_id,
        mode="live_wingman",
    )

    system = render(
        "wingman/suggestions.jinja",
        tone_label=_TONE_LABELS.get(body.tone, "casual and friendly"),
        is_draft=body.is_draft,
        persona_block=ctx.persona_block,
        scenario_block=ctx.scenario_block,
        graph_facts=ctx.graph_facts,
        memory_context=ctx.memory_context,
    )
    user_prompt = f'Partner just said: "{utterance}"'

    from time import perf_counter

    t0 = perf_counter()
    try:
        completion = await llm_router.complete(
            "wingman.json",
            [
                ChatMessage(role=Role.system, content=system),
                ChatMessage(role=Role.user, content=user_prompt),
            ],
            response_format="json",
        )
    except Exception as exc:
        log.warning("suggest_reply_upstream", error=str(exc))
        return SuggestReplyResponse(suggestions=[], provider="", latency_ms=0)

    latency_ms = int((perf_counter() - t0) * 1000)
    provider = completion.raw.get("model", "") if isinstance(completion.raw, dict) else ""

    import json as _json

    suggestions: list[str] = []
    try:
        data = _json.loads(completion.text or "{}")
        raw = data.get("suggestions", [])
        if isinstance(raw, list):
            suggestions = [str(s).strip() for s in raw if str(s).strip()][:3]
    except (ValueError, TypeError):
        suggestions = []

    return SuggestReplyResponse(
        suggestions=suggestions, provider=str(provider), latency_ms=latency_ms
    )


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


_CONFIDENCE_CAPACITY = 10
_CONFIDENCE_REFILL_PER_S = 10 / 60  # ~10 calls per minute per user


@router.post(
    "/sessions/{session_id}/confidence",
    response_model=SetTurnConfidenceResponse,
)
async def set_turn_confidence(
    session_id: UUID,
    body: SetTurnConfidenceRequest,
    user: CurrentUserDep,
    pool: PoolDep,
    limiter: RateLimiterDep,
) -> SetTurnConfidenceResponse:
    rl = await limiter.check(
        f"confidence:{user.id}",
        capacity=_CONFIDENCE_CAPACITY,
        refill_per_s=_CONFIDENCE_REFILL_PER_S,
    )
    if not rl.allowed:
        raise RateLimited(rl.retry_after_s)

    async with transaction(pool) as conn:
        existing = await sessions_repo.get(conn, session_id)
    if existing is None:
        raise NotFound("session not found")
    require_ownership(user, str(existing.user_id))

    items = [(item.turn_index, item.score) for item in body.confidence_by_turn]
    async with UnitOfWork(pool) as uow:
        updated = await session_logs_repo.update_confidence_bulk(
            uow.conn, session_id=session_id, items=items
        )

    log.info(
        "set_turn_confidence_done",
        user=user.id,
        session=str(session_id),
        sent=len(items),
        updated=updated,
    )
    return SetTurnConfidenceResponse(updated=updated)
