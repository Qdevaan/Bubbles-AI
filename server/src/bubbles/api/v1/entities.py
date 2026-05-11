"""Entity-aware ask + graph admin routes.

``ask_entity`` first runs entity extraction on the question, looks up the
matching entities in the user's graph, and then asks the consultant model
with the entity context injected via the ``entity_aware`` template.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from fastapi import APIRouter, Response

from bubbles.ai.extraction import extract_entities
from bubbles.ai.prompts.loader import render
from bubbles.ai.providers.base import ChatMessage, Role
from bubbles.api.v1._schemas import (
    EntityAnswer,
    EntityQueryRequest,
    EntitySummary,
)
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import NotFound
from bubbles.db.repo import entities as entities_repo
from bubbles.db.uow import transaction
from bubbles.deps import PoolDep, RouterDep

router = APIRouter(tags=["entities"])


async def _resolve_entities(
    pool: PoolDep,
    user_id: UUID,
    extracted: list[dict[str, Any]],
) -> list[Any]:
    """Match extracted names against the user's persisted entities."""
    if not extracted:
        return []
    async with transaction(pool) as conn:
        out = []
        for item in extracted:
            name = (item.get("canonical_name") or "").strip().lower()
            if not name:
                continue
            hits = await entities_repo.search_by_name(conn, user_id=user_id, query=name, limit=3)
            out.extend(hits)
    seen: set[UUID] = set()
    deduped = []
    for e in out:
        if e.id in seen:
            continue
        seen.add(e.id)
        deduped.append(e)
    return deduped[:8]


@router.post("/ask_entity", response_model=EntityAnswer)
async def ask_entity(
    body: EntityQueryRequest,
    user: CurrentUserDep,
    llm_router: RouterDep,
    pool: PoolDep,
) -> EntityAnswer:
    user_uuid = UUID(user.id)
    extracted_payload = await extract_entities(llm_router, body.question)
    extracted = extracted_payload.get("entities") or []
    matched = await _resolve_entities(pool, user_uuid, extracted)

    system = render(
        "consultant/entity_aware.jinja",
        entities=matched,
    )
    completion = await llm_router.complete(
        "consultant.complete",
        [
            ChatMessage(role=Role.system, content=system),
            ChatMessage(role=Role.user, content=body.question),
        ],
    )
    return EntityAnswer(
        answer=completion.text,
        entities=[
            EntitySummary(
                id=e.id,
                canonical_name=e.canonical_name,
                entity_type=e.entity_type,
                description=e.description,
            )
            for e in matched
        ],
        provider=str((completion.raw or {}).get("model", "")),
    )


@router.delete("/entities/{entity_id}", status_code=204, response_class=Response)
async def delete_entity(
    entity_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> Response:
    async with transaction(pool) as conn:
        existing = await entities_repo.get_entity(conn, entity_id)
    if existing is None:
        raise NotFound("entity not found")
    require_ownership(user, str(existing.user_id))
    async with transaction(pool) as conn:
        ok = await entities_repo.soft_delete(conn, entity_id=entity_id, user_id=UUID(user.id))
    if not ok:
        raise NotFound("entity not found")
    return Response(status_code=204)
