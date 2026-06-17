# Purpose: Repository for per-turn session log rows used by analytics and rolling-summarize workers.
"""Per-turn conversation log repo (``session_logs``)."""

from __future__ import annotations

from typing import Any, Final
from uuid import UUID

import asyncpg

from bubbles.db.models import SessionLog

VALID_ROLES: Final[frozenset[str]] = frozenset({"user", "others", "llm"})

# How a stored role renders in an assembled transcript line.
_ROLE_LABEL: Final[dict[str, str]] = {"user": "User", "others": "Others", "llm": "AI"}

_COLS: Final[str] = (
    "id, session_id, turn_index, role, content, speaker_label, confidence, "
    "model_used, latency_ms, tokens_used, finish_reason, has_error, error_message, "
    "sentiment_score, sentiment_label, created_at"
)


def _row(r: asyncpg.Record) -> SessionLog:
    return SessionLog(
        id=r["id"],
        session_id=r["session_id"],
        turn_index=r["turn_index"],
        role=r["role"],
        content=r["content"],
        speaker_label=r["speaker_label"],
        confidence=float(r["confidence"]) if r["confidence"] is not None else None,
        model_used=r["model_used"],
        latency_ms=r["latency_ms"],
        tokens_used=r["tokens_used"],
        finish_reason=r["finish_reason"],
        has_error=bool(r["has_error"]),
        error_message=r["error_message"],
        sentiment_score=float(r["sentiment_score"]) if r["sentiment_score"] is not None else None,
        sentiment_label=r["sentiment_label"],
        created_at=r["created_at"],
    )


async def append(
    conn: asyncpg.Connection,
    *,
    session_id: UUID,
    role: str,
    content: str,
    speaker_label: str | None = None,
    confidence: float | None = None,
    model_used: str | None = None,
    latency_ms: int | None = None,
    tokens_used: int | None = None,
    finish_reason: str | None = None,
    has_error: bool = False,
    error_message: str | None = None,
) -> SessionLog:
    """Append a turn; ``turn_index`` is assigned server-side (max+1 for the session).

    Run inside a transaction when ordering matters under concurrency — the
    ``SELECT max(turn_index)`` and the ``INSERT`` are one statement, but two
    racing appends can still pick the same index without a row lock. For our
    workload (one writer per session) that's acceptable.
    """
    if role not in VALID_ROLES:
        raise ValueError(f"invalid role: {role!r}")
    row = await conn.fetchrow(
        f"""
        INSERT INTO session_logs (
            session_id, turn_index, role, content, speaker_label, confidence,
            model_used, latency_ms, tokens_used, finish_reason, has_error, error_message
        )
        VALUES (
            $1,
            (SELECT COALESCE(MAX(turn_index) + 1, 0) FROM session_logs WHERE session_id = $1),
            $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
        )
        RETURNING {_COLS}
        """,
        session_id,
        role,
        content,
        speaker_label,
        confidence,
        model_used,
        latency_ms,
        tokens_used,
        finish_reason,
        has_error,
        error_message,
    )
    assert row is not None
    return _row(row)


async def list_for_session(
    conn: asyncpg.Connection,
    *,
    session_id: UUID,
    limit: int = 500,
    offset: int = 0,
) -> list[SessionLog]:
    rows = await conn.fetch(
        f"""
        SELECT {_COLS}
        FROM session_logs
        WHERE session_id = $1
        ORDER BY turn_index ASC
        LIMIT $2 OFFSET $3
        """,
        session_id,
        limit,
        offset,
    )
    return [_row(r) for r in rows]


async def turn_count(conn: asyncpg.Connection, *, session_id: UUID) -> int:
    n: int | None = await conn.fetchval(
        "SELECT COUNT(*)::int FROM session_logs WHERE session_id = $1",
        session_id,
    )
    return n or 0


async def role_count(conn: asyncpg.Connection, *, session_id: UUID, role: str) -> int:
    n: int | None = await conn.fetchval(
        "SELECT COUNT(*)::int FROM session_logs WHERE session_id = $1 AND role = $2",
        session_id,
        role,
    )
    return n or 0


