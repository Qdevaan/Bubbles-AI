"""Progress dashboard route.

Single omnibus endpoint ``GET /v1/dashboard?range={30d|90d|365d}``.
Returns time-bucketed series (XP, sessions, mistakes, sentiment,
talk-time) and a snapshot summary with previous-window deltas. Reads
only; bound by ``(user_id, time)`` indexes on the source tables.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Literal, cast
from uuid import UUID

from fastapi import APIRouter, Query

from bubbles.api.v1._dashboard_helpers import RANGES, delta_pct, resolve_range
from bubbles.api.v1._schemas import (
    BucketPointFOut,
    BucketPointOut,
    DashboardResponse,
    DashboardSeries,
    DashboardSummary,
    DashboardWindow,
    MetricDelta,
)
from bubbles.auth.current_user import CurrentUserDep
from bubbles.core.errors import BadRequest, RateLimited
from bubbles.core.logging import get_logger
from bubbles.db.repo import dashboard as dashboard_repo
from bubbles.db.uow import transaction
from bubbles.deps import PoolDep, RateLimiterDep

log = get_logger(__name__)
router = APIRouter(tags=["dashboard"])

_RATE_CAPACITY = 30
_RATE_REFILL_PER_S = 30 / 60  # ~30 dashboard fetches per minute per user


def _to_int_buckets(rows: list[dashboard_repo.BucketPoint]) -> list[BucketPointOut]:
    return [BucketPointOut(bucket=r.bucket, value=r.value) for r in rows]


def _to_float_buckets(rows: list[dashboard_repo.BucketPointF]) -> list[BucketPointFOut]:
    return [BucketPointFOut(bucket=r.bucket, value=r.value) for r in rows]


def _seconds_buckets_to_minutes(
    rows: list[dashboard_repo.BucketPoint],
) -> list[BucketPointOut]:
    """Round seconds to whole minutes for the response shape."""
    return [BucketPointOut(bucket=r.bucket, value=round(r.value / 60)) for r in rows]


@router.get("/dashboard", response_model=DashboardResponse)
async def get_dashboard(
    user: CurrentUserDep,
    pool: PoolDep,
    limiter: RateLimiterDep,
    range_arg: str = Query("30d", alias="range"),
) -> DashboardResponse:
    rl = await limiter.check(
        f"dashboard:{user.id}",
        capacity=_RATE_CAPACITY,
        refill_per_s=_RATE_REFILL_PER_S,
    )
    if not rl.allowed:
        raise RateLimited(rl.retry_after_s)

    if range_arg not in RANGES:
        raise BadRequest(f"unknown range: {range_arg!r}")
    range_lit = cast(Literal["30d", "90d", "365d"], range_arg)

    cur_start, cur_end, prev_start, prev_end, step, granularity = resolve_range(
        range_arg, datetime.now(UTC)
    )

    uid = UUID(user.id)
    async with transaction(pool) as conn:
        xp_rows = await dashboard_repo.series_xp(
            conn, user_id=uid, start=cur_start, end=cur_end, step=step
        )
        sess_rows = await dashboard_repo.series_sessions(
            conn, user_id=uid, start=cur_start, end=cur_end, step=step
        )
        mist_rows = await dashboard_repo.series_mistakes(
            conn, user_id=uid, start=cur_start, end=cur_end, step=step
        )
        sent_rows = await dashboard_repo.series_sentiment(
            conn, user_id=uid, start=cur_start, end=cur_end, step=step
        )
        talk_rows = await dashboard_repo.series_talk_time(
            conn, user_id=uid, start=cur_start, end=cur_end, step=step
        )
        sw = await dashboard_repo.summary_window(
            conn,
            user_id=uid,
            cur_start=cur_start,
            cur_end=cur_end,
            prev_start=prev_start,
            prev_end=prev_end,
        )
        snap = await dashboard_repo.snapshot(conn, user_id=uid)

    cur_sent = sw.cur_sentiment if sw.cur_sentiment is not None else 0.0
    prev_sent = sw.prev_sentiment if sw.prev_sentiment is not None else 0.0
    cur_talk_min = sw.cur_talk_seconds / 60
    prev_talk_min = sw.prev_talk_seconds / 60

    summary = DashboardSummary(
        total_xp=MetricDelta(
            current=float(sw.cur_xp),
            previous=float(sw.prev_xp),
            delta_pct=delta_pct(sw.cur_xp, sw.prev_xp),
        ),
        sessions=MetricDelta(
            current=float(sw.cur_sessions),
            previous=float(sw.prev_sessions),
            delta_pct=delta_pct(sw.cur_sessions, sw.prev_sessions),
        ),
        mistakes=MetricDelta(
            current=float(sw.cur_mistakes),
            previous=float(sw.prev_mistakes),
            delta_pct=delta_pct(sw.cur_mistakes, sw.prev_mistakes),
        ),
        avg_sentiment=MetricDelta(
            current=cur_sent,
            previous=prev_sent,
            delta_pct=delta_pct(cur_sent, prev_sent),
        ),
        talk_time_minutes=MetricDelta(
            current=round(cur_talk_min, 1),
            previous=round(prev_talk_min, 1),
            delta_pct=delta_pct(cur_talk_min, prev_talk_min),
        ),
        drill_mastery_pct=snap.drill_mastery_pct,
        current_streak=snap.current_streak,
        level=snap.level,
        due_drill_count=snap.due_drill_count,
    )

    series = DashboardSeries(
        xp_per_bucket=_to_int_buckets(xp_rows),
        sessions_per_bucket=_to_int_buckets(sess_rows),
        mistakes_per_bucket=_to_int_buckets(mist_rows),
        avg_sentiment_per_bucket=_to_float_buckets(sent_rows),
        talk_time_minutes_per_bucket=_seconds_buckets_to_minutes(talk_rows),
    )

    log.info("dashboard_done", user=user.id, range=range_arg, granularity=granularity)

    return DashboardResponse(
        range=range_lit,
        granularity=cast(Literal["daily", "weekly", "monthly"], granularity),
        window=DashboardWindow(start=cur_start, end=cur_end),
        summary=summary,
        series=series,
    )
