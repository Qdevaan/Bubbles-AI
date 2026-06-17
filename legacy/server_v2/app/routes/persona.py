"""Persona routes -- typed performa CRUD."""

import asyncio
from fastapi import APIRouter, Depends, HTTPException, Request

from app.utils.auth_guard import get_verified_user, VerifiedUser
from app.utils.rate_limit import limiter
from app.services import persona_svc, entity_svc
from app.models.persona import UserPersonaUpdate

router = APIRouter(tags=["persona"])


@router.get("/me/persona")
@limiter.limit("30/minute")
async def get_my_persona(
    request: Request,
    user: VerifiedUser = Depends(get_verified_user),
):
    persona = await asyncio.to_thread(persona_svc.get, user.user_id)
    if persona is None:
        raise HTTPException(status_code=404, detail="persona_not_found")
    return persona.model_dump(mode="json")


@router.put("/me/persona")
@limiter.limit("20/minute")
async def put_my_persona(
    request: Request,
    update: UserPersonaUpdate,
    user: VerifiedUser = Depends(get_verified_user),
):
    persona = await asyncio.to_thread(persona_svc.upsert, user.user_id, update)
    persona_svc.invalidate(user.user_id)

    # Seed / refresh the starter knowledge graph from the performa profile so
    # the Entities and Graph screens have data before the first session.
    # Best-effort: a seeding failure must never block the persona save.
    try:
        await asyncio.to_thread(entity_svc.seed_from_persona, user.user_id, persona)
    except Exception as e:  # noqa: BLE001
        print(f"⚠️ persona graph seed failed for {user.user_id}: {e}")

    return persona.model_dump(mode="json")
