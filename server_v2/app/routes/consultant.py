"""
Consultant routes — blocking, streaming, and batch Q&A.

v2 additions:
  - Gamification fire-and-forget hooks (XP, quests, streaks).
  - Rate limit on batch endpoint.
  - Batch question validation.
"""

import asyncio
import json
from datetime import datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Request
from starlette.responses import StreamingResponse

from app.config import settings
from app.models.requests import ConsultantRequest, BatchConsultantRequest
from app.services import graph_svc, vector_svc, brain_svc, session_svc, entity_svc, audit_svc, gamification_svc
from app.utils import fire_and_forget
from app.utils.session_store import session_store
from app.utils.rate_limit import limiter
from app.utils.text_sanitizer import sanitize_input
from app.utils.auth_guard import get_verified_user, VerifiedUser
from app.utils.validation import validate_batch_questions

router = APIRouter()


# ══════════════════════════════════════════════════════════════════════════════
# POST /ask_consultant  (blocking)
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/ask_consultant")
@limiter.limit("10/minute")
async def ask_consultant_endpoint(
    request: Request,
    req: ConsultantRequest,
    user: VerifiedUser = Depends(get_verified_user),
):
    """Blocking consultant Q&A using the 70B model (fully async)."""
    session_id = req.session_id
    if not session_id:
        session_id = await asyncio.to_thread(
            session_svc.create_session_record,
            req.user_id,
            title=f"Consultant {datetime.now().strftime('%Y-%m-%d %H:%M')}",
            mode="consultant",
        )

    def _graph_ctx():
        graph_svc.load_graph(req.user_id)
        return graph_svc.find_context(req.user_id, req.question, top_k=10)

    meta = await session_store.get_metadata(session_id) if session_id else {}
    target_entity_id = meta.get("target_entity_id")

    def _entity_ctx():
        if target_entity_id:
            return entity_svc.get_entity_context(req.user_id, str(target_entity_id))
        return ""

    g_ctx, v_ctx, h_ctx, s_ctx, e_ctx = await asyncio.gather(
        asyncio.to_thread(_graph_ctx),
        asyncio.to_thread(vector_svc.search_memory, req.user_id, req.question),
        asyncio.to_thread(session_svc.fetch_consultant_history, req.user_id, 5, session_id),
        asyncio.to_thread(session_svc.fetch_session_summaries, req.user_id, 3),
        asyncio.to_thread(_entity_ctx),
    )

    if e_ctx:
        g_ctx = f"ROLEPLAY TARGET ENTITY CONTEXT:\n{e_ctx}\n\n" + g_ctx

    safe_question = sanitize_input(req.question)
    result = await brain_svc.ask_consultant(
        req.user_id, safe_question, h_ctx, g_ctx, v_ctx,
        session_summaries=s_ctx, mode=req.mode, persona=req.persona,
    )
    answer = result.get("answer", "")

    await asyncio.to_thread(
        session_svc.log_consultant_qa,
        req.user_id, req.question, answer, session_id=session_id,
        model_used=result.get("model_used"),
        latency_ms=result.get("latency_ms"),
        tokens_used=result.get("tokens_used"),
    )

    await asyncio.to_thread(
        session_svc.update_session_token_usage,
        session_id,
        tokens_prompt=result.get("tokens_prompt", 0),
        tokens_completion=result.get("tokens_completion", 0),
    )

    await vector_svc.save_memory(
        req.user_id, f"Q: {req.question}\nA: {answer}",
        session_id=session_id,
    )
    # Extract entities/relations from Q&A and persist to knowledge graph
    try:
        extraction = await brain_svc.extract_all_from_transcript(
            f"Q: {req.question}\nA: {answer}", g_ctx
        )
        entities = extraction.get("entities", [])
        relations = extraction.get("relations", [])
        if entities:
            await asyncio.to_thread(
                entity_svc.persist_extraction, req.user_id,
                {"entities": entities, "relations": relations}, session_id,
            )
    except Exception as _e:
        print(f"⚠️ Consultant entity extraction error: {_e}")

    await asyncio.to_thread(
        audit_svc.log,
        req.user_id, "consultant_query",
        entity_type="consultant_log", entity_id=session_id,
        details={"mode": req.mode, "persona": req.persona,
                 "latency_ms": result.get("latency_ms"),
                 "tokens_used": result.get("tokens_used")},
    )

    # Gamification
    fire_and_forget(gamification_svc.award_xp(
        req.user_id, 15, "consultant_qa",
        source_id=session_id,
        description="Consultant Q&A",
    ))
    fire_and_forget(gamification_svc.increment_quest_progress(req.user_id, "ask_consultant", 1))
    fire_and_forget(gamification_svc.increment_quest_progress(req.user_id, "save_memory", 1))
    fire_and_forget(gamification_svc.update_streak(req.user_id))

    return {"answer": answer, "session_id": session_id}


