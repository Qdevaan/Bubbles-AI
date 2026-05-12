"""xp_transactions repo integration tests."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import xp as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def test_record_inserts_and_returns_row(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        tx = await repo.record(
            uow.conn, user_id=user_id, amount=30, source_type="session_complete", source_id="s1"
        )
    assert tx is not None
    assert tx.amount == 30
    assert tx.source_type == "session_complete"
    assert tx.source_id == "s1"


async def test_record_is_idempotent_on_source_id(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        first = await repo.record(
            uow.conn, user_id=user_id, amount=30, source_type="session_complete", source_id="s1"
        )
        second = await repo.record(
            uow.conn, user_id=user_id, amount=30, source_type="session_complete", source_id="s1"
        )
    assert first is not None
    assert second is None  # deduped


async def test_record_without_source_id_always_inserts(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        a = await repo.record(uow.conn, user_id=user_id, amount=10, source_type="manual")
        b = await repo.record(uow.conn, user_id=user_id, amount=10, source_type="manual")
        rows = await uow.conn.fetch("SELECT id FROM xp_transactions WHERE user_id=$1", user_id)
    assert a is not None and b is not None
    assert len(rows) == 2


async def test_record_rejects_negative_amount(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        with pytest.raises(ValueError, match="non-negative"):
            await repo.record(uow.conn, user_id=user_id, amount=-5, source_type="manual")


async def test_recent_orders_newest_first(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        await repo.record(uow.conn, user_id=user_id, amount=10, source_type="a", source_id="1")
        await repo.record(uow.conn, user_id=user_id, amount=20, source_type="b", source_id="2")
        await repo.record(uow.conn, user_id=user_id, amount=30, source_type="c", source_id="3")
        rows = await repo.recent(uow.conn, user_id=user_id, limit=2)
    assert [r.amount for r in rows] == [30, 20]


async def test_sum_since_counts_positive_only_within_window(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    now = datetime.now(UTC)
    async with UnitOfWork(pool) as uow:
        # one inside the window, one negative inside, one positive but old
        await uow.conn.execute(
            "INSERT INTO xp_transactions (user_id, amount, source_type, created_at)"
            " VALUES ($1, 50, 'in', $2)",
            user_id,
            now - timedelta(hours=1),
        )
        await uow.conn.execute(
            "INSERT INTO xp_transactions (user_id, amount, source_type, created_at)"
            " VALUES ($1, -20, 'spend', $2)",
            user_id,
            now - timedelta(hours=1),
        )
        await uow.conn.execute(
            "INSERT INTO xp_transactions (user_id, amount, source_type, created_at)"
            " VALUES ($1, 999, 'old', $2)",
            user_id,
            now - timedelta(days=10),
        )
        total = await repo.sum_since(uow.conn, user_id=user_id, since=now - timedelta(days=1))
    assert total == 50
