"""
Entity routes — entity query, graph export, deletion endpoints.
All deletions are audit-logged.
"""

import asyncio
from fastapi import APIRouter, HTTPException, Request
from app.config import settings
from app.database import db
from app.models.requests import EntityQueryRequest
from app.services import brain_svc, entity_svc, graph_svc, vector_svc, audit_svc
from app.utils.rate_limit import limiter

router = APIRouter()


@router.post("/ask_entity")
@limiter.limit("15/minute")
async def ask_entity_endpoint(request: Request, req: EntityQueryRequest):
    """AI summary of everything known about a named entity."""
    if not db:
        return {"answer": "Database unavailable.", "entity": None}
    user_id = req.user_id
    canonical = req.entity_name.strip().lower()
    try:
        ent_res = db.table("entities").select(
            "id, display_name, entity_type, description, mention_count"
        ).eq("user_id", user_id).ilike("canonical_name", f"%{canonical}%").limit(1).execute()

        if not ent_res.data:
            return {"answer": f"No info about '{req.entity_name}' yet.", "entity": None}
        entity = ent_res.data[0]
        eid = entity["id"]

        attr_res = db.table("entity_attributes").select(
            "attribute_key, attribute_value"
        ).eq("entity_id", eid).execute()
        attrs = "\n".join(f"  - {a['attribute_key']}: {a['attribute_value']}" for a in (attr_res.data or []))

        rel_res = db.table("entity_relations").select("relation, target_id").eq("source_id", eid).execute()
        rels = ""
        if rel_res.data:
            tids = list({r["target_id"] for r in rel_res.data})
            tgt = db.table("entities").select("id, display_name").in_("id", tids).execute()
            tmap = {t["id"]: t["display_name"] for t in (tgt.data or [])}
            rels = "\n".join(f"  - {r['relation']}: {tmap.get(r['target_id'], r['target_id'])}" for r in rel_res.data)

        ctx = f"Entity: {entity.get('display_name', canonical)} ({entity['entity_type']})\nMentioned: {entity.get('mention_count',0)} time(s)\n"
        if entity.get("description"): ctx += f"Description: {entity['description']}\n"
        if attrs: ctx += f"Attributes:\n{attrs}\n"
        if rels: ctx += f"Relations:\n{rels}\n"

        v_ctx = await asyncio.to_thread(vector_svc.search_memory, user_id, req.entity_name)
        prompt = f"You are Bubbles AI. Summarise what we know about '{entity.get('display_name', canonical)}' in 2-4 sentences using ONLY:\n{ctx}\nMEMORIES:\n{v_ctx}"
        try:
            comp = brain_svc.client.chat.completions.create(
                messages=[{"role": "user", "content": prompt}],
                model=settings.WINGMAN_MODEL, temperature=0.3, max_tokens=200)
            answer = comp.choices[0].message.content.strip()
        except Exception:
            answer = f"Known facts:\n{ctx}"

        # Audit log
        audit_svc.log(
            user_id, "entity_queried",
            entity_type="entity", entity_id=eid,
            details={"entity_name": req.entity_name},
        )

        return {"answer": answer, "entity": entity}
    except Exception as e:
        return {"answer": f"Error: {e}", "entity": None}


@router.get("/graph_export/{user_id}")
async def get_graph_export(user_id: str):
    """Return knowledge graph data."""
    try:
        import networkx as nx
        from networkx.readwrite import json_graph
        if user_id not in graph_svc.active_graphs:
            graph_svc.load_graph(user_id)
        return json_graph.node_link_data(graph_svc.active_graphs.get(user_id, nx.Graph()))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/entities/{entity_id}")
async def delete_entity(entity_id: str, user_id: str = None):
    if db:
        db.table("entity_attributes").delete().eq("entity_id", entity_id).execute()
        db.table("entity_relations").delete().eq("source_id", entity_id).execute()
        db.table("entity_relations").delete().eq("target_id", entity_id).execute()
        db.table("entities").delete().eq("id", entity_id).execute()

    audit_svc.log(
        user_id, "entity_deleted",
        entity_type="entity", entity_id=entity_id,
    )
    return {"status": "deleted", "entity_id": entity_id}


@router.delete("/sessions/{session_id}")
async def delete_session(session_id: str, user_id: str = None):
    if db:
        db.table("sessions").delete().eq("id", session_id).execute()

    audit_svc.log(
        user_id, "session_deleted",
        entity_type="session", entity_id=session_id,
    )
    return {"status": "deleted", "session_id": session_id}


@router.delete("/memories/{memory_id}")
async def delete_memory(memory_id: str, user_id: str = None):
    if db:
        db.table("memory").delete().eq("id", memory_id).execute()

    audit_svc.log(
        user_id, "memory_deleted",
        entity_type="memory", entity_id=memory_id,
    )
    return {"status": "deleted", "memory_id": memory_id}
