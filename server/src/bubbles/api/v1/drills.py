"""Drill (spaced-repetition) routes.

Three endpoints under ``/v1/drills``:

  GET  /queue                Due cards for the caller. With
                              ``include_upcoming=true`` falls back to
                              upcoming cards when due is empty.
  POST /{id}/review          Apply a Leitner step and award XP on the
                              specific box transition (idempotent on
                              ``(user, source_id=card_id:from->to)``).
  POST /{id}/retire          Silence a card permanently.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, HTTPException

from bubbles.ai.drills import BOX_INTERVALS, next_state
from bubbles.api.v1._schemas import (
    DrillCardOut,
    DrillQueueResponse,
    ReviewDrillRequest,
    ReviewDrillResponse,
)
from bubbles.auth.current_user import CurrentUserDep
from bubbles.core.errors import RateLimited
from bubbles.core.logging import get_logger
from bubbles.db.models import DrillCard
from bubbles.db.repo import drill_cards as drill_repo
from bubbles.db.repo import xp as xp_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep, RateLimiterDep

log = get_logger(__name__)
router = APIRouter(tags=["drills"])

_REVIEW_CAPACITY = 60
_REVIEW_REFILL_PER_S = 60 / 60  # ~60 reviews per minute per user

# XP awards keyed by review semantics. Stored centrally so the test suite
# and any future quest hook agree on the numbers.
_XP_CORRECT_ADVANCE = 15
_XP_WRONG_SHOWUP = 5
_XP_CORRECT_STAY = 0  # box 5 → box 5

_SOURCE_TYPE = "drill_review"
_ACTION_TYPE = "complete_drill_review"


def _to_out(card: DrillCard) -> DrillCardOut:
    """Project a DrillCard row into the API response shape."""
    examples = card.examples or []
    front = ""
    back = ""
    if examples:
        first = examples[0]
        front = str(first.get("snippet", ""))
        back = str(first.get("suggestion", ""))
    return DrillCardOut(
        id=card.id,
        rule_id=card.rule_id,
        category=card.category,
        front=front,
        back=back,
        examples_count=len(examples),
        box=card.box,
        due_at=card.due_at,
        last_reviewed_at=card.last_reviewed_at,
        correct_streak=card.correct_streak,
        total_reviews=card.total_reviews,
        total_correct=card.total_correct,
        retired_at=card.retired_at,
        created_at=card.created_at,
        updated_at=card.updated_at,
    )


@router.get("/drills/queue", response_model=DrillQueueResponse)
async def get_queue(
    user: CurrentUserDep,
    pool: PoolDep,
    limit: int = 20,
    offset: int = 0,
    include_upcoming: bool = False,
) -> DrillQueueResponse:
    uid = UUID(user.id)
    capped = max(1, min(limit, 100))
    offset = max(0, offset)
    async with transaction(pool) as conn:
        due = await drill_repo.list_due(conn, user_id=uid, limit=capped, offset=offset)
        total = await drill_repo.count_due(conn, user_id=uid)
        if not due and include_upcoming:
            due = await drill_repo.list_upcoming(conn, user_id=uid, limit=capped)
    return DrillQueueResponse(items=[_to_out(c) for c in due], total_due=total)


@router.post("/drills/{card_id}/review", response_model=ReviewDrillResponse)
async def review_card(
    card_id: UUID,
    body: ReviewDrillRequest,
    user: CurrentUserDep,
    pool: PoolDep,
    limiter: RateLimiterDep,
) -> ReviewDrillResponse:
    rl = await limiter.check(
        f"drills:review:{user.id}",
        capacity=_REVIEW_CAPACITY,
        refill_per_s=_REVIEW_REFILL_PER_S,
    )
    if not rl.allowed:
        raise RateLimited(rl.retry_after_s)

    uid = UUID(user.id)
    async with UnitOfWork(pool) as uow:
        card = await drill_repo.get(uow.conn, card_id=card_id)
        if card is None:
            raise HTTPException(status_code=404, detail="drill card not found")
        if card.user_id != uid:
            raise HTTPException(status_code=403, detail="not your drill card")
        if card.retired_at is not None:
            raise HTTPException(status_code=409, detail="drill card is retired")

        _new_box, _interval, transition = next_state(card.box, body.result)
        updated = await drill_repo.apply_review(
            uow.conn, card_id=card_id, result=body.result, intervals=BOX_INTERVALS
        )

        if body.result == "correct":
            amount = _XP_CORRECT_STAY if card.box == 5 else _XP_CORRECT_ADVANCE
        else:
            amount = _XP_WRONG_SHOWUP

        xp_awarded = 0
        if amount > 0:
            xp_row = await xp_repo.record(
                uow.conn,
                user_id=uid,
                amount=amount,
                source_type=_SOURCE_TYPE,
                source_id=f"{card_id}:{transition}",
                description=_ACTION_TYPE,
            )
            # ``record`` returns ``None`` if the (user, source_type, source_id)
            # was already awarded — that's the idempotency contract.
            xp_awarded = amount if xp_row is not None else 0

    log.info(
        "drill_review_done",
        user=user.id,
        card=str(card_id),
        transition=transition,
        xp=xp_awarded,
    )
    return ReviewDrillResponse(
        card=_to_out(updated),
        xp_awarded=xp_awarded,
        transition=transition,
    )


@router.post("/drills/{card_id}/retire", response_model=DrillCardOut)
async def retire_card(
    card_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> DrillCardOut:
    uid = UUID(user.id)
    async with UnitOfWork(pool) as uow:
        existing = await drill_repo.get(uow.conn, card_id=card_id)
        if existing is None:
            raise HTTPException(status_code=404, detail="drill card not found")
        if existing.user_id != uid:
            raise HTTPException(status_code=403, detail="not your drill card")
        retired = await drill_repo.retire(uow.conn, card_id=card_id)
        if retired is None:
            raise HTTPException(status_code=409, detail="drill card already retired")
    return _to_out(retired)
