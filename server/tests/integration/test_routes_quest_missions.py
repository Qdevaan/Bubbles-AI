"""H6b: quest-mission endpoints, profile stats{}, action-driven quest progress."""

from __future__ import annotations

import json
from typing import Any
from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.db.repo import gamification as gamification_repo
from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.deps import get_pool

pytestmark = pytest.mark.integration


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )


async def _client(app: FastAPI) -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://t")


async def _make_quest(
    pool: asyncpg.Pool,
    *,
    user_id: UUID,
    mission_type: str,
    action_type: str,
    target: int,
    xp_reward: int,
    brief: dict[str, Any] | None,
) -> tuple[UUID, UUID]:
    async with pool.acquire() as con:
        qd_id = await con.fetchval(
            """
            INSERT INTO quest_definitions
                (title, action_type, target, xp_reward, mission_type, brief)
            VALUES ($1, $2, $3, $4, $5, $6::jsonb) RETURNING id
            """,
            f"{mission_type} quest",
            action_type,
            target,
            xp_reward,
            mission_type,
            json.dumps(brief) if brief is not None else None,
        )
        uq_id = await con.fetchval(
            """
            INSERT INTO user_quests (user_id, quest_id, target, assigned_date)
            VALUES ($1, $2, $3, CURRENT_DATE) RETURNING id
            """,
            user_id,
            qd_id,
            target,
        )
    return qd_id, uq_id


async def test_question_set_mission_answer_flow(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _, uq_id = await _make_quest(
        pool,
        user_id=user_id,
        mission_type="question_set",
        action_type="answer_questions",
        target=2,
        xp_reward=40,
        brief={"questions": [{"id": "q1"}, {"id": "q2"}]},
    )
    _override(app, pool, user_id)
    async with await _client(app) as ac:
        r1 = await ac.post(
            f"/v1/quests/{user_id}/{uq_id}/answer", json={"question_id": "q1", "answer": "a"}
        )
        r2 = await ac.post(
            f"/v1/quests/{user_id}/{uq_id}/answer", json={"question_id": "q2", "answer": "b"}
        )
        bad = await ac.post(
            f"/v1/quests/{user_id}/{uq_id}/answer", json={"question_id": "q9", "answer": "x"}
        )
    assert r1.status_code == 200
    assert r1.json()["progress"] == 1 and r1.json()["is_completed"] is False
    assert r2.status_code == 200
    body2 = r2.json()
    assert (
        body2["progress"] == 2
        and body2["is_completed"] is True
        and body2["newly_completed"] is True
    )
    assert bad.status_code == 400  # quest already completed (and unknown question id)

    async with pool.acquire() as con:
        g = await gamification_repo.get_or_init_gamification(con, user_id)
        xp_rows = await con.fetch(
            "SELECT source_type FROM xp_transactions WHERE user_id = $1", user_id
        )
    assert g.total_xp == 40
    assert [r["source_type"] for r in xp_rows] == ["quest"]


async def test_conversation_mission_attach_session(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _, uq_id = await _make_quest(
        pool,
        user_id=user_id,
        mission_type="conversation",
        action_type="have_conversation",
        target=1,
        xp_reward=60,
        brief={"min_turns": 2},
    )
    async with pool.acquire() as con:
        sid = await con.fetchval(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'active') RETURNING id",
            user_id,
        )
        await session_logs_repo.append(con, session_id=sid, role="user", content="hi")
        await session_logs_repo.append(con, session_id=sid, role="others", content="hello")
        await session_logs_repo.append(con, session_id=sid, role="user", content="more")
    _override(app, pool, user_id)
    async with await _client(app) as ac:
        r = await ac.post(
            f"/v1/quests/{user_id}/{uq_id}/attach_session", json={"session_id": str(sid)}
        )
    assert r.status_code == 200
    body = r.json()
    assert body["is_completed"] is True and body["newly_completed"] is True
    async with pool.acquire() as con:
        g = await gamification_repo.get_or_init_gamification(con, user_id)
    assert g.total_xp == 60


async def test_attach_session_too_short_does_not_complete(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _, uq_id = await _make_quest(
        pool,
        user_id=user_id,
        mission_type="conversation",
        action_type="have_conversation",
        target=1,
        xp_reward=60,
        brief={"min_turns": 5},
    )
    async with pool.acquire() as con:
        sid = await con.fetchval(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'active') RETURNING id",
            user_id,
        )
        await session_logs_repo.append(con, session_id=sid, role="user", content="hi")
    _override(app, pool, user_id)
    async with await _client(app) as ac:
        r = await ac.post(
            f"/v1/quests/{user_id}/{uq_id}/attach_session", json={"session_id": str(sid)}
        )
    assert r.status_code == 200
    assert r.json()["is_completed"] is False
    assert r.json()["newly_completed"] is False


async def test_mission_routes_403_for_other_user(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with await _client(app) as ac:
        r = await ac.post(
            f"/v1/quests/{uuid4()}/{uuid4()}/answer", json={"question_id": "q", "answer": "a"}
        )
    assert r.status_code == 403


async def test_profile_stats_block(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as con:
        await con.execute(
            "INSERT INTO sessions (user_id, title, status, ended_at) VALUES ($1, 's', 'active', now())",
            user_id,
        )
        await con.execute(
            "INSERT INTO memory (user_id, content, memory_type) VALUES ($1, 'm', 'general')",
            user_id,
        )
    _override(app, pool, user_id)
    async with await _client(app) as ac:
        r = await ac.get(f"/v1/gamification/{user_id}")
    assert r.status_code == 200
    stats = r.json()["stats"]
    assert stats["sessions_total"] == 1
    assert stats["sessions_completed"] == 1
    assert stats["memories_total"] == 1
    assert {"entities_total", "mistakes_total", "quests_completed", "achievements_earned"} <= set(
        stats
    )


async def test_bump_quest_progress_by_action(pool: asyncpg.Pool, user_id: UUID) -> None:
    _, uq_id = await _make_quest(
        pool,
        user_id=user_id,
        mission_type="action",
        action_type="use_wingman_turns",
        target=2,
        xp_reward=15,
        brief=None,
    )
    async with pool.acquire() as con:
        q1 = await gamification_repo.bump_quest_progress_by_action(
            con, user_id=user_id, action_type="use_wingman_turns"
        )
        assert q1 is not None and q1.progress == 1 and q1.is_completed is False
        q2 = await gamification_repo.bump_quest_progress_by_action(
            con, user_id=user_id, action_type="use_wingman_turns"
        )
        assert q2 is not None and q2.is_completed is True
        # No matching incomplete quest left.
        q3 = await gamification_repo.bump_quest_progress_by_action(
            con, user_id=user_id, action_type="use_wingman_turns"
        )
        assert q3 is None
        g = await gamification_repo.get_or_init_gamification(con, user_id)
    assert g.total_xp == 15
    _ = uq_id
