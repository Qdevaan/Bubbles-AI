"""
Session routes — start, save, end, wingman transcript processing.

v2 additions:
  - Idempotency key support on start_session, save_session, end_session.
  - Gamification fire-and-forget hooks (XP, quests, streaks) via fire_and_forget().
  - Transcript validation via validate_transcript().
  - Batch logs validation via validate_batch_logs().
"""

import asyncio
import logging
import json
from datetime import datetime
from typing import Dict, List

from fastapi import APIRouter, Depends, Request
from starlette.responses import StreamingResponse

from app.config import settings
from app.models.requests import (
    StartSessionRequest,
    SaveSessionRequest,
    EndSessionRequest,
    WingmanRequest,
)
from app.services import graph_svc, vector_svc, brain_svc, session_svc, entity_svc, audit_svc, gamification_svc, dispatcher_svc
from app.utils import fire_and_forget
from app.utils.rate_limit import limiter
from app.utils.text_sanitizer import sanitize_input
from app.utils.session_store import session_store
from app.utils.auth_guard import get_verified_user, VerifiedUser
from app.utils.validation import validate_transcript, validate_batch_logs

logger = logging.getLogger(__name__)

router = APIRouter()

_MAX_GLOBAL_SESSIONS = 500

# -- Context cache warm-up

async def _warm_context_cache(user_id: str, session_id: str) -> None:
    """Pre-load graph + vector + performa context at session start for zero-latency per-turn use."""
    import app.services.performa_service as performa_svc

    def _graph():
        graph_svc.load_graph(user_id)
        return graph_svc.find_context(user_id, "")

    def _vector():
        return vector_svc.search_memory(user_id, "")

    def _performa():
        return performa_svc.build_context_block(user_id)

    try:
        g_ctx, v_ctx, p_ctx = await asyncio.wait_for(
            asyncio.gather(
                asyncio.to_thread(_graph),
                asyncio.to_thread(_vector),
                asyncio.to_thread(_performa),
            ),
            timeout=2.0,
        )
        await session_store.set_context_cache(session_id, {
            "graph": g_ctx or "",
            "vector": v_ctx or "",
            "performa": p_ctx or "",
        })
    except asyncio.TimeoutError:
        await session_store.set_context_cache(session_id, {"graph": "", "vector": "", "performa": ""})




# ── Helpers ───────────────────────────────────────────────────────────────────

def _get_client_info(request: Request) -> dict:
    ip = request.client.host if request.client else None
    ua = request.headers.get("user-agent")
    return {"ip_address": ip, "user_agent": ua}


async def _check_idempotency(key: str | None, table: str, field: str) -> str | None:
    """
    Check if an idempotency key was already processed.
    Returns the existing resource ID if found, None otherwise.
    """
    if not key:
        return None
    from app.database import db as _db
    if not _db:
        return None
    try:
        res = await asyncio.to_thread(
            lambda: _db.table(table)
            .select("id")
            .eq("idempotency_key", key)
            .maybe_single()
            .execute()
        )
        if res.data:
            return res.data["id"]
    except Exception:
        pass
    return None


# ══════════════════════════════════════════════════════════════════════════════
# POST /start_session
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/start_session")
@limiter.limit("10/minute")
async def start_session_endpoint(
    request: Request,
    req: StartSessionRequest,
    user: VerifiedUser = Depends(get_verified_user),
):
    """Create a new session and return its ID."""
    # Idempotency check
    if req.idempotency_key:
        existing_id = await _check_idempotency(req.idempotency_key, "sessions", "idempotency_key")
        if existing_id:
            return {"session_id": existing_id, "idempotent": True}

    session_id = await asyncio.to_thread(
        session_svc.start_session,
        req.user_id,
        mode=req.mode,
        is_ephemeral=req.is_ephemeral,
        is_multiplayer=req.is_multiplayer,
        persona=req.persona,
        device_id=req.device_id,
        session_type=req.session_type,
        idempotency_key=req.idempotency_key,
    )

    await session_store.set_live_session(req.user_id, session_id)
    metadata = {
        "is_ephemeral": req.is_ephemeral,
        "is_multiplayer": req.is_multiplayer,
        "persona": req.persona,
    }
    if req.target_entity_id is not None:
        metadata["target_entity_id"] = req.target_entity_id
    await session_store.set_metadata(session_id, metadata)

    await session_store.evict_oldest_if_over(_MAX_GLOBAL_SESSIONS)

    client = _get_client_info(request)
    await asyncio.to_thread(
        audit_svc.log,
        req.user_id, "session_started",
        entity_type="session", entity_id=session_id,
        details={"mode": req.mode, "persona": req.persona,
                 "is_ephemeral": req.is_ephemeral, "is_multiplayer": req.is_multiplayer},
        ip_address=client["ip_address"], user_agent=client["user_agent"],
    )

    # Gamification: update streak on first action of the session
    fire_and_forget(gamification_svc.update_streak(req.user_id))
    fire_and_forget(gamification_svc.award_xp(
        req.user_id, 10, "first_session_today",
        source_id=f"first_today_{datetime.now().date().isoformat()}_{req.user_id}",
        description="First action of the day",
    ))

    asyncio.create_task(_warm_context_cache(req.user_id, session_id))
    return {"session_id": session_id}


