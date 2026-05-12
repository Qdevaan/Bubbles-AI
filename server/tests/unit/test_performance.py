"""Pure performance-summary math."""

from __future__ import annotations

from bubbles.core.performance import PerformanceInputs, compute_performance


def _inputs(**over: object) -> PerformanceInputs:
    base: dict[str, object] = {
        "session_count": 0,
        "avg_sentiment": None,
        "avg_user_talk_pct": None,
        "avg_filler_count": None,
        "quests_assigned": 0,
        "quests_completed": 0,
        "current_streak": 0,
    }
    base.update(over)
    return PerformanceInputs(**base)  # type: ignore[arg-type]


def test_defaults_land_in_struggling_with_neutral_breakdown() -> None:
    s = compute_performance(_inputs())
    # engagement 5, sentiment 5, freq 0, quest 5, streak 0, filler 5
    # = 1.5 + 0.75 + 0 + 0.75 + 0 + 0.5 = 3.5  -> "steady"
    assert s.weekly_score == 3.5
    assert s.performance_tier == "steady"
    assert s.recommended_difficulty == "medium"
    assert "consistency" in s.focus_areas  # freq < 4


def test_strong_user_is_excelling() -> None:
    s = compute_performance(
        _inputs(
            session_count=14,
            avg_sentiment=1.0,
            avg_user_talk_pct=0.5,
            avg_filler_count=0.0,
            quests_assigned=10,
            quests_completed=10,
            current_streak=14,
        )
    )
    assert s.weekly_score == 10.0
    assert s.performance_tier == "excelling"
    assert s.recommended_difficulty == "challenge"
    assert s.focus_areas == []


def test_one_sided_talk_flags_engagement() -> None:
    s = compute_performance(_inputs(avg_user_talk_pct=0.95))
    assert s.breakdown["engagement"] == 1.0  # 10 * (1 - 0.9) = 1.0
    assert "engagement" in s.focus_areas


def test_high_fillers_flag_filler_words_and_cap_at_zero() -> None:
    s = compute_performance(_inputs(avg_filler_count=20.0))
    assert s.breakdown["filler_control"] == 0.0
    assert "filler_words" in s.focus_areas


def test_quest_rate_below_half_flags_completion() -> None:
    s = compute_performance(_inputs(quests_assigned=10, quests_completed=2))
    assert s.breakdown["quest_completion"] == 2.0
    assert "quest_completion" in s.focus_areas