# ══════════════════════════════════════════════════════════════════════════════
# POST /ask  (lightweight — graph quick-reference & query engine)
# ══════════════════════════════════════════════════════════════════════════════

class _AskRequest(ConsultantRequest):
    """Thin alias used by the graph query engine."""
    context: str = ""  # e.g. 'knowledge_graph'


@router.post("/ask")
@limiter.limit("20/minute")
async def ask_endpoint(
    request: Request,
    req: _AskRequest,
    user: VerifiedUser = Depends(get_verified_user),
):
    """Lightweight Q&A used by the graph query bar and node quick-reference.
    Now supports session history for follow-up questions."""
    session_id = req.session_id
    
    # If this is a follow-up, fetch context
    h_ctx = ""
    if session_id:
        h_ctx = await asyncio.to_thread(
            session_svc.fetch_consultant_history, req.user_id, 5, session_id
        )

    def _graph_ctx():
        graph_svc.load_graph(req.user_id)
        return graph_svc.find_context(req.user_id, req.question, top_k=12)

    g_ctx, v_ctx = await asyncio.gather(
        asyncio.to_thread(_graph_ctx),
        asyncio.to_thread(vector_svc.search_memory, req.user_id, req.question),
    )

    safe_q = sanitize_input(req.question)
    result = await brain_svc.ask_consultant(
        req.user_id, safe_q, h_ctx, g_ctx, v_ctx,
        session_summaries="", mode="standard", persona="consultant",
    )
    
    answer = result.get("answer", "")
    
    # Log the interaction if it's part of a session
    if not session_id:
        # Create a transient session for the first graph query if it's conversational
        session_id = await asyncio.to_thread(
            session_svc.create_session_record,
            req.user_id,
            title=f"Graph: {safe_q[:30]}...",
            mode="consultant",
        )
    
    await asyncio.to_thread(
        session_svc.log_consultant_qa,
        req.user_id, req.question, answer, session_id=session_id,
        model_used=result.get("model_used"),
        latency_ms=result.get("latency_ms"),
        tokens_used=result.get("tokens_used"),
    )

    return {
        "answer": answer, 
        "session_id": session_id,
        "model_used": result.get("model_used")
    }



