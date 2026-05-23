"""DELETE /v1/sessions/{id} + end_session enqueue route integration tests."""

from __future__ import annotations

from typing import Any
from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.deps import get_arq, get_pool

pytestmark = pytest.mark.integration


class FakeArq:
    def __init__(self) -> None:
        self.calls: list[tuple[tuple[Any, ...], dict[str, Any]]] = []

    async def enqueue_job(self, *args: Any, **kwargs: Any) -> str:
        self.calls.append((args, kwargs))
        return str(kwargs.get("_job_id", "job"))


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID, *, arq: FakeArq | None = None) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[get_arq] = lambda: arq
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )


async def _make_session(pool: asyncpg.Pool, owner: UUID) -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'active') RETURNING id",
            owner,
        )
    assert row is not None
    sid: UUID = row["id"]
    return sid


async def test_delete_session_204_then_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r1 = await ac.delete(f"/v1/sessions/{sid}")
        r2 = await ac.delete(f"/v1/sessions/{sid}")
        # save_session reads the session and must now 404 (soft-deleted)
        r3 = await ac.post("/v1/save_session", json={"session_id": str(sid), "transcript": "x"})
    assert r1.status_code == 204
    assert r2.status_code == 404
    assert r3.status_code == 404


async def test_delete_unknown_session_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.delete(f"/v1/sessions/{uuid4()}")
    assert r.status_code == 404


