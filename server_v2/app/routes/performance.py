"""
Performance summary route — AI-driven adaptive difficulty engine.

Aggregates user session analytics to compute:
  - performance_tier: struggling | steady | improving | excelling
  - recommended_difficulty for quest assignment
  - focus_areas extracted from session patterns
  - ai_coaching_tip: template-based coaching nudge
  - weekly_score: 0-10 composite performance metric
"""

from datetime import date, timedelta, timezone, datetime
from typing import Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request

from app.database import db
from app.utils.rate_limit import limiter
from app.utils.auth_guard import get_verified_user, VerifiedUser, verify_ownership

router = APIRouter()


# ── Performance tier thresholds ──────────────────────────────────────────────
# Based on composite score (0-10)
_TIER_THRESHOLDS = {
    "excelling":  7.5,
    "improving":  5.0,
    "steady":     3.0,
    # anything below 3.0 = "struggling"
}

_DIFFICULTY_MAP = {
    "excelling":  "challenge",
    "improving":  "hard",
    "steady":     "medium",
    "struggling": "easy",
}

_COACHING_TIPS = {
    "excelling":  "You're on fire! 🔥 Push yourself with advanced challenges today.",
    "improving":  "Great progress this week! Keep the momentum going.",
    "steady":     "Consistency is key. Try one more session today to level up.",
    "struggling": "Take it easy. Even a short session counts — you've got this! 💪",
}


