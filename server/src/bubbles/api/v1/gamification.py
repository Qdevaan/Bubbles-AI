"""Gamification HTTP routes — XP profile, daily quests, rewards, leaderboard.

All ``{user_id}``-path routes verify the path id matches the authenticated
user via ``require_ownership`` (no peeking at other users' data). No upstream
(LLM/Redis) calls here, so no ``UpstreamUnavailable`` paths.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter

from bubbles.api.v1._schemas import (
    AchievementOut,
    DailyQuestsResponse,
    GamificationProfile,
    RewardCatalogResponse,
    RewardOut,
    RewardRedeemRequest,
    RewardRedeemResponse,
    UserQuestOut,
    XpEntryOut,
)
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import BadRequest
from bubbles.core.gamification import level_progress
from bubbles.db.repo import achievements as achievements_repo
from bubbles.db.repo import gamification as gamification_repo
from bubbles.db.repo import xp as xp_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep

router = APIRouter(tags=["gamification"])


@router.get("/gamification/{user_id}", response_model=GamificationProfile)
async def get_gamification(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> GamificationProfile:
    require_ownership(user, str(user_id))
    async with transaction(pool) as conn:
        g = await gamification_repo.get_or_init_gamification(conn, user_id)
        badges = await achievements_repo.list_for_user(conn, user_id=user_id)
        recent = await xp_repo.recent(conn, user_id=user_id, limit=20)
    lp = level_progress(g.total_xp)
    return GamificationProfile(
        user_id=user_id,
        xp=g.total_xp,
        level=lp.level,
        xp_into_level=lp.xp_into_level,
        xp_to_next_level=lp.xp_to_next_level,
        xp_progress_pct=lp.progress_pct,
        current_streak=g.current_streak,
        longest_streak=g.longest_streak,
        streak_freezes=g.streak_freezes,
        last_active_date=g.last_active_date,
        badges=[
            AchievementOut(
                id=b.achievement.id,
                code=b.achievement.code,
                title=b.achievement.title,
                description=b.achievement.description,
                icon=b.achievement.icon,
                category=b.achievement.category,
                tier=b.achievement.tier,
                awarded_at=b.awarded_at,
            )
            for b in badges
        ],
        recent_xp=[
            XpEntryOut(
                amount=t.amount,
                source_type=t.source_type,
                description=t.description,
                created_at=t.created_at,
            )
            for t in recent
        ],
    )


@router.get("/quests/{user_id}", response_model=DailyQuestsResponse)
async def get_quests(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> DailyQuestsResponse:
    require_ownership(user, str(user_id))
    today = datetime.now(UTC).date()
    async with transaction(pool) as conn:
        await gamification_repo.get_or_init_gamification(conn, user_id)
        quests = await gamification_repo.get_or_assign_daily_quests(
            conn, user_id=user_id, on_date=today
        )
    reset_at = datetime(today.year, today.month, today.day, tzinfo=UTC) + timedelta(days=1)
    completed = sum(1 for q in quests if q.is_completed)
    return DailyQuestsResponse(
        quests=[
            UserQuestOut(
                id=q.id,
                quest_id=q.quest_id,
                progress=q.progress,
                target=q.target,
                is_completed=q.is_completed,
                assigned_date=q.assigned_date,
                completed_at=q.completed_at,
            )
            for q in quests
        ],
        daily_reset_at=reset_at,
        total_completed_today=completed,
        total_quests_today=len(quests),
    )


@router.get("/rewards/{user_id}", response_model=RewardCatalogResponse)
async def list_rewards(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> RewardCatalogResponse:
    require_ownership(user, str(user_id))
    async with transaction(pool) as conn:
        g = await gamification_repo.get_or_init_gamification(conn, user_id)
        rewards = await gamification_repo.list_active_rewards(conn)
        owned = await gamification_repo.owned_reward_ids(conn, user_id=user_id)
    balance = g.total_xp - g.xp_spent
    return RewardCatalogResponse(
        balance_xp=balance,
        rewards=[
            RewardOut(
                id=r.id,
                title=r.title,
                description=r.description,
                icon=r.icon,
                category=r.category,
                cost_xp=r.cost_xp,
                sort_order=r.sort_order,
                affordable=balance >= r.cost_xp,
                owned=r.id in owned,
            )
            for r in rewards
        ],
    )


@router.post("/rewards/{user_id}/redeem", response_model=RewardRedeemResponse)
async def redeem_reward(
    user_id: UUID,
    body: RewardRedeemRequest,
    user: CurrentUserDep,
    pool: PoolDep,
) -> RewardRedeemResponse:
    require_ownership(user, str(user_id))
    async with UnitOfWork(pool) as uow:
        try:
            ur = await gamification_repo.redeem_reward(
                uow.conn, user_id=user_id, reward_id=body.reward_id
            )
        except ValueError as e:
            raise BadRequest(str(e)) from e
        g = await gamification_repo.get_or_init_gamification(uow.conn, user_id)
    return RewardRedeemResponse(
        reward_id=ur.reward_id,
        cost_xp=ur.cost_xp,
        unlocked_at=ur.unlocked_at,
        balance_xp=g.total_xp - g.xp_spent,
    )
