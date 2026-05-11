"""
Entity routes — entity query, graph export, deletion endpoints, entity timeline.

v2 security fixes:
  - All DELETE endpoints require JWT + ownership verification.
  - Ownership is checked by reading the row's user_id from DB before deleting.

v2 additions:
  - GET /entity_timeline/{entity_id} — time-ordered history of entity mentions.
"""

import asyncio
from fastapi import APIRouter, Depends, HTTPException, Request
from app.config import settings
from app.database import db
from app.models.requests import EntityQueryRequest
from app.services import brain_svc, entity_svc, graph_svc, vector_svc, audit_svc
from app.utils.rate_limit import limiter
from app.utils.auth_guard import get_verified_user, VerifiedUser, verify_ownership

router = APIRouter()


# ══════════════════════════════════════════════════════════════════════════════
# POST /ask_entity
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/ask_entity")
@limiter.limit("15/minute")
async def ask_entity_endpoint(request: Request, req: EntityQueryRequest):
    """AI summary of everything known about a named entity."""
    if not db:
        return {"answer": "Database unavailable.", "entity": None}
    user_id = req.user_id
    canonical = req.entity_name.strip().lower()
    try:
        ent_res = await asyncio.to_thread(
            lambda: db.table("entities").select(
                "id, display_name, entity_type, description, mention_count"
            ).eq("user_id", user_id).ilike("canonical_name", f"%{canonical}%").limit(1).execute()
        )

        if not ent_res.data:
            return {"answer": f"No info about '{req.entity_name}' yet.", "entity": None}
        entity = ent_res.data[0]
        eid = entity["id"]

        attr_res = await asyncio.to_thread(
            lambda: db.table("entity_attributes").select(
                "attribute_key, attribute_value"
            ).eq("entity_id", eid).execute()
        )
        attrs = "\n".join(
            f"  - {a['attribute_key']}: {a['attribute_value']}" for a in (attr_res.data or [])
        )

        rel_res = await asyncio.to_thread(
            lambda: db.table("entity_relations").select("relation, target_id").eq("source_id", eid).execute()
        )
        rels = ""
        if rel_res.data:
            tids = list({r["target_id"] for r in rel_res.data})
            tgt = await asyncio.to_thread(
                lambda: db.table("entities").select("id, display_name").in_("id", tids).execute()
            )
            tmap = {t["id"]: t["display_name"] for t in (tgt.data or [])}
            rels = "\n".join(
                f"  - {r['relation']}: {tmap.get(r['target_id'], r['target_id'])}"
                for r in rel_res.data
            )

        ctx = (
            f"Entity: {entity.get('display_name', canonical)} ({entity['entity_type']})\n"
            f"Mentioned: {entity.get('mention_count', 0)} time(s)\n"
        )
        if entity.get("description"):
            ctx += f"Description: {entity['description']}\n"
        if attrs:
            ctx += f"Attributes:\n{attrs}\n"
        if rels:
            ctx += f"Relations:\n{rels}\n"

        v_ctx = await asyncio.to_thread(vector_svc.search_memory, user_id, req.entity_name)
        prompt = (
            f"You are Bubbles AI. Summarise what we know about "
            f"'{entity.get('display_name', canonical)}' in 2-4 sentences using ONLY:\n"
            f"{ctx}\nMEMORIES:\n{v_ctx}"
        )
        try:
            comp = await asyncio.to_thread(
                lambda: brain_svc.client.chat.completions.create(
                    messages=[{"role": "user", "content": prompt}],
                    model=settings.WINGMAN_MODEL, temperature=0.3, max_tokens=200,
                )
            )
            answer = comp.choices[0].message.content.strip()
        except Exception:
            answer = f"Known facts:\n{ctx}"

        audit_svc.log(
            user_id, "entity_queried",
            entity_type="entity", entity_id=eid,
            details={"entity_name": req.entity_name},
        )

        return {"answer": answer, "entity": entity}
    except Exception as e:
        return {"answer": f"Error: {e}", "entity": None}