# ══════════════════════════════════════════════════════════════════════════════
# POST /process_transcript_wingman
# ══════════════════════════════════════════════════════════════════════════════

async def _wingman_post_process(
    *,
    user_id: str,
    session_id: str | None,
    transcript: str,
    g_ctx: str,
    is_ephemeral: bool,
    advice_text: str,
    advice_meta: dict,
    turn_count: int = 0,
) -> None:
    """Background task: log LLM advice, extract, update graph, persist memory."""
    try:
        if session_id and advice_text and advice_text != "WAITING":
            await asyncio.to_thread(
                session_svc.log_message,
                session_id, "llm", advice_text,
                is_ephemeral=is_ephemeral,
                model_used=advice_meta.get("model_used"),
                latency_ms=advice_meta.get("latency_ms"),
                tokens_used=advice_meta.get("tokens_used"),
                finish_reason=advice_meta.get("finish_reason"),
            )
            if not is_ephemeral:
                await asyncio.to_thread(
                    session_svc.update_session_token_usage,
                    session_id,
                    tokens_prompt=advice_meta.get("tokens_prompt", 0),
                    tokens_completion=advice_meta.get("tokens_completion", 0),
                )

        # ── Throttle: only extract entities every 5 turns to reduce LLM load ──
        # Extraction is a full secondary LLM call; running it on every sentence
        # competes with the primary advice call and hurts latency.
        should_extract = (turn_count % 5 == 0) if turn_count > 0 else False

        if should_extract:
            extraction = await brain_svc.extract_all_from_transcript(transcript, g_ctx)
            new_rels  = extraction.get("relations", [])
            entities  = extraction.get("entities", [])
            events    = extraction.get("events", [])
            tasks     = extraction.get("tasks", [])
            conflicts = extraction.get("conflicts", [])

            if entities:
                await asyncio.to_thread(
                    entity_svc.persist_extraction, user_id,
                    {"entities": entities, "relations": new_rels}, session_id,
                )
                entity_count = min(len(entities), 5)
                fire_and_forget(gamification_svc.award_xp(
                    user_id, entity_count * 5, "entity_extraction",
                    source_id=f"extract_{session_id}_{datetime.now().isoformat()[:16]}",
                    description=f"Extracted {entity_count} entities",
                ))
                fire_and_forget(gamification_svc.increment_quest_progress(
                    user_id, "extract_entities", entity_count,
                ))

            if session_id and not is_ephemeral and extraction.get("tokens_used"):
                await asyncio.to_thread(
                    session_svc.update_session_token_usage,
                    session_id,
                    tokens_prompt=extraction.get("tokens_prompt", 0),
                    tokens_completion=extraction.get("tokens_completion", 0),
                )

            if new_rels:
                graph_svc.update_local_graph(user_id, new_rels)
                if conflicts:
                    await asyncio.to_thread(entity_svc.save_conflicts, user_id, conflicts, session_id)
            await asyncio.to_thread(graph_svc.save_graph, user_id)

            if events:
                await asyncio.to_thread(entity_svc.save_events, user_id, events, session_id)
            if tasks:
                await asyncio.to_thread(entity_svc.save_tasks, user_id, tasks, session_id)

        # Memory save always runs (cheap vector embed, not a full LLM call)
        await vector_svc.save_memory(
            user_id, f"Others: {transcript}", session_id=session_id,
        )
        fire_and_forget(gamification_svc.increment_quest_progress(user_id, "save_memory", 1))
        fire_and_forget(gamification_svc.increment_quest_progress(user_id, "use_wingman_turns", 1))

        if session_id:
            turn_count_now = await session_store.increment_turn_count(session_id)
            if turn_count_now % 20 == 0:
                _sid = session_id
                _turn = turn_count_now

                async def _rolling_summarize():
                    from app.database import db as _db
                    try:
                        logs_res = await asyncio.to_thread(
                            lambda: _db.table("session_logs")
                            .select("role, content")
                            .eq("session_id", _sid)
                            .order("created_at")
                            .execute()
                        )
                        recent_rows = (logs_res.data or [])[-40:]
                        partial_transcript = "\n".join(
                            f"{r['role'].upper()}: {r['content']}" for r in recent_rows
                        )
                        if partial_transcript:
                            rolling_summary = await brain_svc.generate_summary(partial_transcript)
                            if rolling_summary:
                                prev_res = await asyncio.to_thread(
                                    lambda: _db.table("sessions")
                                    .select("summary")
                                    .eq("id", _sid)
                                    .execute()
                                )
                                prev_summary = ""
                                if prev_res.data and prev_res.data[0].get("summary"):
                                    prev_summary = prev_res.data[0]["summary"]
                                combined = (
                                    f"{prev_summary}\n---\n[Turn {_turn}] {rolling_summary}"
                                ).strip()
                                await asyncio.to_thread(
                                    lambda: _db.table("sessions")
                                    .update({"summary": combined})
                                    .eq("id", _sid)
                                    .execute()
                                )
                    except Exception as e:
                        print(f"❌ Rolling summarize error: {e}")

                asyncio.create_task(_rolling_summarize())

    except Exception as exc:
        print(f"❌ Wingman post-process error: {exc}")



