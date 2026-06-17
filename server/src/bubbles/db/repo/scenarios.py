# Purpose: Repository for AI-generated roleplay scenarios: insert, list by user, and update completion state.
"""Scenarios repo — graph-generated roleplay practice."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Final
from uuid import UUID

import asyncpg

from bubbles.db.models import Scenario

_COLS: Final[str] = (
    "id, user_id, target_entity_id, title, situation, goal, success_criteria, "
    "difficulty, role_mode, opening_line, source, status, session_id, passed, "
    "score_feedback, created_at, updated_at"
)


@dataclass(frozen=True, slots=True)
class NewScenario:
    """A scenario draft from the generator, before it is persisted."""

    target_entity_id: UUID | None
    title: str
    situation: str
    goal: str
    success_criteria: str
    difficulty: str
    role_mode: str
    opening_line: str
    source: dict[str, Any]


def _source(raw: Any) -> dict[str, Any]:
    if isinstance(raw, str):
        loaded: Any = json.loads(raw)
        return dict(loaded) if isinstance(loaded, dict) else {}
    return dict(raw) if raw else {}


def _row(r: asyncpg.Record) -> Scenario:
    return Scenario(
        id=r["id"],
        user_id=r["user_id"],
        target_entity_id=r["target_entity_id"],
        title=r["title"],
        situation=r["situation"],
        goal=r["goal"],
        success_criteria=r["success_criteria"],
        difficulty=r["difficulty"],
        role_mode=r["role_mode"],
        opening_line=r["opening_line"],
        source=_source(r["source"]),
        status=r["status"],
        session_id=r["session_id"],
        passed=r["passed"],
        score_feedback=r["score_feedback"],
        created_at=r["created_at"],
        updated_at=r["updated_at"],
    )


async def create_many(
    conn: asyncpg.Connection, *, user_id: UUID, rows: list[NewScenario]
) -> list[Scenario]:
    # The feed worker generates at most 5 scenarios per call (target feed size),
    # so a per-row INSERT loop is acceptable here — no bulk insert needed.
    out: list[Scenario] = []
    for r in rows:
        row = await conn.fetchrow(
            f"""
            INSERT INTO scenarios (
                user_id, target_entity_id, title, situation, goal,
                success_criteria, difficulty, role_mode, opening_line, source
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb)
            RETURNING {_COLS}
            """,
            user_id,
            r.target_entity_id,
            r.title,
            r.situation,
            r.goal,
            r.success_criteria,
            r.difficulty,
            r.role_mode,
            r.opening_line,
            json.dumps(r.source),
        )
        assert row is not None
        out.append(_row(row))
    return out


async def list_for_user(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    status: str = "suggested",
    limit: int = 50,
    offset: int = 0,
) -> list[Scenario]:
    rows = await conn.fetch(
        f"""
        SELECT {_COLS} FROM scenarios
        WHERE user_id = $1 AND status = $2
        ORDER BY created_at DESC
        LIMIT $3 OFFSET $4
        """,
        user_id,
        status,
        limit,
        offset,
    )
    return [_row(r) for r in rows]


async def get(conn: asyncpg.Connection, scenario_id: UUID) -> Scenario | None:
    row = await conn.fetchrow(f"SELECT {_COLS} FROM scenarios WHERE id = $1", scenario_id)
    return _row(row) if row is not None else None


async def get_by_session(conn: asyncpg.Connection, *, session_id: UUID) -> Scenario | None:
    row = await conn.fetchrow(f"SELECT {_COLS} FROM scenarios WHERE session_id = $1", session_id)
    return _row(row) if row is not None else None


async def count_active(conn: asyncpg.Connection, *, user_id: UUID) -> int:
    n: int | None = await conn.fetchval(
        "SELECT COUNT(*)::int FROM scenarios WHERE user_id = $1 AND status = 'suggested'",
        user_id,
    )
    return n or 0


async def used_source_ids(
    conn: asyncpg.Connection, *, user_id: UUID
) -> tuple[set[UUID], set[UUID]]:
    """Task ids and event ids referenced by every non-dismissed scenario."""
    rows = await conn.fetch(
        "SELECT source FROM scenarios WHERE user_id = $1 AND status <> 'dismissed'",
        user_id,
    )
    tasks: set[UUID] = set()
    events: set[UUID] = set()
    for r in rows:
        src = _source(r["source"])
        for key, bucket in (("tasks", tasks), ("events", events)):
            for raw in src.get(key, []) or []:
                try:
                    bucket.add(UUID(str(raw)))
                except (ValueError, AttributeError):
                    continue
    return tasks, events


async def mark_started(
    conn: asyncpg.Connection, *, scenario_id: UUID, session_id: UUID
) -> Scenario | None:
    """Flip a suggested scenario to started. Returns ``None`` if it was not suggested."""
    row = await conn.fetchrow(
        f"""
        UPDATE scenarios
        SET status = 'started', session_id = $2, updated_at = now()
        WHERE id = $1 AND status = 'suggested'
        RETURNING {_COLS}
        """,
        scenario_id,
        session_id,
    )
    return _row(row) if row is not None else None


async def mark_dismissed(conn: asyncpg.Connection, *, scenario_id: UUID) -> Scenario | None:
    """Dismiss a suggested scenario. Returns ``None`` if it was not suggested."""
    row = await conn.fetchrow(
        f"""
        UPDATE scenarios
        SET status = 'dismissed', updated_at = now()
        WHERE id = $1 AND status = 'suggested'
        RETURNING {_COLS}
        """,
        scenario_id,
    )
    return _row(row) if row is not None else None


async def mark_completed(
    conn: asyncpg.Connection,
    *,
    scenario_id: UUID,
    passed: bool | None,
    feedback: str | None,
) -> Scenario | None:
    """Complete a started scenario. Returns ``None`` if it was not ``started``."""
    row = await conn.fetchrow(
        f"""
        UPDATE scenarios
        SET status = 'completed', passed = $2, score_feedback = $3, updated_at = now()
        WHERE id = $1 AND status = 'started'
        RETURNING {_COLS}
        """,
        scenario_id,
        passed,
        feedback,
    )
    return _row(row) if row is not None else None
