# Purpose: Background job that pulls entities, relations, events, and tasks from a session transcript and persists them.
"""Pull entities + relations out of a session transcript and persist them."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any
from uuid import UUID

from bubbles.ai.extraction import extract_entities, prepare_transcript
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.db.repo import entities as entities_repo
from bubbles.db.uow import UnitOfWork

if TYPE_CHECKING:
    from bubbles.workers.arq_settings import WorkerCtx

log = get_logger(__name__)


def _ctx(ctx: dict[str, Any]) -> WorkerCtx:
    bub: WorkerCtx = ctx["bubbles"]
    return bub


async def run(
    ctx: dict[str, Any],
    *,
    user_id: str,
    session_id: str,
    transcript: str,
) -> dict[str, int]:
    bub = _ctx(ctx)
    try:
        prepared = await prepare_transcript(bub.ai.router, transcript)
        payload = await extract_entities(bub.ai.router, prepared)
    except UpstreamUnavailable as exc:
        log.warning("extract_knowledge_upstream", error=str(exc))
        return {"entities": 0, "relations": 0, "links": 0, "events": 0, "tasks": 0}

    raw_entities = payload.get("entities") or []
    raw_relations = payload.get("relations") or []
    raw_events = payload.get("events") or []
    raw_tasks = payload.get("tasks") or []
    user_uuid = UUID(user_id)
    session_uuid = UUID(session_id)

    entity_ids: dict[str, UUID] = {}
    saved_entities = 0
    saved_relations = 0
    saved_links = 0
    saved_events = 0
    saved_tasks = 0

    async with UnitOfWork(bub.pool) as uow:
        for item in raw_entities:
            name = (item.get("canonical_name") or "").strip().lower()
            etype = (item.get("entity_type") or "topic").strip().lower()
            if not name:
                continue
            entity = await entities_repo.upsert_entity(
                uow.conn,
                user_id=user_uuid,
                canonical_name=name,
                entity_type=etype,
                display_name=item.get("display_name"),
                aliases=list(item.get("aliases") or []),
                description=item.get("description"),
            )
            entity_ids[name] = entity.id
            saved_entities += 1
            await entities_repo.link_session_entity(
                uow.conn, session_id=session_uuid, entity_id=entity.id, user_id=user_uuid
            )
            saved_links += 1

        for rel in raw_relations:
            src_name = (rel.get("source") or "").strip().lower()
            dst_name = (rel.get("target") or "").strip().lower()
            relation = (rel.get("relation") or "").strip().lower()
            if not (src_name and dst_name and relation):
                continue
            if src_name not in entity_ids or dst_name not in entity_ids:
                continue
            await entities_repo.upsert_relation(
                uow.conn,
                user_id=user_uuid,
                source_id=entity_ids[src_name],
                target_id=entity_ids[dst_name],
                relation=relation,
            )
            saved_relations += 1

        for ev in raw_events:
            title = (ev.get("title") or "").strip()
            if not title:
                continue
            inserted = await entities_repo.insert_event(
                uow.conn,
                user_id=user_uuid,
                session_id=session_uuid,
                title=title,
                description=(ev.get("description") or None),
                due_text=(ev.get("due_text") or None),
                location=(ev.get("location") or None),
            )
            if inserted is not None:
                saved_events += 1

        for tsk in raw_tasks:
            title = (tsk.get("title") or "").strip()
            if not title:
                continue
            priority = (tsk.get("priority") or "medium").strip().lower()
            if priority not in {"low", "medium", "high"}:
                priority = "medium"
            inserted = await entities_repo.insert_task(
                uow.conn,
                user_id=user_uuid,
                session_id=session_uuid,
                title=title,
                description=(tsk.get("description") or None),
                priority=priority,
                category=(tsk.get("category") or None),
            )
            if inserted is not None:
                saved_tasks += 1

    log.info(
        "extract_knowledge_done",
        user=user_id,
        session=session_id,
        entities=saved_entities,
        relations=saved_relations,
        links=saved_links,
        events=saved_events,
        tasks=saved_tasks,
    )
    return {
        "entities": saved_entities,
        "relations": saved_relations,
        "links": saved_links,
        "events": saved_events,
        "tasks": saved_tasks,
    }
