"""H7 performance_summary route + H8 backfill_session_entities job."""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any
from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.deps import get_pool
from bubbles.workers.jobs import backfill_session_entities, extract_knowledge

pytestmark = pytest.mark.integration


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )


async def test_performance_summary_defaults(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/performance_summary/{user_id}")
    assert r.status_code == 200
    body = r.json()
    # No sessions/quests/streak -> the neutral composite (see test_performance.py).
    assert body["performance_tier"] == "steady"
    assert body["weekly_score"] == 3.5
    assert body["score_delta"] == 0.0
    assert set(body["breakdown"]) == {
        "engagement",
        "sentiment",
        "session_frequency",
        "quest_completion",
        "streak",
        "filler_control",
    }


async def test_performance_summary_other_user_403(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/performance_summary/{uuid4()}")
    assert r.status_code == 403


async def _make_session(pool: asyncpg.Pool, owner: UUID) -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'active') RETURNING id",
            owner,
        )
    assert row is not None
    sid: UUID = row["id"]
    return sid


async def test_backfill_session_entities(
    pool: asyncpg.Pool, user_id: UUID, monkeypatch: pytest.MonkeyPatch
) -> None:
    with_logs = await _make_session(pool, user_id)
    without_logs = await _make_session(pool, user_id)
    async with pool.acquire() as con:
        await session_logs_repo.append(con, session_id=with_logs, role="user", content="met acme")
        await session_logs_repo.append(con, session_id=with_logs, role="others", content="ok")

    async def _fake_extract(_router: Any, _transcript: str) -> dict[str, Any]:
        return {"entities": [{"canonical_name": "acme", "entity_type": "org"}], "relations": []}

    monkeypatch.setattr(extract_knowledge, "extract_entities", _fake_extract)
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)
    }
    result = await backfill_session_entities.run(ctx, limit=50)
    assert result["sessions_processed"] == 1

    async with pool.acquire() as con:
        linked = await con.fetch(
            "SELECT session_id FROM session_entities WHERE session_id = ANY($1::uuid[])",
            [with_logs, without_logs],
        )
    assert [r["session_id"] for r in linked] == [with_logs]

    # Re-run: the session now has links, so nothing left to process.
    result2 = await backfill_session_entities.run(ctx, limit=50)
    assert result2["sessions_processed"] == 0
