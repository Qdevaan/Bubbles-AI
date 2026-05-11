"""
Gamification routes — XP profile and daily quests.

Both endpoints require JWT auth and verify the path user_id matches the
authenticated user (no peeking at other users' profiles).
"""

from datetime import date, timedelta, timezone
from datetime import datetime

from fastapi import APIRouter, Body, Depends, HTTPException, Request

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


# ══════════════════════════════════════════════════════════════════════════════
# POST /quests/{user_id}/{user_quest_id}/answer  (question_set missions)
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/quests/{user_id}/{user_quest_id}/answer")
@limiter.limit("60/minute")
async def submit_quest_answer(
    request: Request,
    user_id: str,
    user_quest_id: str,
    payload: dict = Body(...),
    user: VerifiedUser = Depends(get_verified_user),
):
    """
    Submit an answer for a single question of a question_set mission.
    Body: { "question_id": str, "answer": str }
    """
    await verify_ownership(user_id, user)

    question_id = (payload.get("question_id") or "").strip()
    answer = payload.get("answer")
    if not question_id or answer is None:
        raise HTTPException(status_code=400, detail="question_id and answer are required")

    try:
        return await gamification_svc.submit_question_answer(
            user_id=user_id,
            user_quest_id=user_quest_id,
            question_id=question_id,
            answer=str(answer),
        )
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        print(f"⚠️ submit_quest_answer error: {e}")
        raise HTTPException(status_code=500, detail="Failed to submit answer")


# ══════════════════════════════════════════════════════════════════════════════
# POST /quests/{user_id}/{user_quest_id}/attach_session  (conversation missions)
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/quests/{user_id}/{user_quest_id}/attach_session")
@limiter.limit("30/minute")
async def attach_quest_session(
    request: Request,
    user_id: str,
    user_quest_id: str,
    payload: dict = Body(...),
    user: VerifiedUser = Depends(get_verified_user),
):
    """
    Attach a completed session to a conversation mission.
    Body: { "session_id": str }
    """
    await verify_ownership(user_id, user)

    session_id = (payload.get("session_id") or "").strip()
    if not session_id:
        raise HTTPException(status_code=400, detail="session_id is required")

    try:
        return await gamification_svc.attach_conversation_session(
            user_id=user_id,
            user_quest_id=user_quest_id,
            session_id=session_id,
        )
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        print(f"⚠️ attach_quest_session error: {e}")
        raise HTTPException(status_code=500, detail="Failed to attach session")


# ══════════════════════════════════════════════════════════════════════════════
# GET /rewards/{user_id}  (catalog with affordability + ownership)
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/rewards/{user_id}")
@limiter.limit("20/minute")
async def list_rewards(
    request: Request,
    user_id: str,
    user: VerifiedUser = Depends(get_verified_user),
):
    """
    Reward catalog enriched with the requesting user's balance and ownership.
    """
    await verify_ownership(user_id, user)
    return await gamification_svc.list_rewards(user_id)


# ══════════════════════════════════════════════════════════════════════════════
# POST /rewards/{user_id}/redeem
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/rewards/{user_id}/redeem")
@limiter.limit("10/minute")
async def redeem_reward(
    request: Request,
    user_id: str,
    payload: dict = Body(...),
    user: VerifiedUser = Depends(get_verified_user),
):
    """
    Redeem a reward by id. Body: { "reward_id": str }.
    """
    await verify_ownership(user_id, user)

    reward_id = (payload.get("reward_id") or "").strip()
    if not reward_id:
        raise HTTPException(status_code=400, detail="reward_id is required")

    try:
        return await gamification_svc.redeem_reward(user_id, reward_id)
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        print(f"⚠️ redeem_reward error: {e}")
        raise HTTPException(status_code=500, detail="Failed to redeem reward")


# ══════════════════════════════════════════════════════════════════════════════
# GET /leaderboard?period=daily|weekly|monthly|all&limit=25
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/leaderboard")
@limiter.limit("30/minute")
async def get_leaderboard(
    request: Request,
    period: str = "all",
    limit: int = 25,
    user: VerifiedUser = Depends(get_verified_user),
):
    """
    Global leaderboard for the chosen period plus the caller's rank.
    """
    return await gamification_svc.get_leaderboard(
        requesting_user_id=user.user_id,
        period=period,
        limit=limit,
    )


# ══════════════════════════════════════════════════════════════════════════════
# POST /leaderboard/{user_id}/opt_in
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/leaderboard/{user_id}/opt_in")
@limiter.limit("10/minute")
async def set_leaderboard_opt_in(
    request: Request,
    user_id: str,
    payload: dict = Body(...),
    user: VerifiedUser = Depends(get_verified_user),
):
    """
    Toggle leaderboard visibility. Body: { "opt_in": bool }.
    """
    await verify_ownership(user_id, user)
    opt_in = payload.get("opt_in")
    if not isinstance(opt_in, bool):
        raise HTTPException(status_code=400, detail="opt_in must be boolean")

    ok = await gamification_svc.set_leaderboard_opt_in(user_id, opt_in)
    if not ok:
        raise HTTPException(status_code=500, detail="Failed to update preference")
    return {"user_id": user_id, "leaderboard_opt_in": opt_in}