@router.post("/process_transcript_wingman")
@limiter.limit("30/minute")
async def process_transcript_wingman(
    request: Request,
    req: WingmanRequest,
    user: VerifiedUser = Depends(get_verified_user),
):
    """
    Real-time wingman: log turn, generate advice, extract entities+events+tasks
    in ONE LLM call, detect conflicts, save to memory.
    """
    user_id = req.user_id
    transcript = validate_transcript(sanitize_input(req.transcript))
    session_id = req.session_id
    speaker_role = req.speaker_role if req.speaker_role in ("user", "others") else "others"

    meta = await session_store.get_metadata(session_id) if session_id else {}
    is_ephemeral = meta.get("is_ephemeral", False)

    # 0. Log incoming transcript — fire-and-forget so it never blocks advice
    if session_id:
        _sl = req.speaker_label
        _conf = req.confidence
        asyncio.create_task(asyncio.to_thread(
            session_svc.log_message,
            session_id, speaker_role, transcript,
            speaker_label=_sl,
            confidence=_conf,
            is_ephemeral=is_ephemeral,
        ))

    # Fast-path for user turns: already logging, save memory in background and return
    if speaker_role == "user":
        asyncio.create_task(vector_svc.save_memory(
            user_id, f"User: {transcript}", session_id=session_id,
        ))
        fire_and_forget(gamification_svc.increment_quest_progress(user_id, "save_memory", 1))
        return {"advice": "WAITING"}

    # 1. Load contexts -- try cache first, 200ms hard-timeout fallback on miss
    target_entity_id = meta.get("target_entity_id") if session_id else None
    cached = await session_store.get_context_cache(session_id) if session_id else {}
    if cached:
        g_ctx = cached.get("graph", "")
        v_ctx = cached.get("vector", "")
        e_ctx = ""
        if target_entity_id:
            e_ctx = await asyncio.to_thread(
                entity_svc.get_entity_context, user_id, str(target_entity_id)
            )
    else:
        def _graph_ctx():
            graph_svc.load_graph(user_id)
            return graph_svc.find_context(user_id, transcript)

        def _entity_ctx():
            if target_entity_id:
                return entity_svc.get_entity_context(user_id, str(target_entity_id))
            return ""

        try:
            g_ctx, v_ctx, e_ctx = await asyncio.wait_for(
                asyncio.gather(
                    asyncio.to_thread(_graph_ctx),
                    asyncio.to_thread(vector_svc.search_memory, user_id, transcript),
                    asyncio.to_thread(_entity_ctx),
                ),
                timeout=0.2,  # 200ms hard cap on cache miss
            )
        except asyncio.TimeoutError:
            g_ctx, v_ctx, e_ctx = "", "", ""

    if e_ctx:
        g_ctx = f"ROLEPLAY TARGET ENTITY CONTEXT:\n{e_ctx}\n\n" + g_ctx

    # 2. Get wingman advice — this is what the client is waiting for
    p_ctx = cached.get("performa", "") if cached else ""
    result = await brain_svc.get_wingman_advice(
        user_id, transcript, g_ctx, v_ctx, req.mode, req.persona,
        performa_context=p_ctx,
    )
    advice_text = result.get("answer", "WAITING")

    # 3. Fire background: log LLM advice + extract + graph + memory (non-blocking)
    # Fetch turn count first so the background task can throttle extraction
    current_turn = await session_store.get_turn_count(session_id) if session_id else 0
    asyncio.create_task(_wingman_post_process(
        user_id=user_id,
        session_id=session_id,
        transcript=transcript,
        g_ctx=g_ctx,
        is_ephemeral=is_ephemeral,
        advice_text=advice_text,
        advice_meta=result,
        turn_count=current_turn,
    ))

    return {"advice": advice_text}


