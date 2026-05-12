"""Integration tests for the analytics HTTP routes."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.deps import get_pool

pytestmark = pytest.mark.integration


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )


async def _new_user(pool: asyncpg.Pool) -> UUID:
    uid = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", uid)
    return uid


async def _new_session(pool: asyncpg.Pool, user_id: UUID, **cols: object) -> UUID:
    sid = uuid4()
    keys = ", ".join(["id", "user_id", *cols.keys()])
    placeholders = ", ".join(f"${i + 1}" for i in range(2 + len(cols)))
    async with pool.acquire() as conn:
        await conn.execute(
            f"INSERT INTO sessions ({keys}) VALUES ({placeholders})", sid, user_id, *cols.values()
        )
    return sid


async def test_save_feedback_happy_path(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        r = await c.post("/v1/save_feedback", json={"feedback_type": "thumbs", "value": 1})
        assert r.status_code == 200
        assert r.json() == {"status": "ok", "idempotent": False}
    async with pool.acquire() as conn:
        n = await conn.fetchval("SELECT count(*) FROM feedback WHERE user_id = $1", user_id)
        assert n == 1


async def test_save_feedback_idempotent_replay(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        body = {"feedback_type": "star", "value": 5, "idempotency_key": "k1"}
        r1 = await c.post("/v1/save_feedback", json=body)
        assert r1.json()["idempotent"] is False
        r2 = await c.post("/v1/save_feedback", json=body)
        assert r2.status_code == 200
        assert r2.json()["idempotent"] is True
    async with pool.acquire() as conn:
        n = await conn.fetchval("SELECT count(*) FROM feedback WHERE idempotency_key = 'k1'")
        assert n == 1


async def test_save_feedback_bad_value_is_422(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        r = await c.post("/v1/save_feedback", json={"feedback_type": "star", "value": 99})
        assert r.status_code == 422


async def test_save_feedback_bad_type_is_422(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        r = await c.post("/v1/save_feedback", json={"feedback_type": "nope"})
        assert r.status_code == 422


async def test_session_analytics_404_when_absent(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        r = await c.get(f"/v1/session_analytics/{uuid4()}")
        assert r.status_code == 404


async def test_session_analytics_happy_and_cross_user_403(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    sid = await _new_session(pool, user_id, status="ended")
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO session_analytics (session_id, user_id, total_turns, user_word_count) "
            "VALUES ($1, $2, 5, 12)",
            sid,
            user_id,
        )
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        r = await c.get(f"/v1/session_analytics/{sid}")
        assert r.status_code == 200
        body = r.json()
        assert body["total_turns"] == 5
        assert body["user_word_count"] == 12
        assert body["sentiment_trend"] == []
        assert body["avg_sentiment_score"] is None
    other = await _new_user(pool)
    _override(app, pool, other)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        r = await c.get(f"/v1/session_analytics/{sid}")
        assert r.status_code == 403


async def test_coaching_report_404_then_happy(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    sid = await _new_session(pool, user_id, status="ended")
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        assert (await c.get(f"/v1/coaching_report/{sid}")).status_code == 404
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO coaching_reports "
            "(session_id, user_id, model_used, user_talk_pct, key_topics, filler_word_count, "
            " report_content) "
            "VALUES ($1, $2, 'analytics.coaching', 55.0, ARRAY['budget'], 4, "
            "'{\"tone_clarity\": 8}'::jsonb)",
            sid,
            user_id,
        )
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        r = await c.get(f"/v1/coaching_report/{sid}")
        assert r.status_code == 200
        body = r.json()
        assert body["user_talk_pct"] == 55.0
        assert body["key_topics"] == ["budget"]
        assert body["tone_scores"] == {"tone_clarity": 8}
    other = await _new_user(pool)
    _override(app, pool, other)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        assert (await c.get(f"/v1/coaching_report/{sid}")).status_code == 403


async def test_digest_period_window_and_cross_user_403(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    now = datetime.now(UTC)
    await _new_session(
        pool, user_id, title="recent", status="ended", created_at=now - timedelta(hours=1)
    )
    await _new_session(pool, user_id, title="old", created_at=now - timedelta(days=20))
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO tasks (user_id, title, status) VALUES ($1, 'todo', 'pending')", user_id
        )
        await conn.execute(
            "INSERT INTO entities (user_id, canonical_name, display_name, entity_type, mention_count) "
            "VALUES ($1, 'alice', 'Alice', 'person', 9)",
            user_id,
        )
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        r = await c.get(f"/v1/digest/{user_id}", params={"period": "week"})
        assert r.status_code == 200
        body = r.json()
        assert body["period"] == "week"
        assert [s["title"] for s in body["recent_sessions"]] == ["recent"]
        assert body["sessions_count"] == 1
        assert [t["title"] for t in body["pending_tasks"]] == ["todo"]
        assert [e["display_name"] for e in body["top_entities"]] == ["Alice"]
        r_day = await c.get(f"/v1/digest/{user_id}", params={"period": "day"})
        assert r_day.status_code == 200
    other = await _new_user(pool)
    _override(app, pool, other)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        assert (await c.get(f"/v1/digest/{user_id}")).status_code == 403


async def test_communication_trends_grouping_and_validation(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    now = datetime.now(UTC)
    s1 = await _new_session(pool, user_id, status="ended")
    s2 = await _new_session(pool, user_id, status="ended")
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO session_analytics (session_id, user_id, total_turns, user_word_count, "
            "assistant_word_count, computed_at) VALUES ($1, $2, 3, 5, 4, $3), ($4, $2, 7, 10, 6, $5)",
            s1,
            user_id,
            now - timedelta(days=1),
            s2,
            now - timedelta(days=2),
        )
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        r = await c.get(f"/v1/communication_trends/{user_id}", params={"weeks": 8})
        assert r.status_code == 200
        body = r.json()
        assert body["weeks_requested"] == 8
        total_turns = sum(t["total_turns"] for t in body["trends"])
        assert total_turns == 10
        assert (
            await c.get(f"/v1/communication_trends/{user_id}", params={"weeks": 0})
        ).status_code == 422
        assert (
            await c.get(f"/v1/communication_trends/{user_id}", params={"weeks": 53})
        ).status_code == 422
    other = await _new_user(pool)
    _override(app, pool, other)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        assert (await c.get(f"/v1/communication_trends/{user_id}")).status_code == 403