async def test_delete_other_users_session_403(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    other = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", other)
    sid = await _make_session(pool, other)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.delete(f"/v1/sessions/{sid}")
    assert r.status_code == 403


async def test_end_session_with_transcript_enqueues_jobs(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    arq = FakeArq()
    _override(app, pool, user_id, arq=arq)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/end_session",
            json={"session_id": str(sid), "transcript": "User: hi\nAI: hello"},
        )
    assert r.status_code == 200
    names = [kw["_job_name"] for (_, kw) in arq.calls]
    assert names == [
        "compute_session_analytics",
        "extract_knowledge",
        "compute_embeddings",
        "detect_achievements",
        "sentiment_scan",
        "generate_scenarios",
        "materialize_drill_cards",
    ]
    # Every job in this fan-out carries a ``user_id`` kwarg; assert each call's
    # user_id is the caller's. ``score_scenario`` is the only job that lacks
    # ``user_id`` (keyed by ``scenario_id``); it does not fire here.
    assert all(kw.get("user_id") == str(user_id) for (_, kw) in arq.calls if "user_id" in kw)


async def test_end_session_without_transcript_enqueues_nothing(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    arq = FakeArq()
    _override(app, pool, user_id, arq=arq)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post("/v1/end_session", json={"session_id": str(sid)})
    assert r.status_code == 200
    assert arq.calls == []


async def test_end_session_ok_when_queue_down(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id, arq=None)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/end_session",
            json={"session_id": str(sid), "transcript": "User: hi"},
        )
    assert r.status_code == 200


async def test_log_turn_then_replay(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r0 = await ac.post(
            "/v1/log_turn",
            json={"session_id": str(sid), "role": "user", "content": "hey there"},
        )
        r1 = await ac.post(
            "/v1/log_turn",
            json={
                "session_id": str(sid),
                "role": "others",
                "content": "hi",
                "speaker_label": "Sam",
            },
        )
        rep = await ac.get(f"/v1/session_replay/{sid}")
    assert r0.status_code == 201
    assert r0.json()["turn_index"] == 0
    assert r1.json()["turn_index"] == 1
    body = rep.json()
    assert body["session_id"] == str(sid)
    assert [t["role"] for t in body["turns"]] == ["user", "others"]
    assert body["turns"][1]["speaker_label"] == "Sam"


async def test_log_turn_other_user_403(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    other = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", other)
    sid = await _make_session(pool, other)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post("/v1/log_turn", json={"session_id": str(sid), "content": "x"})
    assert r.status_code == 403


async def test_session_replay_unknown_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/session_replay/{uuid4()}")
    assert r.status_code == 404


async def test_end_session_assembles_transcript_from_rows(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    arq = FakeArq()
    _override(app, pool, user_id, arq=arq)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        await ac.post(
            "/v1/log_turn", json={"session_id": str(sid), "role": "user", "content": "hi"}
        )
        await ac.post(
            "/v1/log_turn", json={"session_id": str(sid), "role": "others", "content": "hello"}
        )
        # No transcript in the body — must be assembled from the rows above.
        r = await ac.post("/v1/end_session", json={"session_id": str(sid)})
    assert r.status_code == 200
    assert [kw["_job_name"] for (_, kw) in arq.calls] == [
        "compute_session_analytics",
        "extract_knowledge",
        "compute_embeddings",
        "detect_achievements",
        "sentiment_scan",
        "generate_scenarios",
        "materialize_drill_cards",
    ]
    sent_transcript = arq.calls[0][1]["transcript"]
    assert sent_transcript == "User: hi\nOthers: hello"


async def test_save_session_ephemeral_skips_persist(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/save_session",
            json={"transcript": "should not persist", "is_ephemeral": True},
        )
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ephemeral_skipped"
    assert body["session"] is None
    # No new session row created.
    async with pool.acquire() as con:
        rows = await con.fetch("SELECT id FROM sessions WHERE user_id = $1", user_id)
    assert rows == []


async def test_save_session_creates_session_from_logs(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    logs = [
        {"speaker": "user", "text": "hello there"},
        {"speaker": "others", "text": "hi back"},
        {"speaker": "user", "text": "how are you"},
    ]
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/save_session",
            json={"transcript": "ignored when logs present", "logs": logs, "title": "Test"},
        )
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "saved"
    sess = body["session"]
    assert sess is not None
    sid = UUID(sess["id"])
    async with pool.acquire() as con:
        status = await con.fetchval("SELECT status FROM sessions WHERE id = $1", sid)
        rows = await con.fetch(
            "SELECT turn_index, role, content FROM session_logs "
            "WHERE session_id = $1 ORDER BY turn_index",
            sid,
        )
    assert status == "ended"
    assert [(r["role"], r["content"]) for r in rows] == [
        ("user", "hello there"),
        ("others", "hi back"),
        ("user", "how are you"),
    ]


async def test_save_session_attaches_to_existing(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/save_session",
            json={
                "session_id": str(sid),
                "logs": [{"speaker": "user", "text": "late upload"}],
            },
        )
    assert r.status_code == 200
    body = r.json()
    assert body["session"]["id"] == str(sid)  # same session, ended in place
    async with pool.acquire() as con:
        status = await con.fetchval("SELECT status FROM sessions WHERE id = $1", sid)
        n = await con.fetchval("SELECT COUNT(*)::int FROM session_logs WHERE session_id = $1", sid)
    assert status == "ended"
    assert n == 1


async def test_save_session_ignores_legacy_user_id_field(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    """Flutter still posts ``user_id`` in the body; auth wins, body field is ignored."""
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/save_session",
            json={
                "user_id": str(uuid4()),  # bogus — must not influence ownership
                "transcript": "User: hi",
                "logs": [{"speaker": "user", "text": "hi"}],
            },
        )
    assert r.status_code == 200
    sid = UUID(r.json()["session"]["id"])
    async with pool.acquire() as con:
        owner = await con.fetchval("SELECT user_id FROM sessions WHERE id = $1", sid)
    assert owner == user_id


async def test_end_session_scenario_linked_enqueues_score(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    arq = FakeArq()
    _override(app, pool, user_id, arq=arq)
    sid = await _make_session(pool, user_id)
    async with pool.acquire() as con:
        erow = await con.fetchrow(
            "INSERT INTO entities (user_id, canonical_name, entity_type) "
            "VALUES ($1, 'sarah', 'person') RETURNING id",
            user_id,
        )
        assert erow is not None
        scn = await con.fetchrow(
            """
            INSERT INTO scenarios (
                user_id, target_entity_id, title, situation, goal, success_criteria,
                opening_line, status, session_id
            )
            VALUES ($1, $2, 't', 's', 'g', 'c', 'o', 'started', $3)
            RETURNING id
            """,
            user_id,
            erow["id"],
            sid,
        )
        assert scn is not None
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/end_session",
            json={"session_id": str(sid), "transcript": "User: hi\nAI: hello"},
        )
    assert r.status_code == 200
    names = [kw["_job_name"] for (_, kw) in arq.calls]
    # Scenario-linked sessions still trigger the feed top-up alongside the score.
    assert "generate_scenarios" in names
    assert "score_scenario" in names
    score_call = next(kw for (_, kw) in arq.calls if kw["_job_name"] == "score_scenario")
    assert score_call["scenario_id"] == str(scn["id"])
