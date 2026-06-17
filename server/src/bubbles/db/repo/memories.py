# Purpose: Repository for rolling-summary memory rows built from session transcripts via the summarise worker.
"""Memory repo with optional pgvector similarity search.

The vector column is `vector(384)`. We accept embeddings as `list[float]`
and let pgvector parse the stringified form ``[0.1,0.2,...]``.
"""

from __future__ import annotations

from collections.abc import Sequence
from uuid import UUID

import asyncpg

from bubbles.db.models import Memory

_COLS = """
    id, user_id, session_id, content, memory_type, importance, confidence,
    source, is_pinned, is_archived, created_at, last_accessed_at, expires_at
"""


def _row(row: asyncpg.Record) -> Memory:
    return Memory(
        id=row["id"],
        user_id=row["user_id"],
        session_id=row["session_id"],
        content=row["content"],
        memory_type=row["memory_type"] or "general",
        importance=float(row["importance"] or 1.0),
        confidence=float(row["confidence"] or 1.0),
        source=row["source"] or "inferred",
        is_pinned=row["is_pinned"] or False,
        is_archived=row["is_archived"] or False,
        created_at=row["created_at"],
        last_accessed_at=row["last_accessed_at"],
        expires_at=row["expires_at"],
    )


def _format_vector(values: Sequence[float]) -> str:
    return "[" + ",".join(f"{v:.6f}" for v in values) + "]"


async def insert(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    content: str,
    memory_type: str = "general",
    embedding: Sequence[float] | None = None,
    session_id: UUID | None = None,
    importance: float = 1.0,
    confidence: float = 1.0,
    source: str = "inferred",
) -> Memory:
    embed_arg = _format_vector(embedding) if embedding is not None else None
    row = await conn.fetchrow(
        f"""
        INSERT INTO memory (
            user_id, session_id, content, memory_type, embedding,
            importance, confidence, source
        )
        VALUES ($1, $2, $3, $4, $5::vector, $6, $7, $8)
        RETURNING {_COLS}
        """,
        user_id,
        session_id,
        content,
        memory_type,
        embed_arg,
        importance,
        confidence,
        source,
    )
    assert row is not None
    return _row(row)


async def list_for_user(
    conn: asyncpg.Connection, *, user_id: UUID, limit: int = 50
) -> list[Memory]:
    rows = await conn.fetch(
        f"""
        SELECT {_COLS}
        FROM memory
        WHERE user_id = $1 AND is_archived = false
        ORDER BY is_pinned DESC, created_at DESC
        LIMIT $2
        """,
        user_id,
        limit,
    )
    return [_row(r) for r in rows]


async def get(conn: asyncpg.Connection, memory_id: UUID) -> Memory | None:
    """Fetch a memory by id regardless of its ``is_archived`` flag."""
    row = await conn.fetchrow(f"SELECT {_COLS} FROM memory WHERE id = $1", memory_id)
    return _row(row) if row is not None else None


async def similar(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    query_vector: Sequence[float],
    limit: int = 5,
) -> list[Memory]:
    """HNSW kNN search. Falls back gracefully if pgvector is missing."""
    rows = await conn.fetch(
        f"""
        SELECT {_COLS}
        FROM memory
        WHERE user_id = $1 AND is_archived = false AND embedding IS NOT NULL
        ORDER BY embedding <-> $2::vector
        LIMIT $3
        """,
        user_id,
        _format_vector(query_vector),
        limit,
    )
    return [_row(r) for r in rows]


async def soft_delete(conn: asyncpg.Connection, *, memory_id: UUID, user_id: UUID) -> bool:
    row = await conn.fetchrow(
        """
        UPDATE memory SET is_archived = true
        WHERE id = $1 AND user_id = $2 AND is_archived = false
        RETURNING id
        """,
        memory_id,
        user_id,
    )
    return row is not None
