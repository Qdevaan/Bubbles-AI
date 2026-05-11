"""Sessions repo — straight asyncpg, no ORM."""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any
from uuid import UUID

import asyncpg

from bubbles.db.models import Session

_COLUMNS = """
    id, user_id, title, summary, session_type, mode, status, persona,
    start_time, end_time, ended_at, created_at, deleted_at,
    idempotency_key, session_context,
    is_starred, is_ephemeral, is_multiplayer
"""


def _row_to_session(row: asyncpg.Record) -> Session:
    raw_ctx = row["session_context"]
    ctx: dict[str, Any] | None
    if raw_ctx is None:
        ctx = None
    elif isinstance(raw_ctx, str):
        ctx = json.loads(raw_ctx)
    else:
        ctx = dict(raw_ctx)
    return Session(
        id=row["id"],
        user_id=row["user_id"],
        title=row["title"],
        summary=row["summary"],
        session_type=row["session_type"],
        mode=row["mode"],
        status=row["status"],
        persona=row["persona"],
        start_time=row["start_time"],
        end_time=row["end_time"],
        ended_at=row["ended_at"],
        created_at=row["created_at"],
        deleted_at=row["deleted_at"],
        idempotency_key=row["idempotency_key"],
        session_context=ctx,
        is_starred=row["is_starred"],
        is_ephemeral=row["is_ephemeral"],
        is_multiplayer=row["is_multiplayer"],
    )


async def get_by_idempotency_key(conn: asyncpg.Connection, key: str) -> UUID | None:
    row = await conn.fetchrow(
        "SELECT id FROM sessions WHERE idempotency_key = $1",
        key,
    )
    if row is None:
        return None
    out: UUID = row["id"]
    return out


async def start(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    title: str | None,
    session_type: str = "general",
    mode: str = "live_wingman",
    persona: str = "casual",
    is_ephemeral: bool = False,
    idempotency_key: str | None = None,
    session_context: dict[str, Any] | None = None,
) -> Session:
    if idempotency_key is not None:
        existing = await get_by_idempotency_key(conn, idempotency_key)
        if existing is not None:
            row = await conn.fetchrow(
                f"SELECT {_COLUMNS} FROM sessions WHERE id = $1",
                existing,
            )
            assert row is not None
            return _row_to_session(row)

    row = await conn.fetchrow(
        f"""
        INSERT INTO sessions (
            user_id, title, session_type, mode, persona,
            is_ephemeral, idempotency_key, session_context, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'active')
        RETURNING {_COLUMNS}
        """,
        user_id,
        title,
        session_type,
        mode,
        persona,
        is_ephemeral,
        idempotency_key,
        json.dumps(session_context) if session_context is not None else None,
    )
    assert row is not None
    return _row_to_session(row)


async def get(conn: asyncpg.Connection, session_id: UUID) -> Session | None:
    row = await conn.fetchrow(
        f"SELECT {_COLUMNS} FROM sessions WHERE id = $1 AND deleted_at IS NULL",
        session_id,
    )
    return _row_to_session(row) if row is not None else None


async def end(
    conn: asyncpg.Connection,
    *,
    session_id: UUID,
    summary: str | None = None,
    ended_at: datetime | None = None,
) -> Session | None:
    row = await conn.fetchrow(
        f"""
        UPDATE sessions
        SET status = 'ended',
            ended_at = COALESCE($2, NOW()),
            end_time = COALESCE(end_time, NOW()),
            summary = COALESCE($3, summary)
        WHERE id = $1 AND deleted_at IS NULL
        RETURNING {_COLUMNS}
        """,
        session_id,
        ended_at,
        summary,
    )
    return _row_to_session(row) if row is not None else None


async def list_recent(conn: asyncpg.Connection, *, user_id: UUID, limit: int = 20) -> list[Session]:
    rows = await conn.fetch(
        f"""
        SELECT {_COLUMNS}
        FROM sessions
        WHERE user_id = $1 AND deleted_at IS NULL
        ORDER BY created_at DESC
        LIMIT $2
        """,
        user_id,
        limit,
    )
    return [_row_to_session(r) for r in rows]


async def soft_delete(conn: asyncpg.Connection, *, session_id: UUID, user_id: UUID) -> bool:
    row = await conn.fetchrow(
        """
        UPDATE sessions
        SET deleted_at = NOW()
        WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
        RETURNING id
        """,
        session_id,
        user_id,
    )
    return row is not None
