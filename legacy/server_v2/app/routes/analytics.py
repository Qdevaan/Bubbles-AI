"""
Analytics routes — feedback, session analytics, coaching reports.

v2 additions:
  - Idempotency on save_feedback.
  - New endpoints: /digest/{user_id}, /communication_trends/{user_id}, /session_replay/{session_id}.
  - Async DB calls (all Supabase calls wrapped in asyncio.to_thread).
"""

import asyncio
import json
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request

from app.config import settings
from app.database import db
from app.models.requests import FeedbackRequest
from app.services import brain_svc, session_svc, audit_svc
from app.utils.rate_limit import limiter
from app.utils.text_sanitizer import sanitize_input
from app.utils.auth_guard import get_verified_user, VerifiedUser, verify_ownership

router = APIRouter()


# ══════════════════════════════════════════════════════════════════════════════
# POST /save_feedback
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/save_feedback")
@limiter.limit("30/minute")
async def save_feedback(request: Request, req: FeedbackRequest):
    """Save user feedback (thumbs up/down, star rating, or text)."""
    try:
        # Idempotency check
        if req.idempotency_key and db:
            existing = await asyncio.to_thread(
                lambda: db.table("feedback")
                .select("id")
                .eq("idempotency_key", req.idempotency_key)
                .maybe_single()
                .execute()
            )
            if existing.data:
                return {"status": "ok", "idempotent": True}

        row = {"user_id": req.user_id, "feedback_type": req.feedback_type}
        if req.session_id:
            row["session_id"] = req.session_id
        if req.session_log_id:
            row["log_id"] = req.session_log_id
        if req.consultant_log_id:
            row["consultant_log_id"] = req.consultant_log_id
        if req.value is not None:
            row["value"] = req.value
            row["rating"] = req.value
        if req.comment:
            row["comment"] = sanitize_input(req.comment, 1000)
        if req.idempotency_key:
            row["idempotency_key"] = req.idempotency_key

        result = await asyncio.to_thread(lambda: db.table("feedback").insert(row).execute())
        feedback_id = result.data[0]["id"] if result.data else None

        audit_svc.log(
            req.user_id, "feedback_submitted",
            entity_type="feedback", entity_id=feedback_id,
            details={"feedback_type": req.feedback_type, "value": req.value,
                     "session_id": req.session_id},
        )

        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GET /session_analytics/{session_id}
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/session_analytics/{session_id}")
@limiter.limit("20/minute")
async def get_session_analytics(request: Request, session_id: str):
    """Return pre-computed session analytics with dynamic talk-time metrics."""
    try:
        res = await asyncio.to_thread(
            lambda: db.table("session_analytics")
            .select("*")
            .eq("session_id", session_id)
            .maybe_single()
            .execute()
        )
        if not res.data:
            raise HTTPException(status_code=404, detail="Analytics not yet computed.")

        data = res.data

        logs_res = await asyncio.to_thread(
            lambda: db.table("session_logs")
            .select("role, content")
            .eq("session_id", session_id)
            .order("created_at")
            .execute()
        )
        logs = logs_res.data or []

        user_words = 0
        others_words = 0
        user_filler_count = 0
        longest_monologue_words = 0
        current_monologue = 0
        last_role = None

        filler_set = {"um", "uh", "like", "literally", "basically", "actually"}

        for log_entry in logs:
            role = log_entry.get("role")
            text = str(log_entry.get("content", ""))
            words_list = text.split()
            words = len(words_list)

            if role == "user":
                user_words += words
                user_filler_count += sum(
                    1 for w in words_list if w.lower().strip(".,!?") in filler_set
                )
            elif role == "others":
                others_words += words

            if role == last_role:
                current_monologue += words
            else:
                current_monologue = words
                last_role = role

            if current_monologue > longest_monologue_words:
                longest_monologue_words = current_monologue

        data["talk_time_user_seconds"] = user_words / 2.5
        data["talk_time_others_seconds"] = others_words / 2.5
        data["longest_monologue_seconds"] = longest_monologue_words / 2.5
        data["user_filler_count"] = user_filler_count

        if user_words + others_words > 0:
            ratio = min(user_words, others_words) / max(user_words, others_words)
            data["mutual_engagement_score"] = round(
                (ratio * 5) + min(len(logs) / 20.0 * 5, 5), 1
            )
        else:
            data["mutual_engagement_score"] = 0.0

        sent_res = await asyncio.to_thread(
            lambda: db.table("sentiment_logs")
            .select("turn_index, score, label")
            .eq("session_id", session_id)
            .order("turn_index")
            .execute()
        )
        data["sentiment_trend"] = sent_res.data or []

        # Enrich with session start time, summary, and fix missing duration
        try:
            sess_info = await asyncio.to_thread(
                lambda: db.table("sessions")
                .select("created_at, ended_at, summary")
                .eq("id", session_id)
                .maybe_single()
                .execute()
            )
            if sess_info.data:
                data["session_started_at"] = sess_info.data.get("created_at")
                data["session_summary"] = sess_info.data.get("summary")
                if not data.get("total_duration_seconds") and sess_info.data.get("created_at") and sess_info.data.get("ended_at"):
                    t_start = datetime.fromisoformat(sess_info.data["created_at"].replace("Z", "+00:00"))
                    t_end = datetime.fromisoformat(sess_info.data["ended_at"].replace("Z", "+00:00"))
                    data["total_duration_seconds"] = (t_end - t_start).total_seconds()
        except Exception:
            pass

        return data
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GET /coaching_report/{session_id}
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/coaching_report/{session_id}")
@limiter.limit("10/minute")
async def get_coaching_report(request: Request, session_id: str):
    """Return or generate-on-demand a coaching report for a session."""
    try:
        existing = await asyncio.to_thread(
            lambda: db.table("coaching_reports")
            .select("*")
            .eq("session_id", session_id)
            .limit(1)
            .execute()
        )
        if existing.data:
            return existing.data[0]

        sess_res = await asyncio.to_thread(
            lambda: db.table("sessions")
            .select("user_id")
            .eq("id", session_id)
            .maybe_single()
            .execute()
        )
        if not sess_res.data:
            raise HTTPException(status_code=404, detail="Session not found.")
        user_id = sess_res.data["user_id"]

        logs_res = await asyncio.to_thread(
            lambda: db.table("session_logs")
            .select("role, content")
            .eq("session_id", session_id)
            .order("created_at")
            .execute()
        )
        transcript = "\n".join(
            f"{r['role'].upper()}: {r['content']}" for r in (logs_res.data or [])
        )
        if not transcript:
            raise HTTPException(status_code=404, detail="No transcript found.")

        coaching_prompt = (
            "You are an expert communication coach. Analyse this transcript. "
            "Use gender-neutral language throughout (use 'they/their/the speaker', never he/she/his/her). "
            'Return JSON ONLY: {"user_talk_pct":float, "others_talk_pct":float, '
            '"key_topics":[str], "key_decisions":[str], "action_items":[str], '
            '"follow_up_people":[str], "filler_words":[str], "filler_word_count":int, '
            '"tone_summary":str, "engagement_trend":"improving|stable|declining", '
            '"suggestions":[str], "strengths":[str], '
            '"report_text":str (summarise what real human participants said; '
            'wrap every AI/assistant recommendation or response in [square brackets like this]), '
            '"tone_aggression":float, "tone_empathy":float, '
            '"tone_analytical":float, "tone_confidence":float, "tone_clarity":float}. '
            "Tone scores 0-10. Max 5 items per list."
        )
        report_data = {}
        try:
            comp = await asyncio.to_thread(
                lambda: brain_svc.client.chat.completions.create(
                    messages=[
                        {"role": "system", "content": coaching_prompt},
                        {"role": "user", "content": transcript[:6000]},
                    ],
                    model=settings.CONSULTANT_MODEL,
                    response_format={"type": "json_object"},
                    temperature=0.3,
                    max_tokens=800,
                )
            )
            report_data = json.loads(comp.choices[0].message.content)
        except Exception as llm_err:
            print(f"coaching_report LLM error: {llm_err}")

        db_keys = {
            "user_talk_pct", "others_talk_pct", "key_topics", "key_decisions",
            "action_items", "follow_up_people", "filler_words", "filler_word_count",
            "tone_summary", "engagement_trend", "suggestions", "strengths", "report_text",
        }
        report_row = {
            "session_id": session_id,
            "user_id": user_id,
            "model_used": settings.CONSULTANT_MODEL,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            **{k: v for k, v in report_data.items() if k in db_keys},
        }
        stored = report_row
        try:
            ins_res = await asyncio.to_thread(
                lambda: db.table("coaching_reports").insert(report_row).execute()
            )
            stored = ins_res.data[0] if ins_res.data else report_row
        except Exception as insert_err:
            print(f"coaching_report insert error: {insert_err}")

        audit_svc.log(
            user_id, "coaching_report_generated",
            entity_type="coaching_report", entity_id=session_id,
            details={"model_used": settings.CONSULTANT_MODEL},
        )

        # Merge in tone scores not stored in DB but useful for the UI
        result = dict(stored)
        for tone_key in ("tone_aggression", "tone_empathy", "tone_analytical", "tone_confidence", "tone_clarity"):
            if tone_key in report_data:
                result[tone_key] = report_data[tone_key]
        return result
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GET /session_replay/{session_id}  [NEW]
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/session_replay/{session_id}")
@limiter.limit("20/minute")
async def get_session_replay(
    request: Request,
    session_id: str,
    user: VerifiedUser = Depends(get_verified_user),
):
    """Return full ordered session transcript. Requires JWT ownership."""
    try:
        sess_res = await asyncio.to_thread(
            lambda: db.table("sessions")
            .select("user_id, title, created_at, ended_at, status, mode, summary")
            .eq("id", session_id)
            .maybe_single()
            .execute()
        )
        if not sess_res.data:
            raise HTTPException(status_code=404, detail="Session not found.")

        await verify_ownership(sess_res.data["user_id"], user)

        logs_res = await asyncio.to_thread(
            lambda: db.table("session_logs")
            .select("id, role, content, turn_index, sentiment_score, sentiment_label, speaker_label, created_at")
            .eq("session_id", session_id)
            .order("turn_index")
            .execute()
        )

        return {
            "session_id": session_id,
            "session": sess_res.data,
            "turns": logs_res.data or [],
            "total_turns": len(logs_res.data or []),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GET /digest/{user_id}  [NEW]
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/digest/{user_id}")
@limiter.limit("20/minute")
async def get_digest(
    request: Request,
    user_id: str,
    period: str = "week",
    user: VerifiedUser = Depends(get_verified_user),
):
    """
    Daily/weekly digest: recent activity summary for a user.
    ?period=day|week (default: week)
    """
    await verify_ownership(user_id, user)

    days = 7 if period != "day" else 1
    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()

    try:
        sessions_res = await asyncio.to_thread(
            lambda: db.table("sessions")
            .select("id, title, mode, status, created_at, summary")
            .eq("user_id", user_id)
            .gte("created_at", cutoff)
            .order("created_at", desc=True)
            .execute()
        )

        tasks_res = await asyncio.to_thread(
            lambda: db.table("tasks")
            .select("id, title, status, priority")
            .eq("user_id", user_id)
            .eq("status", "pending")
            .limit(10)
            .execute()
        )

        entities_res = await asyncio.to_thread(
            lambda: db.table("entities")
            .select("id, display_name, entity_type, mention_count")
            .eq("user_id", user_id)
            .order("mention_count", desc=True)
            .limit(5)
            .execute()
        )

        highlights_res = await asyncio.to_thread(
            lambda: db.table("highlights")
            .select("id, highlight_type, title, body")
            .eq("user_id", user_id)
            .gte("created_at", cutoff)
            .order("created_at", desc=True)
            .limit(5)
            .execute()
        )

        recent_sessions = sessions_res.data or []
        return {
            "period": period,
            "user_id": user_id,
            "sessions_count": len(recent_sessions),
            "recent_sessions": recent_sessions,
            "pending_tasks": tasks_res.data or [],
            "top_entities": entities_res.data or [],
            "recent_highlights": highlights_res.data or [],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GET /communication_trends/{user_id}  [NEW]
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/communication_trends/{user_id}")
@limiter.limit("10/minute")
async def get_communication_trends(
    request: Request,
    user_id: str,
    weeks: int = 8,
    user: VerifiedUser = Depends(get_verified_user),
):
    """
    Weekly aggregated communication trends: talk-time, sentiment, session count.
    ?weeks=N (default: 8)
    """
    await verify_ownership(user_id, user)

    try:
        cutoff = (datetime.now(timezone.utc) - timedelta(weeks=min(weeks, 52))).isoformat()

        analytics_res = await asyncio.to_thread(
            lambda: db.table("session_analytics")
            .select(
                "session_id, total_turns, user_word_count, assistant_word_count, "
                "avg_sentiment_score, dominant_sentiment, total_duration_seconds, computed_at"
            )
            .eq("user_id", user_id)
            .gte("computed_at", cutoff)
            .order("computed_at", desc=True)
            .execute()
        )

        rows = analytics_res.data or []

        # Group by ISO week
        weekly: dict = {}
        for row in rows:
            try:
                dt = datetime.fromisoformat(row["computed_at"].replace("Z", "+00:00"))
                week_key = dt.strftime("%Y-W%W")
            except Exception:
                continue

            if week_key not in weekly:
                weekly[week_key] = {
                    "week": week_key,
                    "sessions": 0,
                    "total_turns": 0,
                    "user_words": 0,
                    "ai_words": 0,
                    "avg_sentiment": [],
                    "total_duration_seconds": 0,
                }
            w = weekly[week_key]
            w["sessions"] += 1
            w["total_turns"] += row.get("total_turns") or 0
            w["user_words"] += row.get("user_word_count") or 0
            w["ai_words"] += row.get("assistant_word_count") or 0
            w["total_duration_seconds"] += row.get("total_duration_seconds") or 0
            if row.get("avg_sentiment_score") is not None:
                w["avg_sentiment"].append(row["avg_sentiment_score"])

        # Finalize averages
        trend_data = []
        for w in sorted(weekly.values(), key=lambda x: x["week"]):
            sentiments = w.pop("avg_sentiment")
            w["avg_sentiment_score"] = (
                round(sum(sentiments) / len(sentiments), 3) if sentiments else None
            )
            trend_data.append(w)

        return {
            "user_id": user_id,
            "weeks_requested": weeks,
            "weeks_available": len(trend_data),
            "trends": trend_data,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ══════════════════════════════════════════════════════════════════════════════
# Background analytics computation
# ══════════════════════════════════════════════════════════════════════════════

async def _compute_session_analytics(session_id: str, user_id: str):
    """Background task: compute aggregated per-session metrics."""
    try:
        logs_res = await asyncio.to_thread(
            lambda: db.table("session_logs")
            .select("role, content, sentiment_score, latency_ms")
            .eq("session_id", session_id)
            .execute()
        )
        logs = logs_res.data or []
        total_turns = len(logs)
        user_turns = sum(1 for l in logs if l.get("role") == "user")
        others_turns = sum(1 for l in logs if l.get("role") == "others")
        llm_turns = sum(1 for l in logs if l.get("role") == "llm")

        user_word_count = 0
        assistant_word_count = 0
        for l in logs:
            content = str(l.get("content", ""))
            wc = len(content.split())
            if l.get("role") == "user":
                user_word_count += wc
            elif l.get("role") in ("llm", "assistant"):
                assistant_word_count += wc

        latencies = [
            l["latency_ms"]
            for l in logs
            if l.get("role") == "llm" and l.get("latency_ms")
        ]
        avg_latency = sum(latencies) / len(latencies) if latencies else None

        sentiments = [
            l["sentiment_score"]
            for l in logs
            if l.get("sentiment_score") is not None
        ]
        avg_sentiment = sum(sentiments) / len(sentiments) if sentiments else None
        dominant_sentiment = None
        if avg_sentiment is not None:
            if avg_sentiment >= 0.1:
                dominant_sentiment = "positive"
            elif avg_sentiment <= -0.1:
                dominant_sentiment = "negative"
            else:
                dominant_sentiment = "neutral"

        sess_res = await asyncio.to_thread(
            lambda: db.table("sessions")
            .select("created_at, ended_at")
            .eq("id", session_id)
            .maybe_single()
            .execute()
        )
        total_duration = None
        if sess_res.data and sess_res.data.get("ended_at"):
            try:
                from dateutil import parser as dtparser
                t_start = dtparser.parse(sess_res.data["created_at"])
                t_end = dtparser.parse(sess_res.data["ended_at"])
                total_duration = (t_end - t_start).total_seconds()
            except Exception:
                pass

        mem_res = await asyncio.to_thread(
            lambda: db.table("memory")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .eq("session_id", session_id)
            .execute()
        )
        events_res = await asyncio.to_thread(
            lambda: db.table("events")
            .select("id", count="exact")
            .eq("session_id", session_id)
            .execute()
        )
        highlights_res = await asyncio.to_thread(
            lambda: db.table("highlights")
            .select("id", count="exact")
            .eq("session_id", session_id)
            .execute()
        )

        analytics_row = {
            "session_id": session_id,
            "user_id": user_id,
            "total_turns": total_turns,
            "user_turns": user_turns,
            "others_turns": others_turns,
            "llm_turns": llm_turns,
            "user_word_count": user_word_count,
            "assistant_word_count": assistant_word_count,
            "average_latency_ms": int(avg_latency) if avg_latency else None,
            "avg_advice_latency_ms": avg_latency,
            "total_duration_seconds": total_duration,
            "memories_saved": mem_res.count or 0,
            "events_extracted": events_res.count or 0,
            "highlights_created": highlights_res.count or 0,
            "avg_sentiment_score": avg_sentiment,
            "dominant_sentiment": dominant_sentiment,
            "computed_at": datetime.now(timezone.utc).isoformat(),
        }
        await asyncio.to_thread(
            lambda: db.table("session_analytics").upsert(analytics_row).execute()
        )
        print(f"📊 Analytics computed for session {session_id}")

        audit_svc.log(
            user_id, "session_analytics_computed",
            entity_type="session_analytics", entity_id=session_id,
            details={"total_turns": total_turns, "user_word_count": user_word_count},
        )
    except Exception as e:
        print(f"❌ _compute_session_analytics error: {e}")
