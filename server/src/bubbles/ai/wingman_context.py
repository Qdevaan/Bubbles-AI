"""Shared context builders for the wingman advice + suggestion endpoints.

Both ``process_transcript_wingman`` and ``suggest_reply`` need the same
slow-path information for the system prompt: memories similar to the
transcript, entities the user knows, the relations between them, the
user persona, the per-meeting scenario, and (for roleplay) the entity
the user is talking to. Everything in here is hard time-capped and
``never raises`` — a failure degrades the prompt, not the response.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any
from uuid import UUID

from bubbles.ai.prompts.loader import (
    render_persona_block,
    render_scenario_header,
)
from bubbles.core.logging import get_logger
from bubbles.db.repo import entities as entities_repo
from bubbles.db.repo import memories as memories_repo
from bubbles.db.repo import personas as personas_repo
from bubbles.db.repo import sessions as sessions_repo
from bubbles.db.uow import transaction

if TYPE_CHECKING:
    import asyncpg

    from bubbles.ai.embeddings import EmbeddingService

log = get_logger(__name__)

CONTEXT_BUDGET_S = 0.5


@dataclass(frozen=True, slots=True)
class WingmanContext:
    """Everything needed to render an advice / suggestion prompt."""

    memory_context: str = ""
    entity_context: str = ""
    graph_facts: str = ""
    persona_block: str = ""
    scenario_block: str = ""
    entity_block: str = ""  # roleplay-only embodiment context
    is_roleplay: bool = False


async def build(
    pool: asyncpg.Pool,
    embeddings: EmbeddingService,
    *,
    user_id: UUID,
    transcript: str,
    session_id: UUID | None = None,
    mode: str = "live_wingman",
    target_entity_id: UUID | None = None,
    budget_s: float = CONTEXT_BUDGET_S,
) -> WingmanContext:
    """Gather wingman prompt context; never raises, hard-capped at ``budget_s``."""
    is_roleplay = mode == "roleplay"
    try:
        return await asyncio.wait_for(
            _build_inner(
                pool,
                embeddings,
                user_id=user_id,
                transcript=transcript,
                session_id=session_id,
                target_entity_id=target_entity_id,
                is_roleplay=is_roleplay,
            ),
            timeout=budget_s,
        )
    except Exception as exc:  # asyncio.TimeoutError or anything inside
        log.info("wingman_context_skipped", error=str(exc))
        return WingmanContext(is_roleplay=is_roleplay)


async def _build_inner(
    pool: asyncpg.Pool,
    embeddings: EmbeddingService,
    *,
    user_id: UUID,
    transcript: str,
    session_id: UUID | None,
    target_entity_id: UUID | None,
    is_roleplay: bool,
) -> WingmanContext:
    async with transaction(pool) as conn:
        # Memories (similar via embedding, fall back to recent).
        try:
            vec = await embeddings.embed(transcript)
            mems = await memories_repo.similar(
                conn, user_id=user_id, query_vector=vec, limit=5
            )
        except Exception:
            mems = await memories_repo.list_for_user(conn, user_id=user_id, limit=5)
        memory_context = "\n".join(
            f"- {m.content.strip()}" for m in mems if m.content.strip()
        )

        # Entities the user already knows.
        ents = await entities_repo.list_for_user(conn, user_id=user_id, limit=8)
        entity_context = "\n".join(
            f"- {e.display_name or e.canonical_name} ({e.entity_type})" for e in ents
        )

        # Graph relations — walk relations of entities whose names appear in
        # the transcript. Cheap heuristic; the legacy contact-graph cache used
        # the same name-match trick.
        graph_facts = await _graph_facts(
            conn, user_id=user_id, transcript=transcript, candidates=ents
        )

        # Persona profile + per-meeting scenario.
        persona = await personas_repo.get(conn, user_id)
        persona_dict = _persona_to_dict(persona)
        persona_block = render_persona_block(persona_dict) if persona_dict else ""

        scenario_ctx: dict[str, Any] | None = None
        if session_id is not None:
            sess = await sessions_repo.get(conn, session_id)
            if sess is not None and sess.session_context:
                scenario_ctx = sess.session_context
        scenario_block = render_scenario_header(scenario_ctx)

        # Roleplay embodiment block — pull target entity attributes + relations.
        entity_block = ""
        if is_roleplay and target_entity_id is not None:
            entity_block = await _entity_block(
                conn, user_id=user_id, entity_id=target_entity_id
            )

    return WingmanContext(
        memory_context=memory_context,
        entity_context=entity_context,
        graph_facts=graph_facts,
        persona_block=persona_block,
        scenario_block=scenario_block,
        entity_block=entity_block,
        is_roleplay=is_roleplay,
    )


def _persona_to_dict(persona: object | None) -> dict[str, Any] | None:
    """Convert a ``UserPersona`` dataclass to the dict that personas jinja expects."""
    if persona is None:
        return None
    return {
        "display_name": getattr(persona, "display_name", None),
        "role_family": getattr(persona, "role_family", "default"),
        "role_primary": getattr(persona, "role_primary", ""),
        "native_language": getattr(persona, "native_language", "en"),
        "learning_language": getattr(persona, "learning_language", "en"),
        "formality_preference": getattr(persona, "formality_preference", "neutral"),
        "communication_style": list(getattr(persona, "communication_style", []) or []),
        "primary_goals": list(getattr(persona, "primary_goals", []) or []),
        "typical_scenarios": list(getattr(persona, "typical_scenarios", []) or []),
        "cultural_context": getattr(persona, "cultural_context", None),
        "avoid_list": getattr(persona, "avoid_list", None),
        "expertise_tags": list(getattr(persona, "expertise_tags", []) or []),
        "profession_detail": getattr(persona, "profession_detail", None),
    }


async def _graph_facts(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    transcript: str,
    candidates: list[Any],
) -> str:
    """Walk entity_relations for any candidate whose name appears in transcript."""
    if not candidates:
        return ""
    t = transcript.lower()
    matched = [
        e for e in candidates
        if (e.canonical_name or "").lower() in t
        or ((e.display_name or "").lower() in t and e.display_name)
    ]
    if not matched:
        return ""
    lines: list[str] = []
    for ent in matched[:3]:
        rels = await entities_repo.list_relations(
            conn, user_id=user_id, entity_id=ent.id
        )
        if not rels:
            continue
        # Resolve target/source names for human-readable lines.
        for rel in rels[:5]:
            other_id = rel.target_id if rel.source_id == ent.id else rel.source_id
            other = await entities_repo.get_entity(conn, other_id)
            other_name = (other.display_name or other.canonical_name) if other else "?"
            label = ent.display_name or ent.canonical_name
            if rel.source_id == ent.id:
                lines.append(f"- {label} → {rel.relation} → {other_name}")
            else:
                lines.append(f"- {other_name} → {rel.relation} → {label}")
    return "\n".join(lines)


async def _entity_block(
    conn: asyncpg.Connection, *, user_id: UUID, entity_id: UUID
) -> str:
    ent = await entities_repo.get_entity(conn, entity_id)
    if ent is None or ent.user_id != user_id:
        return ""
    label = ent.display_name or ent.canonical_name
    parts = [f"You are {label}, a {ent.entity_type}."]
    if ent.description:
        parts.append(ent.description.strip())
    if ent.aliases:
        parts.append(f"Also known as: {', '.join(ent.aliases)}.")
    rels = await entities_repo.list_relations(conn, user_id=user_id, entity_id=entity_id)
    rel_lines: list[str] = []
    for rel in rels[:10]:
        other_id = rel.target_id if rel.source_id == entity_id else rel.source_id
        other = await entities_repo.get_entity(conn, other_id)
        other_name = (other.display_name or other.canonical_name) if other else "?"
        if rel.source_id == entity_id:
            rel_lines.append(f"- {rel.relation} {other_name}")
        else:
            rel_lines.append(f"- {other_name} {rel.relation} you")
    if rel_lines:
        parts.append("Relationships:\n" + "\n".join(rel_lines))
    return "\n".join(parts)
