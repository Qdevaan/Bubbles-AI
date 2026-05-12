"""Gamification HTTP routes — XP profile, daily quests, rewards, leaderboard.

All ``{user_id}``-path routes verify the path id matches the authenticated
user via ``require_ownership`` (no peeking at other users' data). No upstream
(LLM/Redis) calls here, so no ``UpstreamUnavailable`` paths.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Query

from bubbles.api.v1._schemas import (
    AchievementOut,
    DailyQuestsResponse,
    GamificationProfile,
    LeaderboardEntry,
    LeaderboardMe,
    LeaderboardResponse,
    OptInRequest,
    OptInResponse,
    QuestAnswerRequest,
    QuestAttachSessionRequest,
    QuestMissionResult,
    RewardCatalogResponse,
    RewardOut,
    RewardRedeemRequest,
    RewardRedeemResponse,
    UserQuestOut,
    XpEntryOut,
)
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import BadRequest, NotFound
from bubbles.core.gamification import level_progress
from bubbles.db.repo import achievements as achievements_repo
from bubbles.db.repo import gamification as gamification_repo
from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.db.repo import sessions as sessions_repo
from bubbles.db.repo import xp as xp_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep

router = APIRouter(tags=["gamification"])

_Period = Literal["all", "daily", "weekly", "monthly"]


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
        stats = await gamification_repo.user_activity_stats(conn, user_id=user_id)
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
        stats=stats,
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


def _period_start(period: _Period, now: datetime) -> datetime | None:
    if period == "all":
        return None
    if period == "daily":
        return datetime(now.year, now.month, now.day, tzinfo=UTC)
    if period == "weekly":
        return now - timedelta(days=7)
    return now - timedelta(days=30)  # monthly


@router.get("/leaderboard", response_model=LeaderboardResponse)
async def get_leaderboard(
    user: CurrentUserDep,
    pool: PoolDep,
    period: _Period = "all",
    limit: int = Query(25, ge=1, le=100),
) -> LeaderboardResponse:
    me_id = UUID(user.id)
    now = datetime.now(UTC)
    since = _period_start(period, now)
    async with transaction(pool) as conn:
        if since is None:
            rows = await gamification_repo.leaderboard_top(conn, limit=limit)
            entries = [
                LeaderboardEntry(
                    user_id=r["user_id"],
                    xp=r["total_xp"],
                    level=r["level"],
                    current_streak=r["current_streak"],
                    rank=i + 1,
                )
                for i, r in enumerate(rows)
            ]
            my_rank = await gamification_repo.rank_all_time(conn, user_id=me_id)
            my_g = await gamification_repo.get_or_init_gamification(conn, me_id)
            my_xp = my_g.total_xp
        else:
            rows = await gamification_repo.leaderboard_period(conn, since=since, limit=limit)
            entries = [
                LeaderboardEntry(
                    user_id=r["user_id"],
                    xp=r["xp"],
                    level=r["level"],
                    current_streak=r["current_streak"],
                    rank=i + 1,
                )
                for i, r in enumerate(rows)
            ]
            my_rank = await gamification_repo.rank_period(conn, user_id=me_id, since=since)
            my_xp = await xp_repo.sum_since(conn, user_id=me_id, since=since)
    return LeaderboardResponse(
        period=period, entries=entries, me=LeaderboardMe(rank=my_rank, xp=my_xp)
    )


@router.post("/leaderboard/{user_id}/opt_in", response_model=OptInResponse)
async def set_leaderboard_opt_in(
    user_id: UUID,
    body: OptInRequest,
    user: CurrentUserDep,
    pool: PoolDep,
) -> OptInResponse:
    require_ownership(user, str(user_id))
    async with UnitOfWork(pool) as uow:
        g = await gamification_repo.set_leaderboard_opt_in(
            uow.conn, user_id=user_id, opt_in=body.opt_in
        )
    return OptInResponse(user_id=user_id, leaderboard_opt_in=g.leaderboard_opt_in)


# --- quest missions ---------------------------------------------------------


@router.post("/quests/{user_id}/{user_quest_id}/answer", response_model=QuestMissionResult)
async def answer_quest_mission(
    user_id: UUID,
    user_quest_id: UUID,
    body: QuestAnswerRequest,
    user: CurrentUserDep,
    pool: PoolDep,
) -> QuestMissionResult:
    """Submit one answer for a ``question_set`` mission. Progress = #distinct questions answered."""
    require_ownership(user, str(user_id))
    async with UnitOfWork(pool) as uow:
        uq = await gamification_repo.get_user_quest(uow.conn, user_quest_id)
        if uq is None or uq.user_id != user_id:
            raise NotFound("quest assignment not found")
        qd = await gamification_repo.get_quest_def(uow.conn, uq.quest_id)
        if qd is None:
            raise NotFound("quest definition missing")
        if qd.mission_type != "question_set":
            raise BadRequest("quest is not a question_set mission")
        if uq.is_completed:
            raise BadRequest("quest already completed")
        questions = (qd.brief or {}).get("questions") or []
        valid_ids = {
            str(q["id"]) for q in questions if isinstance(q, dict) and q.get("id") is not None
        }
        if valid_ids and body.question_id not in valid_ids:
            raise BadRequest(f"unknown question id: {body.question_id}")
        updated, newly = await gamification_repo.record_question_answer(
            uow.conn, quest=uq, question_id=body.question_id, answer=body.answer
        )
        if newly:
            await gamification_repo.award_quest_xp_once(
                uow.conn,
                user_quest_id=updated.id,
                user_id=uq.user_id,
                xp_reward=qd.xp_reward,
                title=qd.title,
            )
    return QuestMissionResult(
        user_quest_id=updated.id,
        mission_type=qd.mission_type,
        progress=updated.progress,
        target=updated.target,
        is_completed=updated.is_completed,
        newly_completed=newly,
    )


