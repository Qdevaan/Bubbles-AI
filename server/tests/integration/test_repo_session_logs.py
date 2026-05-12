"""session_logs repo: monotonic turn_index, transcript assembly, ordering."""

from __future__ import annotations

from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import session_logs as repo

pytestmark = pytest.mark.integration


async def _make_session(pool: asyncpg.Pool, owner: UUID) -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'active') RETURNING id",
            owner,
        )
    assert row is not None
    sid: UUID = row["id"]
    return sid


async def test_append_assigns_monotonic_turn_index(pool: asyncpg.Pool, user_id: UUID) -> None:
    sid = await _make_session(pool, user_id)
    async with pool.acquire() as con:
        a = await repo.append(con, session_id=sid, role="others", content="hi there")
        b = await repo.append(con, session_id=sid, role="user", content="hello")
        c = await repo.append(con, session_id=sid, role="llm", content="say something kind")
    assert (a.turn_index, b.turn_index, c.turn_index) == (0, 1, 2)


async def test_turn_count_and_listing_order(pool: asyncpg.Pool, user_id: UUID) -> None:
    sid = await _make_session(pool, user_id)
    async with pool.acquire() as con:
        await repo.append(con, session_id=sid, role="others", content="one")
        await repo.append(con, session_id=sid, role="user", content="two")
        await repo.append(con, session_id=sid, role="llm", content="three")
        assert await repo.turn_count(con, session_id=sid) == 3
        rows = await repo.list_for_session(con, session_id=sid)
    assert [r.content for r in rows] == ["one", "two", "three"]
    assert [r.turn_index for r in rows] == [0, 1, 2]


async def test_assemble_transcript_role_labels_and_last_n(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    sid = await _make_session(pool, user_id)
    async with pool.acquire() as con:
        await repo.append(con, session_id=sid, role="user", content="hey")
        await repo.append(con, session_id=sid, role="others", content="hi")
        await repo.append(con, session_id=sid, role="llm", content="ask how they are")
        await repo.append(con, session_id=sid, role="others", content="  ")  # blank — skipped
        full = await repo.assemble_transcript(con, session_id=sid)
        last2 = await repo.assemble_transcript(con, session_id=sid, last_n=2)
    assert full == "User: hey\nOthers: hi\nAI: ask how they are"
    # last_n counts rows (incl. the blank one), rendered oldest-first, blanks dropped
    assert last2 == "AI: ask how they are"


async def test_cascade_delete_with_session(pool: asyncpg.Pool, user_id: UUID) -> None:
    sid = await _make_session(pool, user_id)
    async with pool.acquire() as con:
        await repo.append(con, session_id=sid, role="others", content="x")
        await con.execute("DELETE FROM sessions WHERE id = $1", sid)
        n = await con.fetchval("SELECT COUNT(*) FROM session_logs WHERE session_id = $1", sid)
    assert n == 0


async def test_append_rejects_bad_role(pool: asyncpg.Pool, user_id: UUID) -> None:
    sid = await _make_session(pool, user_id)
    async with pool.acquire() as con:
        with pytest.raises(ValueError, match="invalid role"):
            await repo.append(con, session_id=sid, role="robot", content="x")
