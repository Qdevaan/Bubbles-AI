"""Feedback repo — user thumbs/star/text feedback rows."""

from __future__ import annotations

from uuid import UUID

import asyncpg

from bubbles.db.models import Feedback

_COLS = (
    "id, user_id, session_id, log_id, consultant_log_id, "
    "feedback_type, rating, value, comment, idempotency_key, created_at"
)


def _row(row: asyncpg.Record) -> Feedback:
    return Feedback(
        id=row["id"],
        user_id=row["user_id"],
        session_id=row["session_id"],
        log_id=row["log_id"],
        consultant_log_id=row["consultant_log_id"],
        feedback_type=row["feedback_type"],
        rating=row["rating"],
        value=row["value"],
        comment=row["comment"],
        idempotency_key=row["idempotency_key"],
        created_at=row["created_at"],
    )


async def find_by_idempotency_key(conn: asyncpg.Connection, *, key: str) -> UUID | None:
    row = await conn.fetchrow("SELECT id FROM feedback WHERE idempotency_key = $1", key)
    if row is None:
        return None
    out: UUID = row["id"]
    return out


async def insert(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    feedback_type: str,
    session_id: UUID | None = None,
    log_id: UUID | None = None,
    consultant_log_id: UUID | None = None,
    value: int | None = None,
    rating: int | None = None,
    comment: str | None = None,
    idempotency_key: str | None = None,
) -> Feedback:
    row = await conn.fetchrow(
        f"""
        INSERT INTO feedback (
            user_id, session_id, log_id, consultant_log_id,
            feedback_type, rating, value, comment, idempotency_key
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING {_COLS}
        """,
        user_id,
        session_id,
        log_id,
        consultant_log_id,
        feedback_type,
        rating,
        value,
        comment,
        idempotency_key,
    )
    assert row is not None
    return _row(row)