# ══════════════════════════════════════════════════════════════════════════════
# POST /save_session
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/save_session")
@limiter.limit("10/minute")
async def save_session_endpoint(
    request: Request,
    req: SaveSessionRequest,
    user: VerifiedUser = Depends(get_verified_user),
):
    """Save a completed session (no prior active session entry)."""
    if req.is_ephemeral:
        return {"status": "success", "session_id": "ephemeral-skipped"}

    # Idempotency check
    if req.idempotency_key:
        existing_id = await _check_idempotency(req.idempotency_key, "sessions", "idempotency_key")
        if existing_id:
            return {"status": "success", "session_id": existing_id, "idempotent": True}

    user_id = req.user_id
    transcript = validate_transcript(req.transcript)
    logs = validate_batch_logs(req.logs)

    session_id = await asyncio.to_thread(
        session_svc.create_session_record,
        user_id,
        title=f"Live Session {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        mode="live_wingman",
        idempotency_key=req.idempotency_key,
    )

    await asyncio.to_thread(session_svc.log_batch_messages, session_id, logs)

    extraction = await brain_svc.extract_all_from_transcript(transcript)
    new_rels = extraction.get("relations", [])
    entities = extraction.get("entities", [])
    events = extraction.get("events", [])
    tasks = extraction.get("tasks", [])

    if entities:
        await asyncio.to_thread(
            entity_svc.persist_extraction, user_id,
            {"entities": entities, "relations": new_rels}, session_id,
        )

    highlights = await brain_svc.extract_highlights(transcript)
    if highlights:
        await asyncio.to_thread(entity_svc.save_highlights, user_id, highlights, session_id)

    if events:
        await asyncio.to_thread(entity_svc.save_events, user_id, events, session_id)

    if tasks:
        await asyncio.to_thread(entity_svc.save_tasks, user_id, tasks, session_id)

    if new_rels:
        await asyncio.to_thread(graph_svc.load_graph, user_id)
        graph_svc.update_local_graph(user_id, new_rels)
        await asyncio.to_thread(graph_svc.save_graph, user_id)

    summary = await brain_svc.generate_summary(transcript)
    await asyncio.to_thread(
        session_svc.end_session, session_id, summary=summary or None
    )

    # AI-generated session title (fire-and-forget)
    async def _patch_title_save():
        try:
            title = await brain_svc.generate_title(
                transcript[:600] if transcript else (summary or "")
            )
            if title:
                from app.database import db as _db2
                await asyncio.to_thread(
                    lambda: _db2.table("sessions")
                    .update({"title": title})
                    .eq("id", session_id)
                    .execute()
                )
        except Exception as _e:
            print(f"⚠️ Title generation (save_session) error: {_e}")
    asyncio.create_task(_patch_title_save())

    mem_content = (
        f"Session Summary: {summary}" if summary
        else f"Session Transcript: {transcript[:1000]}"
    )
    await vector_svc.save_memory(user_id, mem_content, session_id=session_id)

    client = _get_client_info(request)
    await asyncio.to_thread(
        audit_svc.log,
        user_id, "session_saved",
        entity_type="session", entity_id=session_id,
        details={"turns": len(logs)},
        ip_address=client["ip_address"], user_agent=client["user_agent"],
    )

    # Gamification
    fire_and_forget(gamification_svc.award_xp(
        user_id, 30, "session_complete", source_id=session_id,
        description="Completed wingman session",
    ))
    fire_and_forget(gamification_svc.increment_quest_progress(user_id, "complete_session", 1))
    fire_and_forget(gamification_svc.increment_quest_progress(user_id, "save_memory", 1))
    fire_and_forget(gamification_svc.update_streak(user_id))
    fire_and_forget(dispatcher_svc.personalize_quest_briefs(user_id))

    return {"status": "success", "session_id": session_id}


