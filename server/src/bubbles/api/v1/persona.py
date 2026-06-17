# Purpose: Persona endpoints: create, read, and update the user's Performa communication profile.
"""User persona routes."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter

from bubbles.api.v1._schemas import PersonaResponse, PersonaUpsertRequest
from bubbles.auth.current_user import CurrentUserDep
from bubbles.core.errors import NotFound
from bubbles.db.repo import personas as personas_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep

router = APIRouter(tags=["persona"])


def _to_response(row: object) -> PersonaResponse:
    return PersonaResponse.model_validate(row, from_attributes=True)


@router.get("/me/persona", response_model=PersonaResponse)
async def get_my_persona(user: CurrentUserDep, pool: PoolDep) -> PersonaResponse:
    async with transaction(pool) as conn:
        row = await personas_repo.get(conn, UUID(user.id))
    if row is None:
        raise NotFound("persona not set")
    return _to_response(row)


@router.put("/me/persona", response_model=PersonaResponse)
async def put_my_persona(
    body: PersonaUpsertRequest,
    user: CurrentUserDep,
    pool: PoolDep,
) -> PersonaResponse:
    async with UnitOfWork(pool) as uow:
        row = await personas_repo.upsert(
            uow.conn,
            user_id=UUID(user.id),
            role_primary=body.role_primary,
            native_language=body.native_language,
            learning_language=body.learning_language,
            display_name=body.display_name,
            age_range=body.age_range,
            profession_detail=body.profession_detail,
            expertise_tags=body.expertise_tags,
            proficiency_self_rated=body.proficiency_self_rated,
            formality_preference=body.formality_preference,
            communication_style=body.communication_style,
            primary_goals=body.primary_goals,
            typical_scenarios=body.typical_scenarios,
            cultural_context=body.cultural_context,
            avoid_list=body.avoid_list,
        )
    return _to_response(row)
