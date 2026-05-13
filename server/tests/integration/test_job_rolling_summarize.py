"""rolling_summarize worker — appends ``[Turn N] {summary}`` to sessions.summary."""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any
from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.workers.jobs import rolling_summarize

pytestmark = pytest.mark.integration


async def _make_session(pool: asyncpg.Pool, owner: UUID, *, summary: str | None = None) -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            """
            INSERT INTO sessions (user_id, title, status, summary)
            VALUES ($1, 's', 'active', $2)
            RETURNING id
            """,
            owner,
            summary,
        )
    assert row is not None
    sid: UUID = row["id"]
    return sid


async def test_rolling_summarize_appends_fragment(
    pool: asyncpg.Pool, user_id: UUID, monkeypatch: pytest.MonkeyPatch
) -> None:
    sid = await _make_session(pool, user_id)
    async with pool.acquire() as con:
        await session_logs_repo.append(con, session_id=sid, role="user", content="hi")
        await session_logs_repo.append(con, session_id=sid, role="others", content="hello")

    async def _fake_summary(_router: Any, _text: str) -> str:
        return "they greeted each other"

    monkeypatch.setattr(rolling_summarize, "generate_summary", _fake_summary)
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool),
    }
    result = await rolling_summarize.run(
        ctx, user_id=str(user_id), session_id=str(sid), turn_index=20
    )
    assert result["updated"] == 1

    async with pool.acquire() as con:
        summary = await con.fetchval("SELECT summary FROM sessions WHERE id = $1", sid)
    assert summary == "[Turn 20] they greeted each other"


async def test_rolling_summarize_appends_with_separator(
    pool: asyncpg.Pool, user_id: UUID, monkeypatch: pytest.MonkeyPatch
) -> None:
    sid = await _make_session(pool, user_id, summary="[Turn 20] first round")
    async with pool.acquire() as con:
        await session_logs_repo.append(con, session_id=sid, role="user", content="more")

    async def _fake_summary(_router: Any, _text: str) -> str:
        return "second round"

    monkeypatch.setattr(rolling_summarize, "generate_summary", _fake_summary)
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool),
    }
    await rolling_summarize.run(ctx, user_id=str(user_id), session_id=str(sid), turn_index=40)
    async with pool.acquire() as con:
        summary = await con.fetchval("SELECT summary FROM sessions WHERE id = $1", sid)
    assert summary == "[Turn 20] first round\n---\n[Turn 40] second round"


async def test_rolling_summarize_skips_on_empty_summary(
    pool: asyncpg.Pool, user_id: UUID, monkeypatch: pytest.MonkeyPatch
) -> None:
    sid = await _make_session(pool, user_id, summary="keep me")
    async with pool.acquire() as con:
        await session_logs_repo.append(con, session_id=sid, role="user", content="hi")

    async def _empty(_router: Any, _text: str) -> str:
        return ""

    monkeypatch.setattr(rolling_summarize, "generate_summary", _empty)
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool),
    }
    result = await rolling_summarize.run(
        ctx, user_id=str(user_id), session_id=str(sid), turn_index=20
    )
    assert result["updated"] == 0
    async with pool.acquire() as con:
        summary = await con.fetchval("SELECT summary FROM sessions WHERE id = $1", sid)
    assert summary == "keep me"