# ══════════════════════════════════════════════════════════════════════════════
# POST /end_session
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/end_session")
@limiter.limit("10/minute")
async def end_session_endpoint(
    request: Request,
    req: EndSessionRequest,
    user: VerifiedUser = Depends(get_verified_user),
):
    """End an active session: summarize, mark completed, compute analytics."""
    from app.routes.analytics import _compute_session_analytics
    from app.database import db as _db

    # Idempotency check
    if req.idempotency_key:
        existing_id = await _check_idempotency(req.idempotency_key, "sessions", "idempotency_key")
        if existing_id:
            return {"status": "completed", "session_id": req.session_id, "idempotent": True}

    try:
        meta = await session_store.get_metadata(req.session_id)
        is_ephemeral = meta.get("is_ephemeral", False)

        if is_ephemeral:
            await asyncio.to_thread(
                session_svc.end_session, req.session_id, is_ephemeral=True
            )
        else:
            logs_res = await asyncio.to_thread(
                lambda: _db.table("session_logs")
                .select("role, content")
                .eq("session_id", req.session_id)
                .order("created_at")
                .execute()
            )
            full_transcript = "\n".join(
                f"{r['role'].upper()}: {r['content']}"
                for r in (logs_res.data or [])
            )
            summary = (
                await brain_svc.generate_summary(full_transcript) if full_transcript else ""
            )
            await asyncio.to_thread(
                session_svc.end_session, req.session_id, summary=summary or None
            )

            # AI-generated session title (fire-and-forget; won't block end_session)
            async def _patch_title_end():
                try:
                    title = await brain_svc.generate_title(
                        full_transcript[:600] if full_transcript else (summary or "")
                    )
                    if title:
                        from app.database import db as _db2
                        await asyncio.to_thread(
                            lambda: _db2.table("sessions")
                            .update({"title": title})
                            .eq("id", req.session_id)
                            .execute()
                        )
                except Exception as _e:
                    print(f"⚠️ Title generation (end_session) error: {_e}")
            asyncio.create_task(_patch_title_end())

            if full_transcript:
                mem_content = (
                    f"Session Summary: {summary}" if summary
                    else full_transcript[:500]
                )
                await vector_svc.save_memory(
                    req.user_id, mem_content, session_id=req.session_id,
                )

                highlights = await brain_svc.extract_highlights(full_transcript)
                if highlights:
                    await asyncio.to_thread(
                        entity_svc.save_highlights, req.user_id, highlights, req.session_id,
                    )
                extra = await brain_svc.extract_all_from_transcript(full_transcript)
                if extra.get("tasks"):
                    await asyncio.to_thread(
                        entity_svc.save_tasks, req.user_id, extra["tasks"], req.session_id,
                    )

    except Exception as e:
        print(f"❌ end_session error: {e}")
        await asyncio.to_thread(session_svc.end_session, req.session_id)

    await session_store.delete_session(req.session_id, req.user_id)

    asyncio.create_task(_compute_session_analytics(req.session_id, req.user_id))

    client = _get_client_info(request)
    await asyncio.to_thread(
        audit_svc.log,
        req.user_id, "session_ended",
        entity_type="session", entity_id=req.session_id,
        ip_address=client["ip_address"], user_agent=client["user_agent"],
    )

    # Gamification
    fire_and_forget(gamification_svc.award_xp(
        req.user_id, 30, "session_complete", source_id=req.session_id,
        description="Completed wingman session",
    ))
    fire_and_forget(gamification_svc.increment_quest_progress(req.user_id, "complete_session", 1))
    fire_and_forget(gamification_svc.increment_quest_progress(req.user_id, "save_memory", 1))
    fire_and_forget(gamification_svc.update_streak(req.user_id))
    fire_and_forget(dispatcher_svc.personalize_quest_briefs(req.user_id))

    # Post-session performa insight analysis (fire-and-forget)
    async def _run_performa_analysis():
        try:
            import app.services.performa_service as _ps
            from app.database import db as _db
            logs_res = await asyncio.to_thread(
                lambda: _db.table("session_logs")
                .select("role, content")
                .eq("session_id", req.session_id)
                .order("created_at")
                .execute()
            )
            text = "\n".join(
                f'{"You" if r["role"] == "user" else "Other"}: {r["content"]}'
                for r in (logs_res.data or []) if r.get("content")
            )
            if text:
                await _ps.analyze_session_for_insights(
                    req.user_id, req.session_id, text,
                    llm_client=brain_svc.client,
                    model=settings.WINGMAN_MODEL,
                )
        except Exception as e:
            logger.warning(f"Performa post-session analysis error: {e}")
    asyncio.create_task(_run_performa_analysis())

    return {"status": "completed", "session_id": req.session_id}
