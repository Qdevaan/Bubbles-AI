"""
Analytics routes — feedback, session analytics, coaching reports.
Records every action to the audit_log and uses all schema columns.
"""

import json
from datetime import datetime

from fastapi import APIRouter, HTTPException, Request

from app.config import settings
from app.database import db
from app.models.requests import FeedbackRequest
from app.services import brain_svc, session_svc, audit_svc
from app.utils.rate_limit import limiter
from app.utils.text_sanitizer import sanitize_input

router = APIRouter()


# ══════════════════════════════════════════════════════════════════════════════
# POST /save_feedback
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/save_feedback")
@limiter.limit("30/minute")
async def save_feedback(request: Request, req: FeedbackRequest):
    """Save user feedback (thumbs up/down, star rating, or text)."""
    try:
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
        result = db.table("feedback").insert(row).execute()
        feedback_id = result.data[0]["id"] if result.data else None

        # Audit log
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
        res = (
            db.table("session_analytics")
            .select("*")
            .eq("session_id", session_id)
            .maybe_single()
            .execute()
        )
        if not res.data:
            raise HTTPException(status_code=404, detail="Analytics not yet computed.")

        data = res.data

        # Dynamically compute talk-time and engagement metrics
        logs_res = (
            db.table("session_logs")
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
                    1 for w in words_list
                    if w.lower().strip(".,!?") in filler_set
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

        # Sentiment trend
        sent_res = (
            db.table("sentiment_logs")
            .select("turn_index, score, label")
            .eq("session_id", session_id)
            .order("turn_index")
            .execute()
        )
        data["sentiment_trend"] = sent_res.data or []

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
        existing = (
            db.table("coaching_reports")
            .select("*")
            .eq("session_id", session_id)
            .maybe_single()
            .execute()
        )
        if existing.data:
            return existing.data

        # Find session owner
        sess_res = (
            db.table("sessions")
            .select("user_id")
            .eq("id", session_id)
            .maybe_single()
            .execute()
        )
        if not sess_res.data:
            raise HTTPException(status_code=404, detail="Session not found.")
        user_id = sess_res.data["user_id"]

        # Get transcript
        logs_res = (
            db.table("session_logs")
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

        # Generate report via LLM
        coaching_prompt = (
            "You are an expert communication coach. Analyse this transcript. "
            'Return JSON ONLY: {"user_talk_pct":float, "others_talk_pct":float, '
            '"key_topics":[str], "key_decisions":[str], "action_items":[str], '
            '"follow_up_people":[str], "filler_words":[str], "filler_word_count":int, '
            '"tone_summary":str, "engagement_trend":"improving|stable|declining", '
            '"suggestions":[str], "strengths":[str], "report_text":str}. Max 5 items per list.'
        )
        report_data = {}
        try:
            comp = brain_svc.client.chat.completions.create(
                messages=[
                    {"role": "system", "content": coaching_prompt},
                    {"role": "user", "content": transcript[:6000]},
                ],
                model=settings.CONSULTANT_MODEL,
                response_format={"type": "json_object"},
                temperature=0.3,
                max_tokens=800,
            )
            report_data = json.loads(comp.choices[0].message.content)
        except Exception as llm_err:
            print(f"coaching_report LLM error: {llm_err}")

        allowed_keys = {
            "user_talk_pct", "others_talk_pct", "key_topics", "key_decisions",
            "action_items", "follow_up_people", "filler_words", "filler_word_count",
            "tone_summary", "engagement_trend", "suggestions", "strengths", "report_text",
        }
        report_row = {
            "session_id": session_id,
            "user_id": user_id,
            "model_used": settings.CONSULTANT_MODEL,
            "generated_at": datetime.now().isoformat(),
            **{k: v for k, v in report_data.items() if k in allowed_keys},
        }
        ins_res = db.table("coaching_reports").insert(report_row).execute()

        # Audit log
        audit_svc.log(
            user_id, "coaching_report_generated",
            entity_type="coaching_report", entity_id=session_id,
            details={"model_used": settings.CONSULTANT_MODEL},
        )

        return ins_res.data[0] if ins_res.data else report_row
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ══════════════════════════════════════════════════════════════════════════════
# Background analytics computation
# ══════════════════════════════════════════════════════════════════════════════

async def _compute_session_analytics(session_id: str, user_id: str):
    """Background task: compute aggregated per-session metrics."""
    try:
        logs_res = (
            db.table("session_logs")
            .select("role, content, sentiment_score, latency_ms")
            .eq("session_id", session_id)
            .execute()
        )
        logs = logs_res.data or []
        total_turns = len(logs)
        user_turns = sum(1 for l in logs if l.get("role") == "user")
        others_turns = sum(1 for l in logs if l.get("role") == "others")
        llm_turns = sum(1 for l in logs if l.get("role") == "llm")

        # Word counts
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

        # Duration
        sess_res = (
            db.table("sessions")
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

        # Counts
        mem_res = (
            db.table("memory")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .eq("session_id", session_id)
            .execute()
        )
        events_res = (
            db.table("events")
            .select("id", count="exact")
            .eq("session_id", session_id)
            .execute()
        )
        highlights_res = (
            db.table("highlights")
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
            "computed_at": datetime.now().isoformat(),
        }
        db.table("session_analytics").upsert(analytics_row).execute()
        print(f"📊 Analytics computed for session {session_id}")

        # Audit log
        audit_svc.log(
            user_id, "session_analytics_computed",
            entity_type="session_analytics", entity_id=session_id,
            details={"total_turns": total_turns, "user_word_count": user_word_count},
        )
    except Exception as e:
        print(f"❌ _compute_session_analytics error: {e}")
