"""drill_cards repo — Leitner-box spaced-repetition cards for past mistakes.

One row per ``(user_id, rule_id, category)``. ``upsert_from_mistakes`` is
the materialization entry point used by the ``materialize_drill_cards``
worker. ``apply_review`` is the SRS transition used by the review route.
"""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Final, Literal
from uuid import UUID

import asyncpg

from bubbles.db.models import DrillCard

_COLS: Final[str] = (
    "id, user_id, rule_id, category, examples, box, due_at, "
    "last_reviewed_at, correct_streak, total_reviews, total_correct, "
    "retired_at, created_at, updated_at"
)

_EXAMPLES_CAP: Final[int] = 10


@dataclass(frozen=True, slots=True)
class NewMistakeForCard:
    """An input row for ``upsert_from_mistakes``.

    Carries the data needed to either create a new card or prepend an
    example to an existing one keyed by ``(user_id, rule_id, category)``.
    """

    mistake_id: UUID
    rule_id: str
    category: str
    snippet: str
    suggestion: str | None


def _examples(raw: Any) -> list[dict[str, Any]]:
    if isinstance(raw, str):
        loaded: Any = json.loads(raw)
        return list(loaded) if isinstance(loaded, list) else []
    return list(raw) if raw else []


def _row(r: asyncpg.Record) -> DrillCard:
    return DrillCard(
        id=r["id"],
        user_id=r["user_id"],
        rule_id=r["rule_id"],
        category=r["category"],
        examples=_examples(r["examples"]),
        box=r["box"],
        due_at=r["due_at"],
        last_reviewed_at=r["last_reviewed_at"],
        correct_streak=r["correct_streak"],
        total_reviews=r["total_reviews"],
        total_correct=r["total_correct"],
        retired_at=r["retired_at"],
        created_at=r["created_at"],
        updated_at=r["updated_at"],
    )


def _example_entry(m: NewMistakeForCard, *, now: datetime) -> dict[str, Any]:
    return {
        "mistake_id": str(m.mistake_id),
        "snippet": m.snippet,
        "suggestion": m.suggestion or "",
        "created_at": now.isoformat(),
    }


async def upsert_from_mistakes(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    mistakes: Sequence[NewMistakeForCard],
) -> int:
    """Upsert one card per distinct ``(rule_id, category)`` in ``mistakes``.

    For each input row: ``INSERT ... ON CONFLICT (user_id, rule_id, category)
    DO UPDATE`` — prepend a new example entry to the JSONB ``examples``
    array, cap at the 10 newest, and bump ``updated_at``. Returns the
    number of distinct cards touched (not the count of example rows).
    """
    if not mistakes:
        return 0
    now = datetime.now(UTC)
    touched: set[tuple[str, str]] = set()
    for m in mistakes:
        entry = _example_entry(m, now=now)
        await conn.execute(
            """
            INSERT INTO drill_cards (user_id, rule_id, category, examples)
            VALUES ($1, $2, $3, $4::jsonb)
            ON CONFLICT (user_id, rule_id, category) DO UPDATE
            SET examples = (
                    SELECT jsonb_agg(e)
                    FROM (
                        SELECT e
                        FROM jsonb_array_elements(
                            ($4::jsonb) || drill_cards.examples
                        ) AS t(e)
                        LIMIT $5
                    ) AS sub
                ),
                updated_at = now()
            """,
            user_id,
            m.rule_id,
            m.category,
            json.dumps([entry]),
            _EXAMPLES_CAP,
        )
        touched.add((m.rule_id, m.category))
    return len(touched)


async def list_due(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    limit: int = 20,
    offset: int = 0,
) -> list[DrillCard]:
    rows = await conn.fetch(
        f"""
        SELECT {_COLS} FROM drill_cards
        WHERE user_id = $1
          AND retired_at IS NULL
          AND due_at <= now()
        ORDER BY due_at ASC
        LIMIT $2 OFFSET $3
        """,
        user_id,
        limit,
        offset,
    )
    return [_row(r) for r in rows]


async def count_due(conn: asyncpg.Connection, *, user_id: UUID) -> int:
    n: int | None = await conn.fetchval(
        """
        SELECT COUNT(*)::int FROM drill_cards
        WHERE user_id = $1 AND retired_at IS NULL AND due_at <= now()
        """,
        user_id,
    )
    return n or 0


async def list_upcoming(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    limit: int = 20,
) -> list[DrillCard]:
    rows = await conn.fetch(
        f"""
        SELECT {_COLS} FROM drill_cards
        WHERE user_id = $1 AND retired_at IS NULL AND due_at > now()
        ORDER BY due_at ASC
        LIMIT $2
        """,
        user_id,
        limit,
    )
    return [_row(r) for r in rows]


async def get(conn: asyncpg.Connection, *, card_id: UUID) -> DrillCard | None:
    row = await conn.fetchrow(
        f"SELECT {_COLS} FROM drill_cards WHERE id = $1", card_id
    )
    return _row(row) if row is not None else None


async def apply_review(
    conn: asyncpg.Connection,
    *,
    card_id: UUID,
    result: Literal["correct", "wrong"],
    intervals: Mapping[int, timedelta],
) -> DrillCard:
    """Atomically advance/reset the box and push ``due_at``.

    Loads the current ``box`` inside the SQL via a CTE so the box math
    happens in one round-trip. ``intervals`` is injected so the route can
    use the canonical ``BOX_INTERVALS`` and tests can substitute.
    Raises ``LookupError`` if the card does not exist.
    """
    # Compute the new_box + interval map as PostgreSQL CASE arms.
    # The 5-box table is small enough that this is cleaner than a JOIN.
    # Each interval is rendered as a literal ISO-8601 duration string
    # we cast to ``interval`` server-side.
    correct_arms = ", ".join(
        f"WHEN {from_box} THEN {min(from_box + 1, 5)}" for from_box in range(1, 6)
    )
    interval_arms = ", ".join(
        f"WHEN {b} THEN interval '{int(intervals[b].total_seconds())} seconds'"
        for b in range(1, 6)
    )
    if result == "correct":
        sql = f"""
            UPDATE drill_cards
            SET box = CASE box {correct_arms} END,
                correct_streak = correct_streak + 1,
                total_reviews = total_reviews + 1,
                total_correct = total_correct + 1,
                last_reviewed_at = now(),
                due_at = now() + (
                    CASE (CASE box {correct_arms} END)
                    {interval_arms}
                    END
                ),
                updated_at = now()
            WHERE id = $1
            RETURNING {_COLS}
        """
    else:
        sql = f"""
            UPDATE drill_cards
            SET box = 1,
                correct_streak = 0,
                total_reviews = total_reviews + 1,
                last_reviewed_at = now(),
                due_at = now() + interval '{int(intervals[1].total_seconds())} seconds',
                updated_at = now()
            WHERE id = $1
            RETURNING {_COLS}
        """
    row = await conn.fetchrow(sql, card_id)
    if row is None:
        raise LookupError(f"drill_card not found: {card_id}")
    return _row(row)


async def retire(conn: asyncpg.Connection, *, card_id: UUID) -> DrillCard | None:
    """Set ``retired_at`` once. Returns ``None`` if already retired."""
    row = await conn.fetchrow(
        f"""
        UPDATE drill_cards
        SET retired_at = now(), updated_at = now()
        WHERE id = $1 AND retired_at IS NULL
        RETURNING {_COLS}
        """,
        card_id,
    )
    return _row(row) if row is not None else None
