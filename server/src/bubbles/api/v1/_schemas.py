"""Wire-format Pydantic models for /v1 routes.

All schemas use ``extra="forbid"`` so unknown fields surface as 422 instead
of being silently dropped.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class _Base(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


# --- sessions --------------------------------------------------------------


class StartSessionRequest(_Base):
    title: str | None = None
    session_type: str = "general"
    mode: str = "live_wingman"
    persona: str = "casual"
    is_ephemeral: bool = False
    idempotency_key: str | None = Field(default=None, max_length=128)
    session_context: dict[str, Any] | None = None


class SessionOut(_Base):
    id: UUID
    user_id: UUID
    title: str | None
    status: str
    persona: str
    mode: str


class EndSessionRequest(_Base):
    session_id: UUID
    summary: str | None = None


class SaveSessionRequest(_Base):
    session_id: UUID
    transcript: str = Field(..., min_length=1, max_length=200_000)


class SessionContextRequest(_Base):
    context: dict[str, Any]


class SuggestReplyRequest(_Base):
    session_id: UUID
    last_user_text: str = Field(..., min_length=1, max_length=4_000)


class SuggestReplyResponse(_Base):
    suggestion: str
    provider: str


# --- consultant ------------------------------------------------------------


class ConsultantRequest(_Base):
    session_id: UUID | None = None
    question: str = Field(..., min_length=1, max_length=8_000)
    persona: str | None = None


class ConsultantBatchRequest(_Base):
    session_id: UUID | None = None
    questions: list[str] = Field(..., min_length=1, max_length=20)


class ConsultantAnswer(_Base):
    answer: str
    provider: str
    fallback_depth: int


class ConsultantBatchAnswer(_Base):
    answers: list[ConsultantAnswer]


# --- entities --------------------------------------------------------------


class EntityQueryRequest(_Base):
    question: str = Field(..., min_length=1, max_length=4_000)
    session_id: UUID | None = None


class EntitySummary(_Base):
    id: UUID
    canonical_name: str
    entity_type: str
    description: str | None = None


class EntityAnswer(_Base):
    answer: str
    entities: list[EntitySummary]
    provider: str


# --- persona ---------------------------------------------------------------


class PersonaUpsertRequest(_Base):
    role_primary: str
    native_language: str
    learning_language: str = "en"
    display_name: str | None = None
    age_range: str | None = None
    profession_detail: str | None = None
    expertise_tags: list[str] = Field(default_factory=list)
    proficiency_self_rated: str | None = None
    formality_preference: str | None = "neutral"
    communication_style: list[str] = Field(default_factory=list)
    primary_goals: list[str] = Field(default_factory=list)
    typical_scenarios: list[str] = Field(default_factory=list)
    cultural_context: str | None = None
    avoid_list: str | None = None


class PersonaResponse(_Base):
    user_id: UUID
    display_name: str | None
    role_primary: str
    role_family: str
    native_language: str
    learning_language: str


# --- grammar ---------------------------------------------------------------


class CheckUserTurnRequest(_Base):
    session_id: UUID | None = None
    text: str = Field(..., min_length=1, max_length=4_000)


class MistakeOut(_Base):
    category: str
    snippet: str
    suggestion: str | None
    source: str
    rule_id: str


class CheckUserTurnResponse(_Base):
    is_correct: bool
    corrected: str | None
    mistakes: list[MistakeOut]


class UserMistakesResponse(_Base):
    items: list[MistakeOut]
    counts: dict[str, int]
