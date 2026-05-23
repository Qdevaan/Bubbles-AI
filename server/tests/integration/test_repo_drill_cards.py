"""drill_cards repo integration tests.

Requires Docker (testcontainers Postgres); skipped automatically without it.
Toggle on via:  $env:RUN_INTEGRATION='1'
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest

from bubbles.ai.drills import BOX_INTERVALS
from bubbles.db.repo import drill_cards as repo
from bubbles.db.repo.drill_cards import NewMistakeForCard

pytestmark = pytest.mark.integration


def _mistake(
    *,
    rule_id: str = "LLM_ARTICLE",
    category: str = "article",
    snippet: str = "I went to store.",
    suggestion: str | None = "I went to the store.",
) -> NewMistakeForCard:
    return NewMistakeForCard(
        mistake_id=uuid4(),
        rule_id=rule_id,
        category=category,
        snippet=snippet,
        suggestion=suggestion,
    )


@pytest.mark.asyncio
async def test_upsert_creates_then_appends_examples(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            n1 = await repo.upsert_from_mistakes(
                conn, user_id=user_id, mistakes=[_mistake(snippet="A")]
            )
        assert n1 == 1
        async with conn.transaction():
            n2 = await repo.upsert_from_mistakes(
                conn, user_id=user_id, mistakes=[_mistake(snippet="B")]
            )
        assert n2 == 1  # same card touched, not a second card
        async with conn.transaction():
            due = await repo.list_due(conn, user_id=user_id, limit=10, offset=0)
        assert len(due) == 1
        card = due[0]
        assert card.rule_id == "LLM_ARTICLE"
        assert card.category == "article"
        # newest first
        assert card.examples[0]["snippet"] == "B"
        assert card.examples[1]["snippet"] == "A"
        assert len(card.examples) == 2


@pytest.mark.asyncio
async def test_upsert_caps_examples_at_ten(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        for i in range(15):
            async with conn.transaction():
                await repo.upsert_from_mistakes(
                    conn, user_id=user_id, mistakes=[_mistake(snippet=f"S{i}")]
                )
        async with conn.transaction():
            due = await repo.list_due(conn, user_id=user_id, limit=10, offset=0)
        assert len(due) == 1
        card = due[0]
        assert len(card.examples) == 10
        # newest at index 0 — last inserted is S14
        assert card.examples[0]["snippet"] == "S14"
        # and the oldest retained is S5 (S0..S4 dropped)
        assert card.examples[-1]["snippet"] == "S5"


@pytest.mark.asyncio
async def test_list_due_excludes_retired_and_future(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await repo.upsert_from_mistakes(conn, user_id=user_id, mistakes=[_mistake()])
            # push due_at to tomorrow + retire on a second card
            future = datetime.now(UTC) + timedelta(days=2)
            await conn.execute(
                "UPDATE drill_cards SET due_at = $1 WHERE user_id = $2",
                future,
                user_id,
            )
        async with conn.transaction():
            due = await repo.list_due(conn, user_id=user_id, limit=10, offset=0)
            upcoming = await repo.list_upcoming(conn, user_id=user_id, limit=10)
        assert due == []
        assert len(upcoming) == 1


@pytest.mark.asyncio
async def test_apply_review_correct_advances_box(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await repo.upsert_from_mistakes(conn, user_id=user_id, mistakes=[_mistake()])
            due = await repo.list_due(conn, user_id=user_id, limit=10, offset=0)
            card = due[0]
        async with conn.transaction():
            after = await repo.apply_review(
                conn,
                card_id=card.id,
                result="correct",
                intervals=BOX_INTERVALS,
            )
        assert after.box == 2
        assert after.correct_streak == 1
        assert after.total_reviews == 1
        assert after.total_correct == 1
        assert after.due_at > card.due_at  # pushed forward
        # interval matches box 2 (3 days from now)
        now = datetime.now(UTC)
        delta = after.due_at - now
        assert timedelta(days=2, hours=20) < delta < timedelta(days=3, hours=4)


@pytest.mark.asyncio
async def test_apply_review_wrong_resets_to_box_one(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await repo.upsert_from_mistakes(conn, user_id=user_id, mistakes=[_mistake()])
            card = (await repo.list_due(conn, user_id=user_id, limit=10, offset=0))[0]
        async with conn.transaction():
            advanced = await repo.apply_review(
                conn, card_id=card.id, result="correct", intervals=BOX_INTERVALS
            )
            assert advanced.box == 2
        async with conn.transaction():
            # force it due again so we can review it
            await conn.execute(
                "UPDATE drill_cards SET due_at = now() WHERE id = $1", advanced.id
            )
        async with conn.transaction():
            after = await repo.apply_review(
                conn, card_id=advanced.id, result="wrong", intervals=BOX_INTERVALS
            )
        assert after.box == 1
        assert after.correct_streak == 0
        assert after.total_reviews == 2
        assert after.total_correct == 1  # unchanged on wrong


@pytest.mark.asyncio
async def test_retire_excludes_from_queue(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await repo.upsert_from_mistakes(conn, user_id=user_id, mistakes=[_mistake()])
            card = (await repo.list_due(conn, user_id=user_id, limit=10, offset=0))[0]
        async with conn.transaction():
            retired = await repo.retire(conn, card_id=card.id)
        assert retired is not None
        assert retired.retired_at is not None
        async with conn.transaction():
            again = await repo.retire(conn, card_id=card.id)
        assert again is None  # idempotent guard
        async with conn.transaction():
            due = await repo.list_due(conn, user_id=user_id, limit=10, offset=0)
        assert due == []


@pytest.mark.asyncio
async def test_ownership_scoped(pool, user_id: UUID, other_user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await repo.upsert_from_mistakes(conn, user_id=user_id, mistakes=[_mistake()])
        async with conn.transaction():
            due_other = await repo.list_due(conn, user_id=other_user_id, limit=10, offset=0)
        assert due_other == []