# POST /ask_consultant_stream  (SSE streaming)
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/ask_consultant_stream")
@limiter.limit("10/minute")
async def ask_consultant_stream_endpoint(
    request: Request,
    req: ConsultantRequest,
    user: VerifiedUser = Depends(get_verified_user),
):
    """Streaming consultant using Groq's streaming API (SSE). Fully async."""
    session_id = req.session_id
    if not session_id:
        session_id = await asyncio.to_thread(
            session_svc.create_session_record,
            req.user_id,
            title=f"Consultant {datetime.now().strftime('%Y-%m-%d %H:%M')}",
            mode="consultant",
        )

    def _graph_ctx():
        graph_svc.load_graph(req.user_id)
        return graph_svc.find_context(req.user_id, req.question, top_k=10)

    meta = await session_store.get_metadata(session_id) if session_id else {}
    target_entity_id = meta.get("target_entity_id")

    def _entity_ctx():
        if target_entity_id:
            return entity_svc.get_entity_context(req.user_id, str(target_entity_id))
        return ""

    g_ctx, v_ctx, h_ctx, s_ctx, e_ctx = await asyncio.gather(
        asyncio.to_thread(_graph_ctx),
        asyncio.to_thread(vector_svc.search_memory, req.user_id, req.question),
        asyncio.to_thread(session_svc.fetch_consultant_history, req.user_id, 5, session_id),
        asyncio.to_thread(session_svc.fetch_session_summaries, req.user_id, 3),
        asyncio.to_thread(_entity_ctx),
    )

    if e_ctx:
        g_ctx = f"ROLEPLAY TARGET ENTITY CONTEXT:\n{e_ctx}\n\n" + g_ctx

    safe_question = sanitize_input(req.question)
    system_prompt = brain_svc._build_consultant_system_prompt(
        h_ctx, g_ctx, v_ctx, s_ctx, req.mode, req.persona,
    )

    await asyncio.to_thread(
        session_svc.log_message, session_id, "user", safe_question
    )

    _sid = session_id
    _uid = req.user_id
    _question = safe_question

    import time as _time

    async def _post_process_stream(
        uid: str, sid: str, question: str, full_answer: str,
        graph_ctx: str, sys_prompt: str, latency: int,
    ):
        """Run all post-stream work (logging, memory, entity extraction) in the
        background so the SSE 'done' event is not delayed by slow I/O."""
        try:
            est_prompt_tokens = brain_svc._estimate_tokens(sys_prompt + question)
            est_completion_tokens = brain_svc._estimate_tokens(full_answer)

            await asyncio.to_thread(
                session_svc.log_message,
                sid, "llm", full_answer,
                model_used=settings.CONSULTANT_MODEL,
                latency_ms=latency,
                tokens_used=est_prompt_tokens + est_completion_tokens,
            )

            from app.database import db as _db
            await asyncio.to_thread(
                lambda: _db.table("consultant_logs").insert({
                    "user_id": uid,
                    "question": question,
                    "answer": full_answer,
                    "query": question,
                    "response": full_answer,
                    "session_id": sid,
                }).execute()
            )

            await vector_svc.save_memory(
                uid, f"Q: {question}\nA: {full_answer}",
                session_id=sid,
            )
            try:
                extraction = await brain_svc.extract_all_from_transcript(
                    f"Q: {question}\nA: {full_answer}", graph_ctx
                )
                _entities = extraction.get("entities", [])
                _relations = extraction.get("relations", [])
                if _entities:
                    await asyncio.to_thread(
                        entity_svc.persist_extraction, uid,
                        {"entities": _entities, "relations": _relations}, sid,
                    )
            except Exception as _ee:
                print(f"⚠️ Consultant stream entity extraction error: {_ee}")

            await asyncio.to_thread(
                session_svc.update_session_token_usage,
                sid,
                tokens_prompt=est_prompt_tokens,
                tokens_completion=est_completion_tokens,
            )

            await asyncio.to_thread(
                audit_svc.log,
                uid, "consultant_stream_query",
                entity_type="consultant_log", entity_id=sid,
                details={"latency_ms": latency,
                         "tokens_est": est_prompt_tokens + est_completion_tokens},
            )

            fire_and_forget(gamification_svc.award_xp(
                uid, 15, "consultant_qa",
                source_id=f"stream_{sid}",
                description="Consultant streaming Q&A",
            ))
            fire_and_forget(gamification_svc.increment_quest_progress(uid, "ask_consultant", 1))
            fire_and_forget(gamification_svc.increment_quest_progress(uid, "save_memory", 1))
            fire_and_forget(gamification_svc.update_streak(uid))

            # AI-generated session title — only set it on first exchange (title still default)
            try:
                from app.database import db as _db2
                existing = await asyncio.to_thread(
                    lambda: _db2.table("sessions")
                    .select("title")
                    .eq("id", sid)
                    .maybe_single()
                    .execute()
                )
                existing_title = (existing.data or {}).get("title", "")
                is_default_title = existing_title.startswith("Consultant 20") or not existing_title
                if is_default_title:
                    generated = await brain_svc.generate_title(f"Q: {question}\nA: {full_answer}")
                    if generated:
                        await asyncio.to_thread(
                            lambda: _db2.table("sessions")
                            .update({"title": generated})
                            .eq("id", sid)
                            .execute()
                        )
            except Exception as _te:
                print(f"⚠️ Consultant title generation error: {_te}")

        except Exception as e:
            print(f"❌ Stream post-processing error: {e}")

    async def generate():
        full_response: List[str] = []
        stream_start = _time.time()
        try:
            stream = await brain_svc.aclient.chat.completions.create(
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": _question},
                ],
                model=settings.CONSULTANT_MODEL,
                temperature=0.7,
                max_tokens=800,
                stream=True,
            )
            async for chunk in stream:
                delta = (
                    chunk.choices[0].delta.content
                    if chunk.choices and chunk.choices[0].delta
                    else None
                )
                if delta:
                    full_response.append(delta)
                    yield f"data: {json.dumps({'token': delta})}\n\n"
        except asyncio.CancelledError:
            return
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

        # Send 'done' immediately — post-processing runs in the background
        # so the client animation stops as soon as tokens finish.
        yield f"data: {json.dumps({'done': True, 'session_id': _sid})}\n\n"

        stream_latency = int((_time.time() - stream_start) * 1000)
        full_answer = "".join(full_response)
        if full_answer:
            fire_and_forget(_post_process_stream(
                _uid, _sid, _question, full_answer,
                g_ctx, system_prompt, stream_latency,
            ))

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ══════════════════════════════════════════════════════════════════════════════
# POST /ask_consultant/batch
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/ask_consultant/batch")
@limiter.limit("5/minute")
async def ask_consultant_batch(
    request: Request,
    req: BatchConsultantRequest,
    user: VerifiedUser = Depends(get_verified_user),
):
    """Process multiple consultant questions concurrently (max 20)."""
    try:
        questions = validate_batch_questions(req.questions)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    async def _ask_one(q: str):
        try:
            result = await brain_svc.ask_consultant(
                req.user_id, q, "", "", "", mode=req.mode,
            )
            return {"answer": result.get("answer", ""), "session_id": None}
        except Exception as e:
            return {"error": str(e)}

    answers = await asyncio.gather(*[_ask_one(q) for q in questions])
    return {"status": "completed", "answers": list(answers)}
