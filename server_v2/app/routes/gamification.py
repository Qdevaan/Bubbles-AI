"""
Gamification routes — XP profile and daily quests.

Both endpoints require JWT auth and verify the path user_id matches the
authenticated user (no peeking at other users' profiles).
"""

from datetime import date, timedelta, timezone
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Request

from app.services import gamification_svc
from app.utils.rate_limit import limiter
from app.utils.auth_guard import get_verified_user, VerifiedUser, verify_ownership

router = APIRouter()


# ══════════════════════════════════════════════════════════════════════════════
# GET /gamification/{user_id}
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/gamification/{user_id}")
@limiter.limit("20/minute")
async def get_gamification(
    request: Request,
    user_id: str,
    user: VerifiedUser = Depends(get_verified_user),
):
    """
    Return full gamification profile: XP, level, streak, badges, recent XP, stats.

    Response fields consumed by the Flutter client:
      xp, level, xp_current_level, xp_next_level, xp_to_next_level,
      xp_progress_pct, current_streak, longest_streak, streak_freezes,
      last_active_date, badges[], recent_xp[], stats{}
    """
    await verify_ownership(user_id, user)

    profile = await gamification_svc.get_gamification_profile(user_id)
    if not profile:
        raise HTTPException(status_code=503, detail="Gamification service unavailable.")
    return profile


# ══════════════════════════════════════════════════════════════════════════════
# GET /quests/{user_id}
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/quests/{user_id}")
@limiter.limit("20/minute")
async def get_quests(
    request: Request,
    user_id: str,
    user: VerifiedUser = Depends(get_verified_user),
):
    """
    Return today's daily quests for the user.
    If no quests are assigned for today, assigns 3 randomly from active definitions.

    Note: daily_reset_at is midnight UTC of the next day — the Flutter client
    can display a countdown using this value.
    """
    await verify_ownership(user_id, user)

    quests = await gamification_svc.get_or_assign_daily_quests(user_id)

    today = date.today()
    tomorrow_midnight = datetime(
        today.year, today.month, today.day,
        tzinfo=timezone.utc
    ) + timedelta(days=1)

    completed_today = sum(1 for q in quests if q.get("is_completed"))

    return {
        "quests": quests,
        "daily_reset_at": tomorrow_midnight.isoformat(),
        "total_completed_today": completed_today,
        "total_quests_today": len(quests),
    }
