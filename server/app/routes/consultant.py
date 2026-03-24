"""
Consultant routes — blocking, streaming, and batch.
All actions record LLM metadata (tokens, latency, model, finish_reason).
"""

import asyncio
import json
from datetime import datetime
from typing import List

from fastapi import APIRouter, Request
from starlette.responses import StreamingResponse

from app.config import settings
from app.models.requests import ConsultantRequest, BatchConsultantRequest
from app.services import graph_svc, vector_svc, brain_svc, session_svc, entity_svc, audit_svc
from app.routes.sessions import SESSION_METADATA
from app.utils.rate_limit import limiter
from app.utils.text_sanitizer import sanitize_input

router = APIRouter()


# ══════════════════════════════════════════════════════════════════════════════
# POST /ask_consultant  (blocking)
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/ask_consultant")
@limiter.limit("10/minute")
async def ask_consultant_endpoint(request: Request, req: ConsultantRequest):
    """Blocking consultant Q&A using the 70B model."""
    # 0. Ensure a consultant session record exists
    session_id = req.session_id
    if not session_id:
        session_id = session_svc.create_session_record(
            req.user_id,
            title=f"Consultant {datetime.now().strftime('%Y-%m-%d %H:%M')}",
            mode="consultant",
        )

    # 1. Fetch all contexts in parallel
    def _graph_ctx():
        graph_svc.load_graph(req.user_id)
        return graph_svc.find_context(req.user_id, req.question, top_k=10)

    target_entity_id = (
        SESSION_METADATA.get(session_id, {}).get("target_entity_id") if session_id else None
    )

    def _entity_ctx():
        if target_entity_id:
            return entity_svc.get_entity_context(req.user_id, str(target_entity_id))
        return ""

    g_ctx, v_ctx, h_ctx, s_ctx, e_ctx = await asyncio.gather(
        asyncio.to_thread(_graph_ctx),
        asyncio.to_thread(vector_svc.search_memory, req.user_id, req.question),
        asyncio.to_thread(session_svc.fetch_consultant_history, req.user_id, 5),
        asyncio.to_thread(session_svc.fetch_session_summaries, req.user_id, 3),
        asyncio.to_thread(_entity_ctx),
    )

    if e_ctx:
        g_ctx = f"ROLEPLAY TARGET ENTITY CONTEXT:\n{e_ctx}\n\n" + g_ctx

    # 2. Get answer — now returns metadata dict
    safe_question = sanitize_input(req.question)
    result = brain_svc.ask_consultant(
        req.user_id, safe_question, h_ctx, g_ctx, v_ctx,
        session_summaries=s_ctx, mode=req.mode, persona=req.persona,
    )
    answer = result.get("answer", "")

    # 3. Log Q&A with full metadata
    session_svc.log_consultant_qa(
        req.user_id, req.question, answer, session_id=session_id,
        model_used=result.get("model_used"),
        latency_ms=result.get("latency_ms"),
        tokens_used=result.get("tokens_used"),
    )

    # 4. Track token usage on session
    session_svc.update_session_token_usage(
        session_id,
        tokens_prompt=result.get("tokens_prompt", 0),
        tokens_completion=result.get("tokens_completion", 0),
    )

    # 5. Save to memory + graph
    await vector_svc.save_memory(
        req.user_id, f"Q: {req.question}\nA: {answer}",
        session_id=session_id,
    )
    graph_svc.save_graph(req.user_id)

    # 6. Audit log
    audit_svc.log(
        req.user_id, "consultant_query",
        entity_type="consultant_log", entity_id=session_id,
        details={"mode": req.mode, "persona": req.persona,
                 "latency_ms": result.get("latency_ms"),
                 "tokens_used": result.get("tokens_used")},
    )

    return {"answer": answer, "session_id": session_id}


