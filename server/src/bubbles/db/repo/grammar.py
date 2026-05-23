"""User mistakes (grammar) repo."""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime
from typing import Final
from uuid import UUID

import asyncpg

from bubbles.db.models import UserMistake

VALID_SOURCES: Final[frozenset[str]] = frozenset({"lt", "llm"})

_COLS = "id, user_id, session_id, rule_id, category, snippet, suggestion, source, created_at"


def _row(row: asyncpg.Record) -> UserMistake:
    return UserMistake(
        id=row["id"],
        user_id=row["user_id"],
        session_id=row["session_id"],
        rule_id=row["rule_id"],
        category=row["category"],
        snippet=row["snippet"],
        suggestion=row["suggestion"],
        source=row["source"],
        created_at=row["created_at"],
    )


async def bulk_insert(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    session_id: UUID | None,
    mistakes: Sequence[dict[str, str]],
) -> int:
    """Insert mistakes in one round-trip via copy_records_to_table."""
    if not mistakes:
        return 0
    for m in mistakes:
        if m.get("source") not in VALID_SOURCES:
            raise ValueError(f"invalid source: {m.get('source')!r}")

    records = [
        (
            user_id,
            session_id,
            m["rule_id"],
            m["category"],
            m["snippet"],
            m.get("suggestion"),
            m["source"],
        )
        for m in mistakes
    ]
    await conn.copy_records_to_table(
        "user_mistakes",
        records=records,
        columns=[
            "user_id",
            "session_id",
            "rule_id",
            "category",
            "snippet",
            "suggestion",
            "source",
        ],
    )
    return len(records)


async def list_for_user(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    since: datetime | None = None,
    limit: int = 100,
) -> list[UserMistake]:
    rows = await conn.fetch(
        f"""
        SELECT {_COLS}
        FROM user_mistakes
        WHERE user_id = $1
          AND ($2::timestamptz IS NULL OR created_at >= $2)
        ORDER BY created_at DESC
        LIMIT $3
        """,
        user_id,
        since,
        limit,
    )
    return [_row(r) for r in rows]


async def category_counts(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    since: datetime | None = None,
) -> dict[str, int]:
    rows = await conn.fetch(
        """
        SELECT category, COUNT(*)::int AS n
        FROM user_mistakes
        WHERE user_id = $1
          AND ($2::timestamptz IS NULL OR created_at >= $2)
        GROUP BY category
        ORDER BY n DESC
        """,
        user_id,
        since,
    )
    return {r["category"]: r["n"] for r in rows}


async def list_for_session(
    conn: asyncpg.Connection, *, session_id: UUID
) -> list[UserMistake]:
    """Return every mistake row tagged with ``session_id`` (chronological)."""
    rows = await conn.fetch(
        f"""
        SELECT {_COLS}
        FROM user_mistakes
        WHERE session_id = $1
        ORDER BY created_at ASC
        """,
        session_id,
    )
    return [_row(r) for r in rows]
