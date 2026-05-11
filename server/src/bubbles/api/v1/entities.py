"""Entity-aware ask + graph admin routes.

``ask_entity`` first runs entity extraction on the question, looks up the
matching entities in the user's graph, and then asks the consultant model
with the entity context injected via the ``entity_aware`` template.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Query, Response

from bubbles.ai.extraction import extract_entities
from bubbles.ai.prompts.loader import render
from bubbles.ai.providers.base import ChatMessage, Role
from bubbles.api.v1._schemas import (
    EntityAnswer,
    EntityQueryRequest,
    EntitySummary,
    EntityTimelineResponse,
    GraphExportResponse,
    GraphLink,
    GraphNode,
    TimelineEvent,
    TimelineSession,
    TimelineTask,
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


@router.get("/graph_export/{user_id}", response_model=GraphExportResponse)
async def graph_export(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
    limit: int = Query(300, ge=1, le=1000),
    entity_type: str | None = Query(None, max_length=64),
    include_archived: bool = Query(False),
) -> GraphExportResponse:
    require_ownership(user, str(user_id))
    async with transaction(pool) as conn:
        ents = await entities_repo.list_for_user(
            conn, user_id=user_id, limit=limit, include_archived=include_archived
        )
        rels = await entities_repo.list_all_relations(conn, user_id=user_id)
    if entity_type is not None:
        wanted = entity_type.strip().lower()
        ents = [e for e in ents if (e.entity_type or "").lower() == wanted]
    node_ids = {e.id for e in ents}
    nodes = [
        GraphNode(
            id=e.id,
            label=e.display_name or e.canonical_name,
            type=e.entity_type,
            description=e.description,
            mention_count=e.mention_count,
            last_seen_at=e.last_seen_at,
        )
        for e in ents
    ]
    links = [
        GraphLink(source=r.source_id, target=r.target_id, relation=r.relation, strength=r.strength)
        for r in rels
        if r.source_id in node_ids and r.target_id in node_ids
    ]
    return GraphExportResponse(user_id=user_id, nodes=nodes, links=links)


@router.get("/entity_timeline/{entity_id}", response_model=EntityTimelineResponse)
async def entity_timeline(
    entity_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
    limit: int = Query(50, ge=1, le=200),
    since: datetime | None = Query(None),
) -> EntityTimelineResponse:
    async with transaction(pool) as conn:
        ent = await entities_repo.get_entity(conn, entity_id)
        if ent is None:
            raise NotFound("entity not found")
        require_ownership(user, str(ent.user_id))
        name = ent.display_name or ent.canonical_name
        sess_rows = await entities_repo.timeline(
            conn, entity_id=entity_id, user_id=ent.user_id, since=since, limit=limit
        )
        event_rows = await entities_repo.events_mentioning(conn, user_id=ent.user_id, name=name)
        task_rows = await entities_repo.tasks_mentioning(conn, user_id=ent.user_id, name=name)
    return EntityTimelineResponse(
        entity_id=entity_id,
        entity_name=name,
        sessions=[
            TimelineSession(
                session_id=r["session_id"], title=r["title"], created_at=r["created_at"]
            )
            for r in sess_rows
        ],
        events=[
            TimelineEvent(
                id=r["id"],
                title=r["title"],
                due_text=r["due_text"],
                description=r["description"],
                created_at=r["created_at"],
            )
            for r in event_rows
        ],
        tasks=[
            TimelineTask(
                id=r["id"],
                title=r["title"],
                status=r["status"],
                priority=r["priority"],
                created_at=r["created_at"],
            )
            for r in task_rows
        ],
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
