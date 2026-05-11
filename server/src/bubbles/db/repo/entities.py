"""Entities + relations repo."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

import asyncpg

from bubbles.db.models import Entity, EntityRelation

_ENTITY_COLS = """
    id, user_id, canonical_name, display_name, entity_type, aliases,
    description, mention_count, is_archived, last_seen_at, created_at
"""

_REL_COLS = """
    id, user_id, source_id, target_id, relation, strength, created_at
"""


def _row_to_entity(row: asyncpg.Record) -> Entity:
    return Entity(
        id=row["id"],
        user_id=row["user_id"],
        canonical_name=row["canonical_name"],
        display_name=row["display_name"],
        entity_type=row["entity_type"],
        aliases=list(row["aliases"] or []),
        description=row["description"],
        mention_count=row["mention_count"] or 0,
        is_archived=row["is_archived"] or False,
        last_seen_at=row["last_seen_at"],
        created_at=row["created_at"],
    )


def _row_to_relation(row: asyncpg.Record) -> EntityRelation:
    return EntityRelation(
        id=row["id"],
        user_id=row["user_id"],
        source_id=row["source_id"],
        target_id=row["target_id"],
        relation=row["relation"],
        strength=float(row["strength"] or 1.0),
        created_at=row["created_at"],
    )


async def upsert_entity(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    canonical_name: str,
    entity_type: str,
    display_name: str | None = None,
    aliases: list[str] | None = None,
    description: str | None = None,
) -> Entity:
    row = await conn.fetchrow(
        f"""
        INSERT INTO entities (user_id, canonical_name, entity_type, display_name, aliases, description, last_seen_at, mention_count)
        VALUES ($1, $2, $3, $4, $5, $6, NOW(), 1)
        ON CONFLICT (user_id, canonical_name) DO UPDATE SET
            entity_type = COALESCE(EXCLUDED.entity_type, entities.entity_type),
            display_name = COALESCE(EXCLUDED.display_name, entities.display_name),
            aliases = COALESCE(EXCLUDED.aliases, entities.aliases),
            description = COALESCE(EXCLUDED.description, entities.description),
            last_seen_at = NOW(),
            mention_count = entities.mention_count + 1
        RETURNING {_ENTITY_COLS}
        """,
        user_id,
        canonical_name,
        entity_type,
        display_name,
        aliases or [],
        description,
    )
    assert row is not None
    return _row_to_entity(row)


async def get_entity(conn: asyncpg.Connection, entity_id: UUID) -> Entity | None:
    row = await conn.fetchrow(
        f"SELECT {_ENTITY_COLS} FROM entities WHERE id = $1",
        entity_id,
    )
    return _row_to_entity(row) if row is not None else None


async def list_for_user(
    conn: asyncpg.Connection, *, user_id: UUID, limit: int = 200
) -> list[Entity]:
    rows = await conn.fetch(
        f"""
        SELECT {_ENTITY_COLS}
        FROM entities
        WHERE user_id = $1 AND is_archived = false
        ORDER BY last_seen_at DESC NULLS LAST, mention_count DESC
        LIMIT $2
        """,
        user_id,
        limit,
    )
    return [_row_to_entity(r) for r in rows]


async def search_by_name(
    conn: asyncpg.Connection, *, user_id: UUID, query: str, limit: int = 10
) -> list[Entity]:
    rows = await conn.fetch(
        f"""
        SELECT {_ENTITY_COLS}
        FROM entities
        WHERE user_id = $1
          AND is_archived = false
          AND (canonical_name ILIKE '%' || $2 || '%' OR display_name ILIKE '%' || $2 || '%')
        ORDER BY mention_count DESC
        LIMIT $3
        """,
        user_id,
        query,
        limit,
    )
    return [_row_to_entity(r) for r in rows]


async def soft_delete(conn: asyncpg.Connection, *, entity_id: UUID, user_id: UUID) -> bool:
    row = await conn.fetchrow(
        """
        UPDATE entities SET is_archived = true
        WHERE id = $1 AND user_id = $2 AND is_archived = false
        RETURNING id
        """,
        entity_id,
        user_id,
    )
    return row is not None


async def upsert_relation(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    source_id: UUID,
    target_id: UUID,
    relation: str,
    strength: float = 1.0,
) -> EntityRelation:
    row = await conn.fetchrow(
        f"""
        INSERT INTO entity_relations (user_id, source_id, target_id, relation, strength, updated_at)
        VALUES ($1, $2, $3, $4, $5, NOW())
        ON CONFLICT (source_id, target_id, relation) DO UPDATE SET
            strength = LEAST(10.0, entity_relations.strength + EXCLUDED.strength * 0.5),
            updated_at = NOW()
        RETURNING {_REL_COLS}
        """,
        user_id,
        source_id,
        target_id,
        relation,
        strength,
    )
    assert row is not None
    return _row_to_relation(row)


async def list_relations(
    conn: asyncpg.Connection, *, user_id: UUID, entity_id: UUID
) -> list[EntityRelation]:
    rows = await conn.fetch(
        f"""
        SELECT {_REL_COLS}
        FROM entity_relations
        WHERE user_id = $1 AND (source_id = $2 OR target_id = $2)
        ORDER BY strength DESC
        """,
        user_id,
        entity_id,
    )
    return [_row_to_relation(r) for r in rows]


async def timeline(
    conn: asyncpg.Connection,
    *,
    entity_id: UUID,
    user_id: UUID,
    since: datetime | None = None,
    limit: int = 50,
) -> list[asyncpg.Record]:
    """Return raw rows joining entity mentions with sessions."""
    rows = await conn.fetch(
        """
        SELECT s.id AS session_id, s.title, s.created_at
        FROM entities e
        JOIN sessions s ON s.user_id = e.user_id
        WHERE e.id = $1
          AND e.user_id = $2
          AND ($3::timestamptz IS NULL OR s.created_at >= $3)
        ORDER BY s.created_at DESC
        LIMIT $4
        """,
        entity_id,
        user_id,
        since,
        limit,
    )
    return list(rows)
