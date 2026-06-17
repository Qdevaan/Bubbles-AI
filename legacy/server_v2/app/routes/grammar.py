"""Grammar / mistake-tracker routes."""
from __future__ import annotations

import asyncio
import time
import uuid
from typing import List

from fastapi import APIRouter, Depends, Query, Request

from app.database import db
from app.models.requests import (
    CheckUserTurnRequest,
    CheckUserTurnResponse,
    MistakeOut,
)
from app.services import brain_svc, grammar_svc
from app.utils.auth_guard import VerifiedUser, get_verified_user
from app.utils.rate_limit import limiter
from app.utils.text_sanitizer import sanitize_input
from app.utils.validation import validate_transcript

router = APIRouter()


@router.post("/check_user_turn", response_model=CheckUserTurnResponse)
@limiter.limit("60/minute")
async def check_user_turn_endpoint(
    request: Request,
    req: CheckUserTurnRequest,
    user: VerifiedUser = Depends(get_verified_user),
):
    t0 = time.time()
    text = validate_transcript(sanitize_input(req.transcript))

    lt_task = grammar_svc.check(text)
    llm_task = brain_svc.check_filler_awkward(text)
    lt_res, llm_res = await asyncio.gather(
        lt_task, llm_task, return_exceptions=True,
    )

    lt_items: List[dict] = lt_res if isinstance(lt_res, list) else []
    llm_issues: List[dict] = (
        llm_res.get("issues", []) if isinstance(llm_res, dict) else []
    )

    rows = []
    for it in lt_items:
        rows.append({
            "user_id": req.user_id,
            "session_id": req.session_id,
            "rule_id": it["rule_id"],
            "category": it["category"],
            "snippet": it["snippet"],
            "suggestion": it.get("suggestion"),
            "source": "lt",
        })
    for it in llm_issues:
        rows.append({
            "user_id": req.user_id,
            "session_id": req.session_id,
            "rule_id": f"llm-{it['category']}",
            "category": it["category"],
            "snippet": it["snippet"],
            "suggestion": it.get("suggestion"),
            "source": "llm",
        })

    items: List[MistakeOut] = []
    if rows and db is not None:
        try:
            res = await asyncio.to_thread(
                lambda: db.table("user_mistakes").insert(rows).execute()
            )
            for r in (res.data or []):
                items.append(MistakeOut(
                    id=str(r["id"]),
                    category=r["category"],
                    snippet=r["snippet"],
                    suggestion=r.get("suggestion"),
                    rule_id=r["rule_id"],
                    source=r["source"],
                ))
        except Exception as e:
            print(f"⚠️ user_mistakes insert failed: {e}")
            for r in rows:
                items.append(MistakeOut(
                    id=uuid.uuid4().hex,
                    category=r["category"],
                    snippet=r["snippet"],
                    suggestion=r.get("suggestion"),
                    rule_id=r["rule_id"],
                    source=r["source"],
                ))

    by_cat: dict[str, int] = {}
    for it in items:
        by_cat[it.category] = by_cat.get(it.category, 0) + 1

    return CheckUserTurnResponse(
        count=len(items),
        by_category=by_cat,
        items=items,
        latency_ms=int((time.time() - t0) * 1000),
    )


@router.get("/user_mistakes")
@limiter.limit("60/minute")
async def list_user_mistakes(
    request: Request,
    session_id: str = Query(...),
    user: VerifiedUser = Depends(get_verified_user),
):
    """List mistakes for a session (used by analytics screen)."""
    if db is None:
        return {"items": []}
    try:
        res = await asyncio.to_thread(
            lambda: db.table("user_mistakes")
                .select("id,rule_id,category,snippet,suggestion,source,created_at")
                .eq("user_id", user.user_id)
                .eq("session_id", session_id)
                .order("created_at", desc=False)
                .execute()
        )
        return {"items": res.data or []}
    except Exception as e:
        print(f"⚠️ list_user_mistakes failed: {e}")
        return {"items": []}