@router.post("/quests/{user_id}/{user_quest_id}/attach_session", response_model=QuestMissionResult)
async def attach_quest_session(
    user_id: UUID,
    user_quest_id: UUID,
    body: QuestAttachSessionRequest,
    user: CurrentUserDep,
    pool: PoolDep,
) -> QuestMissionResult:
    """Attach a session to a ``conversation`` mission. Completes iff it has ≥ ``brief.min_turns`` user turns."""
    require_ownership(user, str(user_id))
    async with UnitOfWork(pool) as uow:
        uq = await gamification_repo.get_user_quest(uow.conn, user_quest_id)
        if uq is None or uq.user_id != user_id:
            raise NotFound("quest assignment not found")
        qd = await gamification_repo.get_quest_def(uow.conn, uq.quest_id)
        if qd is None:
            raise NotFound("quest definition missing")
        if qd.mission_type != "conversation":
            raise BadRequest("quest is not a conversation mission")
        if uq.is_completed:
            raise BadRequest("quest already completed")
        sess = await sessions_repo.get(uow.conn, body.session_id)
        if sess is None or sess.user_id != user_id:
            raise NotFound("session not found")
        user_turns = await session_logs_repo.role_count(
            uow.conn, session_id=body.session_id, role="user"
        )
        min_turns = max(1, int((qd.brief or {}).get("min_turns", 1)))
        updated, newly = await gamification_repo.complete_conversation_quest(
            uow.conn,
            quest=uq,
            session_id=body.session_id,
            user_turns=user_turns,
            min_turns=min_turns,
        )
        if newly:
            await gamification_repo.award_quest_xp_once(
                uow.conn,
                user_quest_id=updated.id,
                user_id=uq.user_id,
                xp_reward=qd.xp_reward,
                title=qd.title,
            )
    return QuestMissionResult(
        user_quest_id=updated.id,
        mission_type=qd.mission_type,
        progress=updated.progress,
        target=updated.target,
        is_completed=updated.is_completed,
        newly_completed=newly,
    )
