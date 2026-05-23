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
class SessionLog:
    """One conversation turn. ``role`` is one of ``user`` / ``others`` / ``llm``."""

    id: UUID
    session_id: UUID
    turn_index: int
    role: str
    content: str | None
    speaker_label: str | None
    confidence: float | None
    model_used: str | None
    latency_ms: int | None
    tokens_used: int | None
    finish_reason: str | None
    has_error: bool
    error_message: str | None
    sentiment_score: float | None
    sentiment_label: str | None
    created_at: datetime


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


@dataclass(frozen=True, slots=True)
class SessionAnalytics:
    session_id: UUID
    user_id: UUID
    total_turns: int
    user_turns: int
    others_turns: int
    llm_turns: int
    user_word_count: int
    assistant_word_count: int
    average_latency_ms: int | None
    avg_advice_latency_ms: float | None
    total_duration_seconds: float | None
    memories_saved: int
    events_extracted: int
    highlights_created: int
    avg_sentiment_score: float | None
    dominant_sentiment: str | None
    topic_summary: str | None
    computed_at: datetime


@dataclass(frozen=True, slots=True)
class CoachingReport:
    id: UUID
    user_id: UUID
    session_id: UUID | None
    model_used: str | None
    user_talk_pct: float | None
    others_talk_pct: float | None
    key_topics: list[str]
    key_decisions: list[str]
    action_items: list[str]
    follow_up_people: list[str]
    filler_words: list[str]
    filler_word_count: int
    tone_summary: str | None
    engagement_trend: str | None
    suggestions: list[str]
    strengths: list[str]
    areas_of_improvement: list[str]
    report_text: str | None
    report_content: dict[str, Any]
    generated_at: datetime


@dataclass(frozen=True, slots=True)
class Feedback:
    id: UUID
    user_id: UUID
    session_id: UUID | None
    log_id: UUID | None
    consultant_log_id: UUID | None
    feedback_type: str | None
    rating: int | None
    value: int | None
    comment: str | None
    idempotency_key: str | None
    created_at: datetime


@dataclass(frozen=True, slots=True)
class WeeklyTrend:
    week: str
    sessions: int
    total_turns: int
    user_words: int
    ai_words: int
    avg_sentiment_score: float | None
    total_duration_seconds: float


@dataclass(frozen=True, slots=True)
class Scenario:
    id: UUID
    user_id: UUID
    target_entity_id: UUID | None
    title: str
    situation: str
    goal: str
    success_criteria: str
    difficulty: str
    role_mode: str
    opening_line: str
    source: dict[str, Any]
    status: str
    session_id: UUID | None
    passed: bool | None
    score_feedback: str | None
    created_at: datetime
    updated_at: datetime


@dataclass(frozen=True, slots=True)
class DrillCard:
    id: UUID
    user_id: UUID
    rule_id: str
    category: str
    examples: list[dict[str, Any]]
    box: int
    due_at: datetime
    last_reviewed_at: datetime | None
    correct_streak: int
    total_reviews: int
    total_correct: int
    retired_at: datetime | None
    created_at: datetime
    updated_at: datetime
