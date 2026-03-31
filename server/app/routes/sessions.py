"""
Session routes — start, save, end, wingman transcript processing.

FIXES APPLIED:
  - All brain_svc calls are now `await`ed (async LLM calls).
  - Sequential 4-call LLM chain replaced with single extract_all_from_transcript().
  - In-memory global dicts replaced with session_store (Redis/in-memory abstraction).
  - Synchronous Supabase DB calls inside async functions wrapped in asyncio.to_thread().
  - JWT auth verification via get_verified_user dependency on all endpoints.
"""

import asyncio
import json
from datetime import datetime
from typing import Dict, List

from fastapi import APIRouter, Depends, Request
from starlette.responses import StreamingResponse

from app.models.requests import (
    StartSessionRequest,
    SaveSessionRequest,
    EndSessionRequest,
    WingmanRequest,
)
from app.services import graph_svc, vector_svc, brain_svc, session_svc, entity_svc, audit_svc
from app.utils.rate_limit import limiter
from app.utils.text_sanitizer import sanitize_input
from app.utils.session_store import session_store
from app.utils.auth_guard import get_verified_user, VerifiedUser

router = APIRouter()

_MAX_GLOBAL_SESSIONS = 500


# ── Helpers ───────────────────────────────────────────────────────────────────

def _get_client_info(request: Request) -> dict:
    """Extract client IP and user-agent from the request for audit logging."""
    ip = request.client.host if request.client else None
    ua = request.headers.get("user-agent")
    return {"ip_address": ip, "user_agent": ua}


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
    session_id = await asyncio.to_thread(
        session_svc.start_session,
        req.user_id,
        mode=req.mode,
        is_ephemeral=req.is_ephemeral,
        is_multiplayer=req.is_multiplayer,
        persona=req.persona,
        device_id=req.device_id,
        session_type=req.session_type,
    )

    # Store session state in the abstracted session store (Redis or in-memory)
    await session_store.set_live_session(req.user_id, session_id)
    metadata = {
        "is_ephemeral": req.is_ephemeral,
        "is_multiplayer": req.is_multiplayer,
        "persona": req.persona,
    }
    if req.target_entity_id is not None:
        metadata["target_entity_id"] = req.target_entity_id
    await session_store.set_metadata(session_id, metadata)

    # Cap global sessions
    await session_store.evict_oldest_if_over(_MAX_GLOBAL_SESSIONS)

    # Audit log (sync call — wrapped)
    client = _get_client_info(request)
    await asyncio.to_thread(
        audit_svc.log,
        req.user_id, "session_started",
        entity_type="session", entity_id=session_id,
        details={"mode": req.mode, "persona": req.persona,
                 "is_ephemeral": req.is_ephemeral, "is_multiplayer": req.is_multiplayer},
        ip_address=client["ip_address"], user_agent=client["user_agent"],
    )

    return {"session_id": session_id}


