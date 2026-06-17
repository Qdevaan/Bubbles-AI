# Purpose: Repository for Performa persona records: create, fetch by user_id, and update communication profile.
"""User personas repo (subsystem A)."""

from __future__ import annotations

from typing import Final
from uuid import UUID

import asyncpg

from bubbles.db.models import UserPersona

ROLE_FAMILIES: Final[frozenset[str]] = frozenset(
    {"educator", "learner", "professional", "casual", "default"}
)

_COLS = """
    user_id, display_name, age_range, role_primary, profession_detail,
    expertise_tags, native_language, learning_language, proficiency_self_rated,
    formality_preference, communication_style, primary_goals, typical_scenarios,
    cultural_context, avoid_list, role_family, completed_at, created_at, updated_at
"""


def classify_role_family(role_primary: str) -> str:
    role = (role_primary or "").lower()
    if role in {"teacher", "professor", "lecturer"}:
        return "educator"
    if role in {"student"}:
        return "learner"
    if role in {"professional", "manager", "freelancer"}:
        return "professional"
    if role in {"homemaker"}:
        return "casual"
    return "default"


def _row(row: asyncpg.Record) -> UserPersona:
    return UserPersona(
        user_id=row["user_id"],
        display_name=row["display_name"],
        age_range=row["age_range"],
        role_primary=row["role_primary"],
        role_family=row["role_family"],
        profession_detail=row["profession_detail"],
        expertise_tags=list(row["expertise_tags"] or []),
        native_language=row["native_language"],
        learning_language=row["learning_language"],
        proficiency_self_rated=row["proficiency_self_rated"],
        formality_preference=row["formality_preference"],
        communication_style=list(row["communication_style"] or []),
        primary_goals=list(row["primary_goals"] or []),
        typical_scenarios=list(row["typical_scenarios"] or []),
        cultural_context=row["cultural_context"],
        avoid_list=row["avoid_list"],
        completed_at=row["completed_at"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


async def get(conn: asyncpg.Connection, user_id: UUID) -> UserPersona | None:
    row = await conn.fetchrow(
        f"SELECT {_COLS} FROM user_personas WHERE user_id = $1",
        user_id,
    )
    return _row(row) if row is not None else None


async def upsert(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    role_primary: str,
    native_language: str,
    learning_language: str = "en",
    display_name: str | None = None,
    age_range: str | None = None,
    profession_detail: str | None = None,
    expertise_tags: list[str] | None = None,
    proficiency_self_rated: str | None = None,
    formality_preference: str | None = "neutral",
    communication_style: list[str] | None = None,
    primary_goals: list[str] | None = None,
    typical_scenarios: list[str] | None = None,
    cultural_context: str | None = None,
    avoid_list: str | None = None,
) -> UserPersona:
    role_family = classify_role_family(role_primary)
    row = await conn.fetchrow(
        f"""
        INSERT INTO user_personas (
            user_id, display_name, age_range, role_primary, role_family,
            profession_detail, expertise_tags, native_language, learning_language,
            proficiency_self_rated, formality_preference, communication_style,
            primary_goals, typical_scenarios, cultural_context, avoid_list,
            completed_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, NOW())
        ON CONFLICT (user_id) DO UPDATE SET
            display_name = EXCLUDED.display_name,
            age_range = EXCLUDED.age_range,
            role_primary = EXCLUDED.role_primary,
            role_family = EXCLUDED.role_family,
            profession_detail = EXCLUDED.profession_detail,
            expertise_tags = EXCLUDED.expertise_tags,
            native_language = EXCLUDED.native_language,
            learning_language = EXCLUDED.learning_language,
            proficiency_self_rated = EXCLUDED.proficiency_self_rated,
            formality_preference = EXCLUDED.formality_preference,
            communication_style = EXCLUDED.communication_style,
            primary_goals = EXCLUDED.primary_goals,
            typical_scenarios = EXCLUDED.typical_scenarios,
            cultural_context = EXCLUDED.cultural_context,
            avoid_list = EXCLUDED.avoid_list,
            completed_at = NOW(),
            updated_at = NOW()
        RETURNING {_COLS}
        """,
        user_id,
        display_name,
        age_range,
        role_primary,
        role_family,
        profession_detail,
        expertise_tags or [],
        native_language,
        learning_language,
        proficiency_self_rated,
        formality_preference,
        communication_style or [],
        primary_goals or [],
        typical_scenarios or [],
        cultural_context,
        avoid_list,
    )
    assert row is not None
    return _row(row)