# ══════════════════════════════════════════════════════════════════════════════
# POST /ask_consultant_stream  (SSE streaming)
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/ask_consultant_stream")
@limiter.limit("10/minute")
async def ask_consultant_stream_endpoint(request: Request, req: ConsultantRequest):
    """Streaming consultant using Groq's streaming API (SSE)."""
    session_id = req.session_id
    if not session_id:
        session_id = session_svc.create_session_record(
            req.user_id,
            title=f"Consultant {datetime.now().strftime('%Y-%m-%d %H:%M')}",
            mode="consultant",
        )

    # Fetch contexts in parallel
    def _graph_ctx():
        graph_svc.load_graph(req.user_id)
        return graph_svc.find_context(req.user_id, req.question, top_k=10)

    target_entity_id = (
        SESSION_METADATA.get(session_id, {}).get("target_entity_id") if session_id else None
    )

    def _entity_ctx():
        if target_entity_id:
            return entity_svc.get_entity_context(req.user_id, str(target_entity_id))
        return ""

    g_ctx, v_ctx, h_ctx, s_ctx, e_ctx = await asyncio.gather(
        asyncio.to_thread(_graph_ctx),
        asyncio.to_thread(vector_svc.search_memory, req.user_id, req.question),
        asyncio.to_thread(session_svc.fetch_consultant_history, req.user_id, 5),
        asyncio.to_thread(session_svc.fetch_session_summaries, req.user_id, 3),
        asyncio.to_thread(_entity_ctx),
    )

    if e_ctx:
        g_ctx = f"ROLEPLAY TARGET ENTITY CONTEXT:\n{e_ctx}\n\n" + g_ctx

    safe_question = sanitize_input(req.question)
    system_prompt = brain_svc._build_consultant_system_prompt(
        h_ctx, g_ctx, v_ctx, s_ctx, req.mode, req.persona,
    )

    # Log user message immediately for Realtime
    session_svc.log_message(session_id, "user", safe_question)

    _sid = session_id
    _uid = req.user_id
    _question = safe_question

    import time as _time

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
            print(f"⚠️ Stream cancelled for session {_sid}")
            return
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

        # Post-stream: log and persist with metadata
        stream_latency = int((_time.time() - stream_start) * 1000)
        full_answer = "".join(full_response)
        if full_answer:
            try:
                # Estimate token usage for streaming (approximate)
                est_prompt_tokens = brain_svc._estimate_tokens(system_prompt + _question)
                est_completion_tokens = brain_svc._estimate_tokens(full_answer)

                session_svc.log_message(
                    _sid, "llm", full_answer,
                    model_used=settings.CONSULTANT_MODEL,
                    latency_ms=stream_latency,
                    tokens_used=est_prompt_tokens + est_completion_tokens,
                )
                from app.database import db as _db
                _db.table("consultant_logs").insert(
                    {
                        "user_id": _uid,
                        "question": _question,
                        "answer": full_answer,
                        "query": _question,
                        "response": full_answer,
                        "session_id": _sid,
                    }
                ).execute()
                await vector_svc.save_memory(
                    _uid, f"Q: {_question}\nA: {full_answer}",
                    session_id=_sid,
                )
                graph_svc.save_graph(_uid)

                # Track token usage
                session_svc.update_session_token_usage(
                    _sid,
                    tokens_prompt=est_prompt_tokens,
                    tokens_completion=est_completion_tokens,
                )

                # Audit
                audit_svc.log(
                    _uid, "consultant_stream_query",
                    entity_type="consultant_log", entity_id=_sid,
                    details={"latency_ms": stream_latency,
                             "tokens_est": est_prompt_tokens + est_completion_tokens},
                )
            except Exception as e:
                print(f"❌ Stream post-processing error: {e}")

        yield f"data: {json.dumps({'done': True, 'session_id': _sid})}\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ══════════════════════════════════════════════════════════════════════════════
# POST /ask_consultant/batch
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/ask_consultant/batch")
async def ask_consultant_batch(req: BatchConsultantRequest):
    """Process multiple consultant questions sequentially."""
    answers = []
    for q in req.questions:
        try:
            result = brain_svc.ask_consultant(
                req.user_id, q, "", "", "", mode=req.mode,
            )
            answers.append({"answer": result.get("answer", ""), "session_id": None})
        except Exception as e:
            answers.append({"error": str(e)})
    return {"status": "completed", "answers": answers}
