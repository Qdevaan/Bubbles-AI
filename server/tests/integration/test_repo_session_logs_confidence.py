"""session_logs_repo.update_confidence_bulk integration tests."""

from __future__ import annotations

from uuid import UUID

import pytest

from bubbles.db.repo import session_logs as session_logs_repo

pytestmark = pytest.mark.integration


async def _seed_log(conn, *, session_id: UUID, turn_index: int, role: str = "user") -> None:
    await conn.execute(
        """
        INSERT INTO session_logs (session_id, turn_index, role, content)
        VALUES ($1, $2, $3, 'x')
        """,
        session_id,
        turn_index,
        role,
    )


@pytest.mark.asyncio
async def test_update_confidence_bulk_updates_matching_turns(
    pool, session_id: UUID
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await _seed_log(conn, session_id=session_id, turn_index=0)
            await _seed_log(conn, session_id=session_id, turn_index=1)
            await _seed_log(conn, session_id=session_id, turn_index=2)
        async with conn.transaction():
            n = await session_logs_repo.update_confidence_bulk(
                conn,
                session_id=session_id,
                items=[(0, 0.9), (1, 0.5), (2, 0.1)],
            )
        rows = await conn.fetch(
            "SELECT turn_index, confidence FROM session_logs WHERE session_id = $1 "
            "ORDER BY turn_index",
            session_id,
        )
    assert n == 3
    assert [(r["turn_index"], float(r["confidence"])) for r in rows] == [
        (0, 0.9),
        (1, 0.5),
        (2, 0.1),
    ]


@pytest.mark.asyncio
async def test_update_confidence_bulk_silently_ignores_unknown_turn_index(
    pool, session_id: UUID
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await _seed_log(conn, session_id=session_id, turn_index=0)
        async with conn.transaction():
            n = await session_logs_repo.update_confidence_bulk(
                conn,
                session_id=session_id,
                items=[(0, 0.7), (99, 0.4)],  # turn 99 doesn't exist
            )
    # Only 1 row matched; the unknown turn_index is silently skipped.
    assert n == 1


@pytest.mark.asyncio
async def test_update_confidence_bulk_does_not_touch_other_sessions(
    pool, session_id: UUID, other_session_id: UUID
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await _seed_log(conn, session_id=session_id, turn_index=0)
            await _seed_log(conn, session_id=other_session_id, turn_index=0)
        async with conn.transaction():
            await session_logs_repo.update_confidence_bulk(
                conn,
                session_id=session_id,
                items=[(0, 0.95)],
            )
        own = await conn.fetchval(
            "SELECT confidence FROM session_logs WHERE session_id = $1 AND turn_index = 0",
            session_id,
        )
        other = await conn.fetchval(
            "SELECT confidence FROM session_logs WHERE session_id = $1 AND turn_index = 0",
            other_session_id,
        )
    assert float(own) == 0.95
    assert other is None


@pytest.mark.asyncio
async def test_update_confidence_bulk_empty_items_is_noop(
    pool, session_id: UUID
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await _seed_log(conn, session_id=session_id, turn_index=0)
        async with conn.transaction():
            n = await session_logs_repo.update_confidence_bulk(
                conn, session_id=session_id, items=[]
            )
    assert n == 0
