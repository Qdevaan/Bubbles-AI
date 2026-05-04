"""Performa service -- user context profile CRUD and AI-driven insight extraction."""

import asyncio
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from app.database import db

logger = logging.getLogger(__name__)

_TABLE = "performa"


# -- CRUD ----------------------------------------------------------------------

def get_performa(user_id: str) -> Dict[str, Any]:
    """Return the user's performa row (manual_data + ai_data). Creates empty row if absent."""
    resp = db.table(_TABLE).select("*").eq("user_id", user_id).maybe_single().execute()
    if resp.data:
        return resp.data
    # First access -- upsert empty row
    db.table(_TABLE).upsert({"user_id": user_id}).execute()
    return {"user_id": user_id, "manual_data": {}, "ai_data": {}}


def update_manual_data(user_id: str, manual_data: Dict[str, Any]) -> None:
    db.table(_TABLE).upsert({
        "user_id": user_id,
        "manual_data": manual_data,
    }).execute()


def get_pending_insights(user_id: str) -> List[Dict[str, Any]]:
    """Return AI insights awaiting approval (approved=False)."""
    row = get_performa(user_id)
    ai_data = row.get("ai_data", {})
    insights = ai_data.get("aiInsights", [])
    return [i for i in insights if not i.get("approved", True)]


def approve_insight(user_id: str, insight_id: str, approved: bool) -> None:
    """Approve or permanently reject a pending insight."""
    row = get_performa(user_id)
    ai_data = row.get("ai_data", {})
    insights = ai_data.get("aiInsights", [])
    if approved:
        for i in insights:
            if i.get("id") == insight_id:
                i["approved"] = True
                break
    else:
        insights = [i for i in insights if i.get("id") != insight_id]
    ai_data["aiInsights"] = insights
    db.table(_TABLE).update({"ai_data": ai_data}).eq("user_id", user_id).execute()


def _add_insight(user_id: str, text: str, source_session: str, confidence: float, approved: bool) -> None:
    row = get_performa(user_id)
    ai_data = row.get("ai_data", {})
    insights: List[Dict] = ai_data.get("aiInsights", [])
    # De-duplicate: skip if very similar insight already exists
    for existing in insights:
        if existing.get("text", "").lower() == text.lower():
            return
    insights.append({
        "id": str(uuid.uuid4()),
        "text": text,
        "source": source_session,
        "confidence": confidence,
        "addedAt": datetime.now(timezone.utc).isoformat(),
        "approved": approved,
    })
    ai_data["aiInsights"] = insights[-50:]  # cap at 50 total insights
    db.table(_TABLE).update({"ai_data": ai_data}).eq("user_id", user_id).execute()


# -- AI Extension --------------------------------------------------------------

async def analyze_session_for_insights(
    user_id: str,
    session_id: str,
    transcript_text: str,
    llm_client,
    model: str,
) -> None:
    """
    Post-session: scan transcript for user patterns. Silent-add minor findings;
    mark significant findings as pending approval (approved=False).
    """
    if not transcript_text.strip():
        return

    prompt = (
        "Analyze this conversation transcript. Extract insights about the FIRST speaker (the user).\n\n"
        "Return a JSON array. Each item: {\"text\": \"...\", \"type\": \"minor|significant\", \"confidence\": 0.0-1.0}\n\n"
        "MINOR: contact name mentioned, repeated keyword/topic, industry jargon used\n"
        "SIGNIFICANT: new communication goal detected, weakness pattern across multiple turns, "
        "role or industry change signal, recurring challenge\n\n"
        "Rules:\n"
        "- Max 5 insights per session\n"
        "- Only insights about the USER, not the other speaker\n"
        "- Be specific: 'Frequently uses filler words when asked about pricing' not 'needs improvement'\n"
        "- Return [] if nothing notable found\n\n"
        f"Transcript:\n{transcript_text[:3000]}"
    )

    try:
        resp = await asyncio.to_thread(
            lambda: llm_client.chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=300,
                temperature=0.3,
            )
        )
        raw = resp.choices[0].message.content.strip()
        start, end = raw.find("["), raw.rfind("]")
        if start == -1 or end == -1:
            return
        insights = json.loads(raw[start:end + 1])
    except Exception as e:
        logger.warning(f"Performa insight extraction failed for {user_id}: {e}")
        return

    for item in insights:
        text = item.get("text", "").strip()
        kind = item.get("type", "minor")
        conf = float(item.get("confidence", 0.7))
        if not text:
            continue
        approved = kind == "minor"
        await asyncio.to_thread(_add_insight, user_id, text, session_id, conf, approved)


# -- Context for Wingman -------------------------------------------------------

def build_context_block(user_id: str, max_tokens: int = 80) -> str:
    """Return the ABOUT YOU block injected into wingman system prompt."""
    try:
        row = get_performa(user_id)
        m = row.get("manual_data", {})
        parts = []
        if m.get("role"):
            company = m.get("company", "")
            parts.append(f"Role: {m['role']}" + (f" at {company}" if company else ""))
        if m.get("industry"):
            parts.append(f"Industry: {m['industry']}")
        goals = m.get("goals", [])
        if goals:
            parts.append(f"Goals: {', '.join(goals[:3])}")
        keywords = m.get("customKeywords", [])
        if keywords:
            parts.append(f"Watch for: {', '.join(keywords[:5])}")
        style = m.get("communicationStyle", "")
        if style:
            parts.append(f"Style: {style}")
        if not parts:
            return ""
        block = "ABOUT YOU:\n" + "\n".join(parts)
        return block[:max_tokens * 4]  # rough token cap: 4 chars ~= 1 token
    except Exception:
        return ""