async def turns_for_analytics(
    conn: asyncpg.Connection, *, session_id: UUID
) -> list[asyncpg.Record]:
    """role / latency_ms / sentiment_score / sentiment_label, ordered by turn_index."""
    return list(
        await conn.fetch(
            """
            SELECT turn_index, role, latency_ms, sentiment_score, sentiment_label
            FROM session_logs WHERE session_id = $1 ORDER BY turn_index ASC
            """,
            session_id,
        )
    )


async def unscored_turns(
    conn: asyncpg.Connection, *, session_id: UUID, limit: int = 200
) -> list[asyncpg.Record]:
    """User/others turns that don't have a sentiment score yet (LLM turns excluded)."""
    return list(
        await conn.fetch(
            """
            SELECT turn_index, role, content
            FROM session_logs
            WHERE session_id = $1 AND role <> 'llm' AND sentiment_score IS NULL
              AND content IS NOT NULL AND length(btrim(content)) > 0
            ORDER BY turn_index ASC LIMIT $2
            """,
            session_id,
            limit,
        )
    )


async def update_sentiments(
    conn: asyncpg.Connection,
    *,
    session_id: UUID,
    scores: dict[int, tuple[float | None, str | None]],
) -> int:
    """Write (score, label) onto session_logs rows by turn_index. Returns rows updated."""
    updated = 0
    for turn_index, (score, label) in scores.items():
        if score is None and label is None:
            continue
        res = await conn.execute(
            """
            UPDATE session_logs SET sentiment_score = $3, sentiment_label = $4
            WHERE session_id = $1 AND turn_index = $2
            """,
            session_id,
            turn_index,
            score,
            label,
        )
        # asyncpg execute() returns e.g. "UPDATE 1"
        updated += int(res.split()[-1]) if res.startswith("UPDATE") else 0
    return updated


async def assemble_transcript(
    conn: asyncpg.Connection,
    *,
    session_id: UUID,
    last_n: int | None = None,
) -> str:
    """Build a ``"User: …\\nAI: …"`` transcript from stored turns.

    ``last_n`` keeps only the most recent N turns (for rolling summaries),
    still rendered oldest-first.
    """
    if last_n is not None:
        rows = await conn.fetch(
            """
            SELECT role, content FROM (
                SELECT role, content, turn_index
                FROM session_logs WHERE session_id = $1
                ORDER BY turn_index DESC LIMIT $2
            ) sub ORDER BY turn_index ASC
            """,
            session_id,
            last_n,
        )
    else:
        rows = await conn.fetch(
            "SELECT role, content FROM session_logs WHERE session_id = $1 ORDER BY turn_index ASC",
            session_id,
        )
    lines: list[str] = []
    for r in rows:
        text = (r["content"] or "").strip()
        if not text:
            continue
        label = _ROLE_LABEL.get(r["role"], r["role"].capitalize())
        lines.append(f"{label}: {text}")
    return "\n".join(lines)


def to_out_dict(log: SessionLog) -> dict[str, Any]:
    """Flatten a ``SessionLog`` for the replay wire schema."""
    return {
        "turn_index": log.turn_index,
        "role": log.role,
        "content": log.content,
        "speaker_label": log.speaker_label,
        "confidence": log.confidence,
        "model_used": log.model_used,
        "latency_ms": log.latency_ms,
        "sentiment_score": log.sentiment_score,
        "sentiment_label": log.sentiment_label,
        "created_at": log.created_at,
    }


async def update_confidence_bulk(
    conn: asyncpg.Connection,
    *,
    session_id: UUID,
    items: list[tuple[int, float]],
) -> int:
    """Bulk-update ``session_logs.confidence`` keyed by ``(session_id, turn_index)``.

    Rows whose ``turn_index`` does not match an existing log entry for
    this session are silently ignored. Returns the count of rows
    actually updated.
    """
    if not items:
        return 0
    turn_indexes = [t for t, _ in items]
    scores = [s for _, s in items]
    rows = await conn.fetch(
        """
        UPDATE session_logs sl
        SET confidence = data.score
        FROM unnest($1::int[], $2::numeric[]) AS data(turn_index, score)
        WHERE sl.session_id = $3
          AND sl.turn_index = data.turn_index
        RETURNING 1
        """,
        turn_indexes,
        scores,
        session_id,
    )
    return len(rows)