# ══════════════════════════════════════════════════════════════════════════════
# GET /graph_export/{user_id}
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/graph_export/{user_id}")
async def get_graph_export(user_id: str):
    """Return knowledge graph data built from entities + entity_relations tables."""
    if not db:
        raise HTTPException(status_code=503, detail="Database unavailable.")
    try:
        # Fetch all entities for this user
        entities_res = await asyncio.to_thread(
            lambda: db.table("entities")
            .select("id, canonical_name, display_name, entity_type, description, mention_count")
            .eq("user_id", user_id)
            .eq("is_archived", False)
            .execute()
        )
        entities = entities_res.data or []

        # Fetch all relations for this user
        relations_res = await asyncio.to_thread(
            lambda: db.table("entity_relations")
            .select("id, source_id, target_id, relation, strength")
            .eq("user_id", user_id)
            .execute()
        )
        relations = relations_res.data or []

        # Build entity id set for filtering valid relations
        entity_ids = {e["id"] for e in entities}

        # Build nodes list
        nodes = []
        for e in entities:
            nodes.append({
                "id": e["id"],
                "label": e.get("display_name") or e.get("canonical_name", ""),
                "type": e.get("entity_type", ""),
                "description": e.get("description", ""),
                "mention_count": e.get("mention_count", 0),
            })

        # Build links list (only include relations where both entities exist)
        links = []
        for r in relations:
            if r["source_id"] in entity_ids and r["target_id"] in entity_ids:
                links.append({
                    "source": r["source_id"],
                    "target": r["target_id"],
                    "relation": r.get("relation", "related_to"),
                    "strength": r.get("strength", 1.0),
                })

        return {"nodes": nodes, "links": links}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GET /entity_timeline/{entity_id}  [NEW]
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/entity_timeline/{entity_id}")
@limiter.limit("20/minute")
async def get_entity_timeline(
    request: Request,
    entity_id: str,
    user_id: str,
):
    """
    Time-ordered history of sessions and events where the entity was mentioned.
    Requires ?user_id= query parameter for ownership scoping.
    """
    if not db:
        raise HTTPException(status_code=503, detail="Database unavailable.")
    try:
        # Verify the entity belongs to the requesting user
        ent_res = await asyncio.to_thread(
            lambda: db.table("entities")
            .select("id, display_name, user_id")
            .eq("id", entity_id)
            .maybe_single()
            .execute()
        )
        if not ent_res.data:
            raise HTTPException(status_code=404, detail="Entity not found.")
        if ent_res.data["user_id"] != user_id:
            raise HTTPException(status_code=403, detail="Forbidden.")

        entity_name = ent_res.data.get("display_name", "")

        # Sessions that mention this entity via session_logs
        sessions_res = await asyncio.to_thread(
            lambda: db.table("sessions")
            .select("id, title, mode, created_at, summary, status")
            .eq("user_id", user_id)
            .eq("target_entity_id", entity_id)
            .order("created_at", desc=True)
            .limit(20)
            .execute()
        )

        # Events associated with this entity
        events_res = await asyncio.to_thread(
            lambda: db.table("events")
            .select("id, title, due_text, description, created_at")
            .eq("user_id", user_id)
            .ilike("title", f"%{entity_name}%")
            .order("created_at", desc=True)
            .limit(10)
            .execute()
        )

        # Tasks associated with this entity
        tasks_res = await asyncio.to_thread(
            lambda: db.table("tasks")
            .select("id, title, status, priority, created_at")
            .eq("user_id", user_id)
            .ilike("title", f"%{entity_name}%")
            .order("created_at", desc=True)
            .limit(10)
            .execute()
        )

        return {
            "entity_id": entity_id,
            "entity_name": entity_name,
            "sessions": sessions_res.data or [],
            "events": events_res.data or [],
            "tasks": tasks_res.data or [],
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ══════════════════════════════════════════════════════════════════════════════
# DELETE /entities/{entity_id}  — requires auth + ownership
# ══════════════════════════════════════════════════════════════════════════════

@router.delete("/entities/{entity_id}")
@limiter.limit("10/minute")
async def delete_entity(
    request: Request,
    entity_id: str,
    user: VerifiedUser = Depends(get_verified_user),
):
    """Delete an entity and all its attributes/relations. Requires ownership."""
    if not db:
        raise HTTPException(status_code=503, detail="Database unavailable.")

    # Ownership check
    row = await asyncio.to_thread(
        lambda: db.table("entities")
        .select("user_id")
        .eq("id", entity_id)
        .maybe_single()
        .execute()
    )
    if not row.data:
        raise HTTPException(status_code=404, detail="Entity not found.")
    await verify_ownership(row.data["user_id"], user)

    await asyncio.to_thread(
        lambda: db.table("entity_attributes").delete().eq("entity_id", entity_id).execute()
    )
    await asyncio.to_thread(
        lambda: db.table("entity_relations").delete().eq("source_id", entity_id).execute()
    )
    await asyncio.to_thread(
        lambda: db.table("entity_relations").delete().eq("target_id", entity_id).execute()
    )
    await asyncio.to_thread(
        lambda: db.table("entities").delete().eq("id", entity_id).execute()
    )

    audit_svc.log(
        user.user_id, "entity_deleted",
        entity_type="entity", entity_id=entity_id,
    )
    return {"status": "deleted", "entity_id": entity_id}


# ══════════════════════════════════════════════════════════════════════════════
# DELETE /sessions/{session_id}  — requires auth + ownership
# ══════════════════════════════════════════════════════════════════════════════

@router.delete("/sessions/{session_id}")
@limiter.limit("10/minute")
async def delete_session(
    request: Request,
    session_id: str,
    user: VerifiedUser = Depends(get_verified_user),
):
    """Delete a session. Requires ownership."""
    if not db:
        raise HTTPException(status_code=503, detail="Database unavailable.")

    row = await asyncio.to_thread(
        lambda: db.table("sessions")
        .select("user_id")
        .eq("id", session_id)
        .maybe_single()
        .execute()
    )
    if not row.data:
        raise HTTPException(status_code=404, detail="Session not found.")
    await verify_ownership(row.data["user_id"], user)

    await asyncio.to_thread(
        lambda: db.table("sessions").delete().eq("id", session_id).execute()
    )

    audit_svc.log(
        user.user_id, "session_deleted",
        entity_type="session", entity_id=session_id,
    )
    return {"status": "deleted", "session_id": session_id}


# ══════════════════════════════════════════════════════════════════════════════
# DELETE /memories/{memory_id}  — requires auth + ownership
# ══════════════════════════════════════════════════════════════════════════════

@router.delete("/memories/{memory_id}")
@limiter.limit("10/minute")
async def delete_memory(
    request: Request,
    memory_id: str,
    user: VerifiedUser = Depends(get_verified_user),
):
    """Delete a memory entry. Requires ownership."""
    if not db:
        raise HTTPException(status_code=503, detail="Database unavailable.")

    row = await asyncio.to_thread(
        lambda: db.table("memory")
        .select("user_id")
        .eq("id", memory_id)
        .maybe_single()
        .execute()
    )
    if not row.data:
        raise HTTPException(status_code=404, detail="Memory not found.")
    await verify_ownership(row.data["user_id"], user)

    await asyncio.to_thread(
        lambda: db.table("memory").delete().eq("id", memory_id).execute()
    )

    audit_svc.log(
        user.user_id, "memory_deleted",
        entity_type="memory", entity_id=memory_id,
    )
    return {"status": "deleted", "memory_id": memory_id}