@router.get("/performance_summary/{user_id}")
@limiter.limit("10/minute")
async def get_performance_summary(
    request: Request,
    user_id: str,
    user: VerifiedUser = Depends(get_verified_user),
):
    """
    Compute and return an AI-analyzed performance summary for the user.
    Used by the Game Center's adaptive difficulty engine.
    """
    await verify_ownership(user_id, user)

    if not db:
        raise HTTPException(status_code=503, detail="Database unavailable")

    try:
        # ── Gather data from the last 7 days ──────────────────────────────
        week_ago = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()

        # Session analytics (engagement scores)
        analytics_res = db.table("session_analytics") \
            .select("mutual_engagement_score, user_filler_count, avg_sentiment_score, total_turns, created_at") \
            .eq("user_id", user_id) \
            .gte("created_at", week_ago) \
            .order("created_at", desc=True) \
            .limit(20) \
            .execute()

        sessions_data = analytics_res.data or []

        # Completed sessions count this week
        sessions_res = db.table("sessions") \
            .select("id", count="exact") \
            .eq("user_id", user_id) \
            .eq("status", "completed") \
            .gte("created_at", week_ago) \
            .execute()
        session_count = sessions_res.count or 0

        # Quest completion rate (last 7 days)
        quests_total_res = db.table("user_quests") \
            .select("id, is_completed") \
            .eq("user_id", user_id) \
            .gte("assigned_date", (date.today() - timedelta(days=7)).isoformat()) \
            .execute()

        quest_data = quests_total_res.data or []
        quests_assigned = len(quest_data)
        quests_completed = sum(1 for q in quest_data if q.get("is_completed"))
        quest_completion_rate = (quests_completed / quests_assigned) if quests_assigned > 0 else 0.5

        # Gamification profile (streak)
        profile_res = db.table("user_gamification") \
            .select("current_streak, total_xp") \
            .eq("user_id", user_id) \
            .maybe_single() \
            .execute()

        streak = 0
        if profile_res and profile_res.data:
            streak = profile_res.data.get("current_streak", 0) or 0

        # ── Compute composite score (0-10) ────────────────────────────────
        #
        # Weighted formula:
        #   engagement_avg * 0.3  (already 0-10)
        #   sentiment_avg  * 0.15 (map -1..1 to 0..10)
        #   session_freq   * 0.2  (sessions/7 * 10, cap at 10)
        #   quest_rate     * 0.15 (0-1 * 10)
        #   streak_factor  * 0.1  (streak/7 * 10, cap at 10)
        #   filler_reduce  * 0.1  (inverse of filler count trend)

        # Engagement
        engagement_scores = [
            (s.get("mutual_engagement_score") or 5)
            for s in sessions_data
            if s.get("mutual_engagement_score") is not None
        ]
        engagement_avg = sum(engagement_scores) / len(engagement_scores) if engagement_scores else 5.0

        # Sentiment
        sentiment_scores = [
            (s.get("avg_sentiment_score") or 0)
            for s in sessions_data
            if s.get("avg_sentiment_score") is not None
        ]
        sentiment_avg = sum(sentiment_scores) / len(sentiment_scores) if sentiment_scores else 0.0
        sentiment_norm = (sentiment_avg + 1) * 5  # map -1..1 → 0..10

        # Session frequency
        session_freq = min(session_count / 7 * 10, 10)

        # Quest rate
        quest_score = quest_completion_rate * 10

        # Streak factor
        streak_factor = min(streak / 7 * 10, 10)

        # Filler reduction (lower = better)
        filler_counts = [
            (s.get("user_filler_count") or 0)
            for s in sessions_data
        ]
        avg_fillers = sum(filler_counts) / len(filler_counts) if filler_counts else 5
        filler_score = max(0, 10 - avg_fillers)  # 0 fillers = 10, 10+ fillers = 0

        composite = (
            engagement_avg * 0.3 +
            sentiment_norm * 0.15 +
            session_freq * 0.2 +
            quest_score * 0.15 +
            streak_factor * 0.1 +
            filler_score * 0.1
        )
        composite = round(min(max(composite, 0), 10), 1)

        # ── Determine tier ────────────────────────────────────────────────
        if composite >= _TIER_THRESHOLDS["excelling"]:
            tier = "excelling"
        elif composite >= _TIER_THRESHOLDS["improving"]:
            tier = "improving"
        elif composite >= _TIER_THRESHOLDS["steady"]:
            tier = "steady"
        else:
            tier = "struggling"

        # ── Focus areas ───────────────────────────────────────────────────
        focus_areas = []
        if engagement_avg < 5:
            focus_areas.append("engagement")
        if avg_fillers > 3:
            focus_areas.append("filler_words")
        if sentiment_norm < 5:
            focus_areas.append("positivity")
        if session_freq < 4:
            focus_areas.append("consistency")
        if quest_completion_rate < 0.5:
            focus_areas.append("quest_completion")

        # ── Previous week's score (for delta) ─────────────────────────────
        two_weeks_ago = (datetime.now(timezone.utc) - timedelta(days=14)).isoformat()
        prev_analytics = db.table("session_analytics") \
            .select("mutual_engagement_score") \
            .eq("user_id", user_id) \
            .gte("created_at", two_weeks_ago) \
            .lt("created_at", week_ago) \
            .limit(20) \
            .execute()
        prev_scores = [
            (s.get("mutual_engagement_score") or 5)
            for s in (prev_analytics.data or [])
        ]
        prev_avg = sum(prev_scores) / len(prev_scores) if prev_scores else composite
        score_delta = round(composite - prev_avg, 1)

        return {
            "performance_tier": tier,
            "recommended_difficulty": _DIFFICULTY_MAP[tier],
            "focus_areas": focus_areas,
            "ai_coaching_tip": _COACHING_TIPS[tier],
            "weekly_score": composite,
            "score_delta": score_delta,
            "breakdown": {
                "engagement": round(engagement_avg, 1),
                "sentiment": round(sentiment_norm, 1),
                "session_frequency": round(session_freq, 1),
                "quest_completion": round(quest_score, 1),
                "streak": round(streak_factor, 1),
                "filler_control": round(filler_score, 1),
            },
        }

    except Exception as e:
        print(f"⚠️ performance_summary error: {e}")
        raise HTTPException(status_code=500, detail="Failed to compute performance summary")
