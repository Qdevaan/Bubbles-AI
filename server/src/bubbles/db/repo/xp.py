"""xp_transactions repo: append-only XP ledger with source dedup."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

import asyncpg

from bubbles.db.models import XpTransaction

_COLS = "id, user_id, amount, source_type, source_id, description, created_at"


def _row(row: asyncpg.Record) -> XpTransaction:
    return XpTransaction(
        id=row["id"],
        user_id=row["user_id"],
        amount=row["amount"],
        source_type=row["source_type"],
        source_id=row["source_id"],
        description=row["description"],
        created_at=row["created_at"],
    )


async def record(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    amount: int,
    source_type: str,
    source_id: str | None = None,
    description: str | None = None,
) -> XpTransaction | None:
    """Append an XP-award row.

    Returns ``None`` when a row with the same ``(user_id, source_type, source_id)``
    already exists (idempotent re-award). The dedup unique index only covers
    rows where ``source_id IS NOT NULL`` (partial index
    ``idx_xp_transactions_dedup``), so a ``None`` ``source_id`` always inserts.
    The ``WHERE source_id IS NOT NULL`` predicate in the ``ON CONFLICT`` clause
    must match the partial index's predicate — PostgreSQL requires this to use a
    partial index as an ``ON CONFLICT`` arbiter. ``amount`` must be non-negative
    — XP *spend* is tracked separately via ``user_gamification.xp_spent``.
    """
    if amount < 0:
        raise ValueError("amount must be non-negative")
    row = await conn.fetchrow(
        f"""
        INSERT INTO xp_transactions (user_id, amount, source_type, source_id, description)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (user_id, source_type, source_id) WHERE source_id IS NOT NULL DO NOTHING
        RETURNING {_COLS}
        """,
        user_id,
        amount,
        source_type,
        source_id,
        description,
    )
    return _row(row) if row is not None else None


async def recent(
    conn: asyncpg.Connection, *, user_id: UUID, limit: int = 20
) -> list[XpTransaction]:
    rows = await conn.fetch(
        f"SELECT {_COLS} FROM xp_transactions WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2",
        user_id,
        limit,
    )
    return [_row(r) for r in rows]


async def sum_since(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    since: datetime,
    exclude_source_types: frozenset[str] = frozenset(),
) -> int:
    """Sum positive XP awarded to ``user_id`` since ``since``.

    ``exclude_source_types`` lets the daily-cap check ignore exempt sources
    (quests, achievements, streak milestones) so they neither consume the cap
    nor are limited by it.
    """
    val: int | None = await conn.fetchval(
        """
        SELECT COALESCE(SUM(amount), 0)::int
        FROM xp_transactions
        WHERE user_id = $1 AND amount > 0 AND created_at >= $2
          AND ($3::text[] = '{}' OR source_type <> ALL($3::text[]))
        """,
        user_id,
        since,
        list(exclude_source_types),
    )
    return val or 0
