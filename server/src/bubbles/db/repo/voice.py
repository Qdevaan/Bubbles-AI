"""Voice-enrolment repo (``voice_enrollments``).

One row per user holds their speaker embedding (192-dim ECAPA). Re-enrolling
replaces the row.
"""

from __future__ import annotations

from collections.abc import Sequence
from uuid import UUID

import asyncpg


def _fmt(values: Sequence[float]) -> str:
    return "[" + ",".join(f"{v:.6f}" for v in values) + "]"


async def upsert_embedding(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    embedding: Sequence[float],
    model_version: str,
) -> None:
    """Replace the user's enrolment with a fresh embedding (single writer: the worker)."""
    await conn.execute("DELETE FROM voice_enrollments WHERE user_id = $1", user_id)
    await conn.execute(
        """
        INSERT INTO voice_enrollments (user_id, embedding, samples_count, model_version)
        VALUES ($1, $2::vector, 1, $3)
        """,
        user_id,
        _fmt(embedding),
        model_version,
    )


async def get_embedding(conn: asyncpg.Connection, *, user_id: UUID) -> list[float] | None:
    """Return the user's stored embedding as a plain float list, or ``None``."""
    raw = await conn.fetchval(
        "SELECT embedding::text FROM voice_enrollments WHERE user_id = $1 ORDER BY updated_at DESC LIMIT 1",
        user_id,
    )
    if raw is None:
        return None
    text = str(raw).strip().lstrip("[").rstrip("]")
    return [float(x) for x in text.split(",")] if text else None


async def cosine_distance_to_user(
    conn: asyncpg.Connection, *, user_id: UUID, embedding: Sequence[float]
) -> float | None:
    """pgvector cosine distance (``<=>``) between ``embedding`` and the user's enrolment.

    ``None`` if the user has no enrolment. Distance is ``1 - cosine_similarity``
    in ``[0, 2]``; ~0 means same speaker.
    """
    dist = await conn.fetchval(
        """
        SELECT embedding <=> $2::vector AS d
        FROM voice_enrollments WHERE user_id = $1
        ORDER BY updated_at DESC LIMIT 1
        """,
        user_id,
        _fmt(embedding),
    )
    return float(dist) if dist is not None else None
