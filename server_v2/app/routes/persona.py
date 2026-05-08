"""Persona routes -- typed performa CRUD."""

import asyncio
from fastapi import APIRouter, Body, Depends, HTTPException, Request
from pydantic import ValidationError

from app.utils.auth_guard import get_verified_user, VerifiedUser
from app.utils.rate_limit import limiter
from app.services import persona_svc
from app.models.persona import UserPersonaUpdate

router = APIRouter(tags=["persona"])


@router.get("/me/persona")
@limiter.limit("30/minute")
async def get_my_persona(
    request: Request,
    user: VerifiedUser = Depends(get_verified_user),
):
    persona = await asyncio.to_thread(persona_svc.get, user.id)
    if persona is None:
        raise HTTPException(status_code=404, detail="persona_not_found")
    return persona.model_dump(mode="json")


@router.put("/me/persona")
@limiter.limit("20/minute")
async def put_my_persona(
    request: Request,
    payload: dict = Body(...),
    user: VerifiedUser = Depends(get_verified_user),
):
    # Validate manually so invalid fields surface as 422 (not the project-wide
    # 400 RequestValidationError handler).
    try:
        update = UserPersonaUpdate.model_validate(payload)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors())

    persona = await asyncio.to_thread(persona_svc.upsert, user.id, update)
    persona_svc.invalidate(user.id)
    return persona.model_dump(mode="json")
