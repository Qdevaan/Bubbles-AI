"""Domain row models.

Frozen dataclasses — fast to construct, immutable, no business logic. Maps
1:1 to columns we read; columns we don't read aren't modelled.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from typing import Any
from uuid import UUID


@dataclass(frozen=True, slots=True)
class Session:
    id: UUID
    user_id: UUID
    title: str | None
    summary: str | None
    session_type: str
    mode: str
    status: str
    persona: str
    start_time: datetime
    end_time: datetime | None
    ended_at: datetime | None
    created_at: datetime
    deleted_at: datetime | None
    idempotency_key: str | None
    session_context: dict[str, Any] | None
    is_starred: bool
    is_ephemeral: bool
    is_multiplayer: bool


@dataclass(frozen=True, slots=True)
class Entity:
    id: UUID
    user_id: UUID
    canonical_name: str
    display_name: str | None
    entity_type: str
    aliases: list[str]
    description: str | None
    mention_count: int
    is_archived: bool
    last_seen_at: datetime | None
    created_at: datetime


@dataclass(frozen=True, slots=True)
class EntityRelation:
    id: UUID
    user_id: UUID
    source_id: UUID
    target_id: UUID
    relation: str
    strength: float
    created_at: datetime


@dataclass(frozen=True, slots=True)
class UserPersona:
    user_id: UUID
    display_name: str | None
    role_primary: str
    role_family: str
    profession_detail: str | None
    expertise_tags: list[str]
    native_language: str
    learning_language: str
    proficiency_self_rated: str | None
    formality_preference: str | None
    communication_style: list[str]
    primary_goals: list[str]
    typical_scenarios: list[str]
    cultural_context: str | None
    avoid_list: str | None
    age_range: str | None
    completed_at: datetime | None
    created_at: datetime
    updated_at: datetime


@dataclass(frozen=True, slots=True)
class UserMistake:
    id: UUID
    user_id: UUID
    session_id: UUID | None
    rule_id: str
    category: str
    snippet: str
    suggestion: str | None
    source: str
    created_at: datetime


@dataclass(frozen=True, slots=True)
class Memory:
    id: UUID
    user_id: UUID
    session_id: UUID | None
    content: str
    memory_type: str
    importance: float
    confidence: float
    source: str
    is_pinned: bool
    is_archived: bool
    created_at: datetime
    last_accessed_at: datetime | None
    expires_at: datetime | None


@dataclass(frozen=True, slots=True)
class UserGamification:
    user_id: UUID
    total_xp: int
    level: int
    current_streak: int
    longest_streak: int
    streak_freezes: int
    last_active_date: date | None
    xp_spent: int
    leaderboard_opt_in: bool
    updated_at: datetime


@dataclass(frozen=True, slots=True)
class QuestDefinition:
    id: UUID
    title: str
    description: str | None
    quest_type: str
    action_type: str
    target: int
    xp_reward: int
    is_active: bool
    focus_area: str | None
    difficulty: str
    mission_type: str
    brief: dict[str, Any] | None


@dataclass(frozen=True, slots=True)
class UserQuest:
    id: UUID
    user_id: UUID
    quest_id: UUID
    progress: int
    target: int
    is_completed: bool
    xp_awarded: bool
    assigned_date: date
    completed_at: datetime | None
    created_at: datetime


@dataclass(frozen=True, slots=True)
class Reward:
    id: UUID
    title: str
    description: str | None
    icon: str
    category: str
    cost_xp: int
    sort_order: int
    is_active: bool


@dataclass(frozen=True, slots=True)
class UserReward:
    id: UUID
    user_id: UUID
    reward_id: UUID
    cost_xp: int
    unlocked_at: datetime


@dataclass(frozen=True, slots=True)
class XpTransaction:
    id: UUID
    user_id: UUID
    amount: int
    source_type: str
    source_id: str | None
    description: str | None
    created_at: datetime


@dataclass(frozen=True, slots=True)
class Achievement:
    id: UUID
    code: str | None
    title: str
    description: str | None
    icon: str
    category: str
    criteria_type: str
    criteria_value: int
    xp_reward: int
    tier: str | None
    created_at: datetime


@dataclass(frozen=True, slots=True)
class UserAchievement:
    id: UUID
    user_id: UUID
    achievement_id: UUID
    awarded_at: datetime


@dataclass(frozen=True, slots=True)
class UserBadge:
    """View model: an earned achievement plus when it was awarded."""

    achievement: Achievement
    awarded_at: datetime
