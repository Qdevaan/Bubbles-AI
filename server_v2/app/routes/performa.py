"""Performa routes -- user context profile."""

import asyncio
from typing import Any, Dict

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

from app.utils.auth_guard import get_verified_user, VerifiedUser
from app.utils.rate_limit import limiter
import app.services.performa_service as performa_svc

router = APIRouter(tags=["performa"])


class UpdatePerformaRequest(BaseModel):
    user_id: str
    manual_data: Dict[str, Any]


class ApproveInsightRequest(BaseModel):
    user_id: str
    insight_id: str
    approved: bool


@router.get("/performa/{user_id}")
@limiter.limit("30/minute")
async def get_performa(
    request: Request,
    user_id: str,
    user: VerifiedUser = Depends(get_verified_user),
):
    return await asyncio.to_thread(performa_svc.get_performa, user_id)


@router.put("/performa/{user_id}")
@limiter.limit("20/minute")
async def update_performa(
    request: Request,
    user_id: str,
    req: UpdatePerformaRequest,
    user: VerifiedUser = Depends(get_verified_user),
):
    await asyncio.to_thread(performa_svc.update_manual_data, user_id, req.manual_data)
    return {"ok": True}


@router.get("/performa/{user_id}/pending_insights")
@limiter.limit("30/minute")
async def get_pending_insights(
    request: Request,
    user_id: str,
    user: VerifiedUser = Depends(get_verified_user),
):
    insights = await asyncio.to_thread(performa_svc.get_pending_insights, user_id)
    return {"insights": insights}


@router.post("/performa/{user_id}/approve_insight")
@limiter.limit("30/minute")
async def approve_insight(
    request: Request,
    user_id: str,
    req: ApproveInsightRequest,
    user: VerifiedUser = Depends(get_verified_user),
):
    await asyncio.to_thread(performa_svc.approve_insight, user_id, req.insight_id, req.approved)
    return {"ok": True}
