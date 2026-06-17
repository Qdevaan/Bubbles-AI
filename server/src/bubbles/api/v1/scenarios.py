# Purpose: Scenario endpoints: list generated roleplay scenarios, start a scenario session, and submit scores.
"""Personalized roleplay scenario routes.

Scenarios are generated from the user's knowledge graph (see
``bubbles.ai.scenarios``). The feed is topped up by the ``generate_scenarios``
worker; ``POST /scenarios/generate`` is the synchronous on-demand path.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Query

from bubbles.ai import scenarios as scenario_gen
from bubbles.api.v1._schemas import (
    GenerateScenarioRequest,
    ScenarioOut,
    StartScenarioResponse,
)
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import Conflict, NotFound, RateLimited, UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.db.repo import entities as entities_repo
from bubbles.db.repo import scenarios as scenarios_repo
from bubbles.db.repo import sessions as sessions_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep, RateLimiterDep, RouterDep

log = get_logger(__name__)
router = APIRouter(tags=["scenarios"])

_GENERATE_CAPACITY = 10
_GENERATE_REFILL_PER_S = 10 / 60  # ~10 generations per minute


def _to_out(s: object) -> ScenarioOut:
    return ScenarioOut.model_validate(s, from_attributes=True)


@router.get("/scenarios", response_model=list[ScenarioOut])
async def list_scenarios(
    user: CurrentUserDep,
    pool: PoolDep,
    status: str = Query("suggested", pattern="^(suggested|started|completed|dismissed)$"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> list[ScenarioOut]:
    async with transaction(pool) as conn:
        rows = await scenarios_repo.list_for_user(
            conn, user_id=UUID(user.id), status=status, limit=limit, offset=offset
        )
    return [_to_out(r) for r in rows]


@router.post("/scenarios/generate", response_model=ScenarioOut, status_code=201)
async def generate_scenario(
    body: GenerateScenarioRequest,
    user: CurrentUserDep,
    pool: PoolDep,
    llm_router: RouterDep,
    limiter: RateLimiterDep,
) -> ScenarioOut:
    rl = await limiter.check(
        f"scenarios:generate:{user.id}",
        capacity=_GENERATE_CAPACITY,
        refill_per_s=_GENERATE_REFILL_PER_S,
    )
    if not rl.allowed:
        raise RateLimited(rl.retry_after_s)

    user_uuid = UUID(user.id)
    async with transaction(pool) as conn:
        entity = await entities_repo.get_entity(conn, body.target_entity_id)
    if entity is None:
        raise NotFound("entity not found")
    require_ownership(user, str(entity.user_id))

    async with transaction(pool) as conn:
        drafts = await scenario_gen.generate(
            conn,
            llm_router,
            user_id=user_uuid,
            count=1,
            target_entity_id=body.target_entity_id,
        )
    if not drafts:
        raise UpstreamUnavailable("could not generate a scenario — try again")

    async with UnitOfWork(pool) as uow:
        created = await scenarios_repo.create_many(uow.conn, user_id=user_uuid, rows=drafts)
    return _to_out(created[0])


@router.post("/scenarios/{scenario_id}/start", response_model=StartScenarioResponse)
async def start_scenario(
    scenario_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> StartScenarioResponse:
    async with transaction(pool) as conn:
        scenario = await scenarios_repo.get(conn, scenario_id)
    if scenario is None:
        raise NotFound("scenario not found")
    require_ownership(user, str(scenario.user_id))
    if scenario.status != "suggested":
        raise Conflict("scenario is not startable")

    session_context = {
        "scenario": scenario.situation,
        "role_mode": scenario.role_mode,
        "notes": scenario.goal,
        "opening_line": scenario.opening_line,
    }
    async with UnitOfWork(pool) as uow:
        session = await sessions_repo.start(
            uow.conn,
            user_id=UUID(user.id),
            title=scenario.title,
            mode="roleplay",
            session_context=session_context,
        )
        started = await scenarios_repo.mark_started(
            uow.conn, scenario_id=scenario_id, session_id=session.id
        )
    if started is None:
        raise Conflict("scenario is not startable")
    return StartScenarioResponse(session_id=session.id, scenario=_to_out(started))


@router.post("/scenarios/{scenario_id}/dismiss", response_model=ScenarioOut)
async def dismiss_scenario(
    scenario_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> ScenarioOut:
    async with transaction(pool) as conn:
        scenario = await scenarios_repo.get(conn, scenario_id)
    if scenario is None:
        raise NotFound("scenario not found")
    require_ownership(user, str(scenario.user_id))
    async with UnitOfWork(pool) as uow:
        dismissed = await scenarios_repo.mark_dismissed(uow.conn, scenario_id=scenario_id)
    if dismissed is None:
        raise Conflict("scenario cannot be dismissed")
    return _to_out(dismissed)
