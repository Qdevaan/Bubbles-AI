"""Integration tests for the feedback repo."""

from __future__ import annotations

from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import feedback as feedback_repo

pytestmark = pytest.mark.integration


async def test_insert_and_find_by_idempotency_key(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        row = await feedback_repo.insert(
            conn,
            user_id=user_id,
            feedback_type="thumbs",
            value=1,
            comment="great",
            idempotency_key="abc-123",
        )
        assert row.user_id == user_id
        assert row.feedback_type == "thumbs"
        assert row.value == 1
        found = await feedback_repo.find_by_idempotency_key(conn, key="abc-123")
        assert found == row.id
        missing = await feedback_repo.find_by_idempotency_key(conn, key="nope")
        assert missing is None


async def test_duplicate_idempotency_key_raises_unique_violation(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    async with pool.acquire() as conn:
        await feedback_repo.insert(
            conn, user_id=user_id, feedback_type="star", value=5, idempotency_key="dup-1"
        )
        with pytest.raises(asyncpg.UniqueViolationError):
            await feedback_repo.insert(
                conn, user_id=user_id, feedback_type="star", value=4, idempotency_key="dup-1"
            )


async def test_insert_without_idempotency_key(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        row = await feedback_repo.insert(conn, user_id=user_id, feedback_type="text", comment="hi")
        assert row.idempotency_key is None
        assert row.value is None