# ══════════════════════════════════════════════════════════════════════════════
# POST /process_transcript_wingman
# ══════════════════════════════════════════════════════════════════════════════

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
    transcript = sanitize_input(req.transcript)
    session_id = req.session_id
    speaker_role = req.speaker_role if req.speaker_role in ("user", "others") else "others"

    # Load session metadata from store (async)
    meta = await session_store.get_metadata(session_id) if session_id else {}
    is_ephemeral = meta.get("is_ephemeral", False)

    # 0. Log incoming transcript
    if session_id:
        await asyncio.to_thread(
            session_svc.log_message,
            session_id, speaker_role, transcript,
            speaker_label=req.speaker_label,
            confidence=req.confidence,
            is_ephemeral=is_ephemeral,
        )

    # 1. Load contexts in parallel
    def _graph_ctx():
        graph_svc.load_graph(user_id)
        return graph_svc.find_context(user_id, transcript)

    target_entity_id = meta.get("target_entity_id") if session_id else None

    def _entity_ctx():
        if target_entity_id:
            return entity_svc.get_entity_context(user_id, str(target_entity_id))
        return ""

    g_ctx, v_ctx, e_ctx = await asyncio.gather(
        asyncio.to_thread(_graph_ctx),
        asyncio.to_thread(vector_svc.search_memory, user_id, transcript),
        asyncio.to_thread(_entity_ctx),
    )

    if e_ctx:
        g_ctx = f"ROLEPLAY TARGET ENTITY CONTEXT:\n{e_ctx}\n\n" + g_ctx

    # 2. Get wingman advice (ASYNC — no longer blocks event loop)
    advice_text = "WAITING"
    advice_meta = {}
    if speaker_role == "others":
        result = await brain_svc.get_wingman_advice(
            user_id, transcript, g_ctx, v_ctx, req.mode, req.persona,
        )
        advice_text = result.get("answer", "WAITING")
        advice_meta = result

    # 3. Log LLM advice
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
        if session_id and not is_ephemeral:
            await asyncio.to_thread(
                session_svc.update_session_token_usage,
                session_id,
                tokens_prompt=advice_meta.get("tokens_prompt", 0),
                tokens_completion=advice_meta.get("tokens_completion", 0),
            )

    # 4. UNIFIED EXTRACTION — replaces 4 separate LLM calls (entities + events + tasks + conflicts)
    #    One async LLM call extracts everything simultaneously.
    extraction = await brain_svc.extract_all_from_transcript(transcript, g_ctx)

    new_rels = extraction.get("relations", [])
    entities = extraction.get("entities", [])
    events = extraction.get("events", [])
    tasks = extraction.get("tasks", [])
    conflicts = extraction.get("conflicts", [])

    # Persist entities
    if entities:
        await asyncio.to_thread(
            entity_svc.persist_extraction, user_id,
            {"entities": entities, "relations": new_rels}, session_id,
        )

    # Track extraction token usage
    if session_id and not is_ephemeral and extraction.get("tokens_used"):
        await asyncio.to_thread(
            session_svc.update_session_token_usage,
            session_id,
            tokens_prompt=extraction.get("tokens_prompt", 0),
            tokens_completion=extraction.get("tokens_completion", 0),
        )

    # 5. Update graph
    if new_rels:
        graph_svc.update_local_graph(user_id, new_rels)
        if conflicts:
            await asyncio.to_thread(entity_svc.save_conflicts, user_id, conflicts, session_id)
    await asyncio.to_thread(graph_svc.save_graph, user_id)

    # 6. Persist events
    if events:
        await asyncio.to_thread(entity_svc.save_events, user_id, events, session_id)

    # 7. Persist tasks
    if tasks:
        await asyncio.to_thread(entity_svc.save_tasks, user_id, tasks, session_id)

    # 8. Save to long-term memory
    await vector_svc.save_memory(
        user_id, f"{speaker_role.capitalize()}: {transcript}",
        session_id=session_id,
    )

    # 9. Rolling summarization every 20 turns (fully async DB)
    if session_id:
        turn_count = await session_store.increment_turn_count(session_id)
        if turn_count % 20 == 0:
            _sid = session_id
            _turn = turn_count

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
                            print(f"🔄 Rolling summary appended at turn {_turn}")
                except Exception as e:
                    print(f"❌ Rolling summarize error: {e}")

            asyncio.create_task(_rolling_summarize())

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

    user_id = req.user_id
    transcript = req.transcript
    logs = req.logs

    # 1. Create session record (async-wrapped)
    session_id = await asyncio.to_thread(
        session_svc.create_session_record,
        user_id,
        title=f"Live Session {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        mode="live_wingman",
    )

    # 2. Bulk-log turns (async-wrapped)
    await asyncio.to_thread(session_svc.log_batch_messages, session_id, logs)

    # 3. Unified extraction (ONE LLM call for everything)
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

    # 4. Extract highlights (separate async call — different schema)
    highlights = await brain_svc.extract_highlights(transcript)
    if highlights:
        await asyncio.to_thread(entity_svc.save_highlights, user_id, highlights, session_id)

    # 5. Persist events
    if events:
        await asyncio.to_thread(entity_svc.save_events, user_id, events, session_id)

    # 6. Persist tasks
    if tasks:
        await asyncio.to_thread(entity_svc.save_tasks, user_id, tasks, session_id)

    # 7. Update knowledge graph (sync calls on graph are CPU-bound, safe to thread)
    if new_rels:
        await asyncio.to_thread(graph_svc.load_graph, user_id)
        graph_svc.update_local_graph(user_id, new_rels)
        await asyncio.to_thread(graph_svc.save_graph, user_id)

    # 8. Generate summary and mark completed
    summary = await brain_svc.generate_summary(transcript)
    await asyncio.to_thread(
        session_svc.end_session, session_id, summary=summary or None
    )

    # 9. Save to long-term memory
    mem_content = (
        f"Session Summary: {summary}" if summary
        else f"Session Transcript: {transcript[:1000]}"
    )
    await vector_svc.save_memory(user_id, mem_content, session_id=session_id)

    # 10. Audit log
    client = _get_client_info(request)
    await asyncio.to_thread(
        audit_svc.log,
        user_id, "session_saved",
        entity_type="session", entity_id=session_id,
        details={"turns": len(logs)},
        ip_address=client["ip_address"], user_agent=client["user_agent"],
    )

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

            if full_transcript:
                mem_content = (
                    f"Session Summary: {summary}" if summary
                    else full_transcript[:500]
                )
                await vector_svc.save_memory(
                    req.user_id, mem_content, session_id=req.session_id,
                )

                # Extract highlights and tasks on session end
                highlights = await brain_svc.extract_highlights(full_transcript)
                if highlights:
                    await asyncio.to_thread(
                        entity_svc.save_highlights, req.user_id, highlights, req.session_id,
                    )
                # Extract remaining tasks
                extra = await brain_svc.extract_all_from_transcript(full_transcript)
                if extra.get("tasks"):
                    await asyncio.to_thread(
                        entity_svc.save_tasks, req.user_id, extra["tasks"], req.session_id,
                    )

    except Exception as e:
        print(f"❌ end_session error: {e}")
        await asyncio.to_thread(session_svc.end_session, req.session_id)

    # Clean up session store (atomic)
    await session_store.delete_session(req.session_id, req.user_id)

    # Fire analytics in background
    asyncio.create_task(_compute_session_analytics(req.session_id, req.user_id))

    # Audit log
    client = _get_client_info(request)
    await asyncio.to_thread(
        audit_svc.log,
        req.user_id, "session_ended",
        entity_type="session", entity_id=req.session_id,
        ip_address=client["ip_address"], user_agent=client["user_agent"],
    )

    return {"status": "completed", "session_id": req.session_id}
