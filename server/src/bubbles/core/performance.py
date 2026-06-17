# Purpose: Async context manager that records wall-clock latency and emits it as a Prometheus histogram observation.
"""Pure performance-summary math — no I/O.

Re-derives ``server_v2``'s adaptive-difficulty composite from the metrics v5
actually persists (v2's ``mutual_engagement_score`` doesn't exist here; we use
talk-time balance from the coaching report as the engagement proxy).
"""

from __future__ import annotations

from dataclasses import dataclass

_TIER_THRESHOLDS: tuple[tuple[str, float], ...] = (
    ("excelling", 7.5),
    ("improving", 5.0),
    ("steady", 3.0),
)  # below the last → "struggling"

_DIFFICULTY: dict[str, str] = {
    "excelling": "challenge",
    "improving": "hard",
    "steady": "medium",
    "struggling": "easy",
}

_COACHING_TIPS: dict[str, str] = {
    "excelling": "You're on fire! 🔥 Push yourself with advanced challenges today.",
    "improving": "Great progress this week! Keep the momentum going.",
    "steady": "Consistency is key. Try one more session today to level up.",
    "struggling": "Take it easy. Even a short session counts — you've got this! 💪",
}


@dataclass(frozen=True, slots=True)
class PerformanceInputs:
    session_count: int  # completed sessions in the window
    avg_sentiment: float | None  # mean session_analytics.avg_sentiment_score in [-1, 1]
    avg_user_talk_pct: float | None  # mean coaching_reports.user_talk_pct in [0, 1]
    avg_filler_count: float | None  # mean coaching_reports.filler_word_count
    quests_assigned: int
    quests_completed: int
    current_streak: int


@dataclass(frozen=True, slots=True)
class PerformanceSummary:
    performance_tier: str
    recommended_difficulty: str
    focus_areas: list[str]
    ai_coaching_tip: str
    weekly_score: float
    breakdown: dict[str, float]


def _clamp10(x: float) -> float:
    return max(0.0, min(10.0, x))


def _engagement_score(avg_user_talk_pct: float | None) -> float:
    # Balanced (~50/50) talk time scores best; one-sided conversations score low.
    if avg_user_talk_pct is None:
        return 5.0
    return _clamp10(10.0 * (1.0 - min(1.0, abs(0.5 - avg_user_talk_pct) * 2.0)))


def compute_performance(i: PerformanceInputs) -> PerformanceSummary:
    engagement = _engagement_score(i.avg_user_talk_pct)
    sentiment = _clamp10(((i.avg_sentiment or 0.0) + 1.0) * 5.0)  # [-1,1] → [0,10]
    session_freq = _clamp10(i.session_count / 7.0 * 10.0)
    quest_rate = (i.quests_completed / i.quests_assigned) if i.quests_assigned > 0 else 0.5
    quest_score = _clamp10(quest_rate * 10.0)
    streak_score = _clamp10(i.current_streak / 7.0 * 10.0)
    avg_fillers = i.avg_filler_count if i.avg_filler_count is not None else 5.0
    filler_score = _clamp10(10.0 - avg_fillers)

    composite = round(
        _clamp10(
            engagement * 0.30
            + sentiment * 0.15
            + session_freq * 0.20
            + quest_score * 0.15
            + streak_score * 0.10
            + filler_score * 0.10
        ),
        1,
    )

    tier = "struggling"
    for name, threshold in _TIER_THRESHOLDS:
        if composite >= threshold:
            tier = name
            break

    focus: list[str] = []
    if engagement < 5.0:
        focus.append("engagement")
    if avg_fillers > 3.0:
        focus.append("filler_words")
    if sentiment < 5.0:
        focus.append("positivity")
    if session_freq < 4.0:
        focus.append("consistency")
    if quest_rate < 0.5:
        focus.append("quest_completion")

    return PerformanceSummary(
        performance_tier=tier,
        recommended_difficulty=_DIFFICULTY[tier],
        focus_areas=focus,
        ai_coaching_tip=_COACHING_TIPS[tier],
        weekly_score=composite,
        breakdown={
            "engagement": round(engagement, 1),
            "sentiment": round(sentiment, 1),
            "session_frequency": round(session_freq, 1),
            "quest_completion": round(quest_score, 1),
            "streak": round(streak_score, 1),
            "filler_control": round(filler_score, 1),
        },
    )
