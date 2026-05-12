"""Analytics read endpoints + feedback write.

- POST /v1/save_feedback                       — record user feedback (idempotent)
- GET  /v1/session_analytics/{session_id}      — cached per-session metrics row
- GET  /v1/coaching_report/{session_id}        — cached per-session coaching report
- GET  /v1/digest/{user_id}                    — recent activity digest (day|week)
- GET  /v1/communication_trends/{user_id}      — session_analytics aggregated by ISO week

The metrics row and coaching report are written by the ``compute_session_analytics``
worker; until it has run for a session these GETs return 404.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Query

from bubbles.api.v1._schemas import (
    CoachingReportOut,
    CommunicationTrendsResponse,
    DigestEntity,
    DigestHighlight,
    DigestResponse,
    DigestSession,
    DigestTask,
    PerformanceSummaryResponse,
    SaveFeedbackRequest,
    SaveFeedbackResponse,
    SessionAnalyticsOut,
    WeeklyTrendOut,
)
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import NotFound
from bubbles.core.performance import PerformanceInputs, compute_performance
from bubbles.db.repo import analytics as analytics_repo
from bubbles.db.repo import feedback as feedback_repo
from bubbles.db.repo import gamification as gamification_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep

router = APIRouter(tags=["analytics"])


def _group_by_week(rows: list[asyncpg.Record]) -> list[WeeklyTrendOut]:
    buckets: dict[str, dict[str, float | int]] = {}
    sentiment: dict[str, tuple[float, int]] = {}
    for r in rows:
        iso = r["computed_at"].isocalendar()
        key = f"{iso[0]}-W{iso[1]:02d}"
        b = buckets.setdefault(
            key,
            {"sessions": 0, "total_turns": 0, "user_words": 0, "ai_words": 0, "duration": 0.0},
        )
        b["sessions"] = int(b["sessions"]) + 1
        b["total_turns"] = int(b["total_turns"]) + int(r["total_turns"] or 0)
        b["user_words"] = int(b["user_words"]) + int(r["user_word_count"] or 0)
        b["ai_words"] = int(b["ai_words"]) + int(r["assistant_word_count"] or 0)
        b["duration"] = float(b["duration"]) + float(r["total_duration_seconds"] or 0)
        score = r["avg_sentiment_score"]
        if score is not None:
            s_sum, s_n = sentiment.get(key, (0.0, 0))
            sentiment[key] = (s_sum + float(score), s_n + 1)
    out: list[WeeklyTrendOut] = []
    for key, b in buckets.items():
        s_sum, s_n = sentiment.get(key, (0.0, 0))
        out.append(
            WeeklyTrendOut(
                week=key,
                sessions=int(b["sessions"]),
                total_turns=int(b["total_turns"]),
                user_words=int(b["user_words"]),
                ai_words=int(b["ai_words"]),
                avg_sentiment_score=(s_sum / s_n) if s_n else None,
                total_duration_seconds=float(b["duration"]),
            )
        )
    out.sort(key=lambda w: w.week, reverse=True)
    return out


@router.post("/save_feedback", response_model=SaveFeedbackResponse)
async def save_feedback(
    body: SaveFeedbackRequest, user: CurrentUserDep, pool: PoolDep
) -> SaveFeedbackResponse:
    # No HTML sanitization of `comment`: v5 never renders it as HTML, and the
    # schema bounds its length. The row's user_id is always the caller's id.
    if body.idempotency_key:
        async with transaction(pool) as conn:
            existing = await feedback_repo.find_by_idempotency_key(conn, key=body.idempotency_key)
        if existing is not None:
            return SaveFeedbackResponse(status="ok", idempotent=True)
    rating = body.value if body.feedback_type == "star" else None
    try:
        async with UnitOfWork(pool) as uow:
            await feedback_repo.insert(
                uow.conn,
                user_id=UUID(user.id),
                feedback_type=body.feedback_type,
                session_id=body.session_id,
                log_id=body.session_log_id,
                consultant_log_id=body.consultant_log_id,
                value=body.value,
                rating=rating,
                comment=body.comment,
                idempotency_key=body.idempotency_key,
            )
    except asyncpg.UniqueViolationError:
        return SaveFeedbackResponse(status="ok", idempotent=True)
    return SaveFeedbackResponse(status="ok")


@router.get("/session_analytics/{session_id}", response_model=SessionAnalyticsOut)
async def get_session_analytics(
    session_id: UUID, user: CurrentUserDep, pool: PoolDep
) -> SessionAnalyticsOut:
    async with transaction(pool) as conn:
        row = await analytics_repo.get_session_analytics(conn, session_id=session_id)
    if row is None:
        raise NotFound("session analytics not found")
    require_ownership(user, str(row.user_id))
    return SessionAnalyticsOut(
        session_id=row.session_id,
        total_turns=row.total_turns,
        user_turns=row.user_turns,
        others_turns=row.others_turns,
        llm_turns=row.llm_turns,
        user_word_count=row.user_word_count,
        assistant_word_count=row.assistant_word_count,
        average_latency_ms=row.average_latency_ms,
        avg_advice_latency_ms=row.avg_advice_latency_ms,
        total_duration_seconds=row.total_duration_seconds,
        memories_saved=row.memories_saved,
        events_extracted=row.events_extracted,
        highlights_created=row.highlights_created,
        avg_sentiment_score=row.avg_sentiment_score,
        dominant_sentiment=row.dominant_sentiment,
        topic_summary=row.topic_summary,
        sentiment_trend=[],
        computed_at=row.computed_at,
    )


@router.get("/coaching_report/{session_id}", response_model=CoachingReportOut)
async def get_coaching_report(
    session_id: UUID, user: CurrentUserDep, pool: PoolDep
) -> CoachingReportOut:
    async with transaction(pool) as conn:
        row = await analytics_repo.get_coaching_report(conn, session_id=session_id)
    if row is None:
        raise NotFound("coaching report not found")
    require_ownership(user, str(row.user_id))
    tone_scores = {
        k: int(v)
        for k, v in row.report_content.items()
        if isinstance(v, int | float) and not isinstance(v, bool)
    }
    return CoachingReportOut(
        session_id=row.session_id,
        model_used=row.model_used,
        user_talk_pct=row.user_talk_pct,
        others_talk_pct=row.others_talk_pct,
        key_topics=row.key_topics,
        key_decisions=row.key_decisions,
        action_items=row.action_items,
        follow_up_people=row.follow_up_people,
        filler_words=row.filler_words,
        filler_word_count=row.filler_word_count,
        tone_summary=row.tone_summary,
        engagement_trend=row.engagement_trend,
        suggestions=row.suggestions,
        strengths=row.strengths,
        areas_of_improvement=row.areas_of_improvement,
        report_text=row.report_text,
        tone_scores=tone_scores,
        generated_at=row.generated_at,
    )


@router.get("/digest/{user_id}", response_model=DigestResponse)
async def get_digest(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
    period: Literal["day", "week"] = "week",
) -> DigestResponse:
    require_ownership(user, str(user_id))
    days = 1 if period == "day" else 7
    since = datetime.now(UTC) - timedelta(days=days)
    async with transaction(pool) as conn:
        sessions = await analytics_repo.digest_sessions(conn, user_id=user_id, since=since)
        count = (
            await conn.fetchval(
                "SELECT count(*) FROM sessions "
                "WHERE user_id = $1 AND created_at >= $2 AND deleted_at IS NULL",
                user_id,
                since,
            )
            or 0
        )
        tasks = await analytics_repo.digest_pending_tasks(conn, user_id=user_id)
        entities = await analytics_repo.digest_top_entities(conn, user_id=user_id)
        highlights = await analytics_repo.digest_recent_highlights(
            conn, user_id=user_id, since=since
        )
    return DigestResponse(
        period=period,
        user_id=user_id,
        sessions_count=int(count),
        recent_sessions=[DigestSession(**dict(r)) for r in sessions],
        pending_tasks=[DigestTask(**dict(r)) for r in tasks],
        top_entities=[DigestEntity(**dict(r)) for r in entities],
        recent_highlights=[DigestHighlight(**dict(r)) for r in highlights],
    )


@router.get("/communication_trends/{user_id}", response_model=CommunicationTrendsResponse)
async def get_communication_trends(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
    weeks: int = Query(8, ge=1, le=52),
) -> CommunicationTrendsResponse:
    require_ownership(user, str(user_id))
    since = datetime.now(UTC) - timedelta(weeks=weeks)
    async with transaction(pool) as conn:
        rows = await analytics_repo.trends_since(conn, user_id=user_id, since=since)
    trends = _group_by_week(rows)
    return CommunicationTrendsResponse(
        user_id=user_id, weeks_requested=weeks, weeks_available=len(trends), trends=trends
    )


async def _performance_inputs(
    pool: PoolDep, *, user_id: UUID, since: datetime, until: datetime | None
) -> PerformanceInputs:
    async with transaction(pool) as conn:
        win = await analytics_repo.performance_window(
            conn, user_id=user_id, since=since, until=until
        )
        assigned, completed = await gamification_repo.quest_completion_between(
            conn, user_id=user_id, since_date=since.date()
        )
        g = await gamification_repo.get_or_init_gamification(conn, user_id)
    return PerformanceInputs(
        session_count=win["session_count"],
        avg_sentiment=win["avg_sentiment"],
        avg_user_talk_pct=win["avg_user_talk_pct"],
        avg_filler_count=win["avg_filler_count"],
        quests_assigned=assigned,
        quests_completed=completed,
        current_streak=g.current_streak,
    )


@router.get("/performance_summary/{user_id}", response_model=PerformanceSummaryResponse)
async def get_performance_summary(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> PerformanceSummaryResponse:
    require_ownership(user, str(user_id))
    now = datetime.now(tz=UTC)
    this_week = await _performance_inputs(
        pool, user_id=user_id, since=now - timedelta(days=7), until=None
    )
    prev_week = await _performance_inputs(
        pool, user_id=user_id, since=now - timedelta(days=14), until=now - timedelta(days=7)
    )
    summary = compute_performance(this_week)
    prev = compute_performance(prev_week)
    return PerformanceSummaryResponse(
        performance_tier=summary.performance_tier,
        recommended_difficulty=summary.recommended_difficulty,
        focus_areas=summary.focus_areas,
        ai_coaching_tip=summary.ai_coaching_tip,
        weekly_score=summary.weekly_score,
        score_delta=round(summary.weekly_score - prev.weekly_score, 1),
        breakdown=summary.breakdown,
    )
