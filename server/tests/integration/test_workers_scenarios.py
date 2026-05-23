"""generate_scenarios + score_scenario worker integration tests."""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any
from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import scenarios as scenarios_repo
from bubbles.workers.jobs import generate_scenarios

pytestmark = pytest.mark.integration


async def _entity(pool: asyncpg.Pool, owner: UUID, name: str = "sarah") -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO entities (user_id, canonical_name, display_name, entity_type) "
            "VALUES ($1, $2, $2, 'person') RETURNING id",
            owner,
            name,
        )
    assert row is not None
    eid: UUID = row["id"]
    return eid


def _draft(eid: UUID) -> scenarios_repo.NewScenario:
    return scenarios_repo.NewScenario(
        target_entity_id=eid,
        title="t",
        situation="s",
        goal="g",
        success_criteria="c",
        difficulty="medium",
        role_mode="default",
        opening_line="o",
        source={"entity_id": str(eid), "tasks": [], "events": []},
    )


async def test_generate_scenarios_noops_when_feed_full(
    pool: asyncpg.Pool, user_id: UUID, monkeypatch: pytest.MonkeyPatch
) -> None:
    eid = await _entity(pool, user_id)
    from bubbles.db.uow import UnitOfWork

    async with UnitOfWork(pool) as uow:
        await scenarios_repo.create_many(
            uow.conn, user_id=user_id, rows=[_draft(eid) for _ in range(5)]
        )

    async def _fail(*_a: Any, **_kw: Any) -> list[scenarios_repo.NewScenario]:
        raise AssertionError("generate must not be called when the feed is full")

    monkeypatch.setattr(generate_scenarios.scenario_gen, "generate", _fail)
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)
    }
    created = await generate_scenarios.run(ctx, user_id=str(user_id))
    assert created == 0


async def test_generate_scenarios_fills_gap(
    pool: asyncpg.Pool, user_id: UUID, monkeypatch: pytest.MonkeyPatch
) -> None:
    eid = await _entity(pool, user_id)

    async def _two(*_a: Any, **kw: Any) -> list[scenarios_repo.NewScenario]:
        return [_draft(eid) for _ in range(kw["count"])]

    monkeypatch.setattr(generate_scenarios.scenario_gen, "generate", _two)
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)
    }
    created = await generate_scenarios.run(ctx, user_id=str(user_id))
    assert created == 5
    async with pool.acquire() as con:
        n = await con.fetchval("SELECT COUNT(*)::int FROM scenarios WHERE user_id = $1", user_id)
    assert n == 5


async def test_generate_scenarios_partial_fill(
    pool: asyncpg.Pool, user_id: UUID, monkeypatch: pytest.MonkeyPatch
) -> None:
    eid = await _entity(pool, user_id)
    from bubbles.db.uow import UnitOfWork

    async with UnitOfWork(pool) as uow:
        await scenarios_repo.create_many(
            uow.conn, user_id=user_id, rows=[_draft(eid) for _ in range(3)]
        )

    async def _n(*_a: Any, **kw: Any) -> list[scenarios_repo.NewScenario]:
        return [_draft(eid) for _ in range(kw["count"])]

    monkeypatch.setattr(generate_scenarios.scenario_gen, "generate", _n)
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)
    }
    created = await generate_scenarios.run(ctx, user_id=str(user_id))
    assert created == 2


async def test_score_scenario_writes_result_and_awards_xp(
    pool: asyncpg.Pool, user_id: UUID, monkeypatch: pytest.MonkeyPatch
) -> None:
    from bubbles.ai import extraction
    from bubbles.db.repo import session_logs as session_logs_repo
    from bubbles.db.uow import UnitOfWork
    from bubbles.workers.jobs import score_scenario

    eid = await _entity(pool, user_id)
    async with pool.acquire() as con:
        srow = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'ended') RETURNING id",
            user_id,
        )
    assert srow is not None
    sid: UUID = srow["id"]
    async with pool.acquire() as con:
        await session_logs_repo.append(con, session_id=sid, role="user", content="hi")
        await session_logs_repo.append(con, session_id=sid, role="others", content="hello")
    async with UnitOfWork(pool) as uow:
        created = await scenarios_repo.create_many(uow.conn, user_id=user_id, rows=[_draft(eid)])
        await scenarios_repo.mark_started(uow.conn, scenario_id=created[0].id, session_id=sid)

    async def _pass(*_a: Any, **_kw: Any) -> tuple[bool | None, str | None]:
        return (True, "well done")

    monkeypatch.setattr(extraction, "evaluate_conversation_mission", _pass)
    monkeypatch.setattr(score_scenario, "evaluate_conversation_mission", _pass)
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)
    }
    result = await score_scenario.run(ctx, scenario_id=str(created[0].id))
    # Re-run must not double-award XP.
    await score_scenario.run(ctx, scenario_id=str(created[0].id))

    assert result["scored"] is True
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "SELECT status, passed, score_feedback FROM scenarios WHERE id = $1", created[0].id
        )
        xp_n = await con.fetchval(
            "SELECT COUNT(*)::int FROM xp_transactions WHERE user_id = $1 AND source_type = 'scenario'",
            user_id,
        )
    assert row is not None
    assert row["status"] == "completed"
    assert row["passed"] is True
    assert row["score_feedback"] == "well done"
    assert xp_n == 1  # idempotent — second run deduped


async def test_score_scenario_returns_no_linked_session_when_unlinked(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    from bubbles.workers.jobs import score_scenario

    eid = await _entity(pool, user_id)
    from bubbles.db.uow import UnitOfWork

    async with UnitOfWork(pool) as uow:
        created = await scenarios_repo.create_many(uow.conn, user_id=user_id, rows=[_draft(eid)])
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)
    }
    result = await score_scenario.run(ctx, scenario_id=str(created[0].id))
    assert result == {"scored": False, "reason": "no linked session"}


async def test_score_scenario_returns_empty_transcript_when_no_turns(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    from bubbles.db.uow import UnitOfWork
    from bubbles.workers.jobs import score_scenario

    eid = await _entity(pool, user_id)
    async with pool.acquire() as con:
        srow = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'ended') RETURNING id",
            user_id,
        )
    assert srow is not None
    sid: UUID = srow["id"]
    async with UnitOfWork(pool) as uow:
        created = await scenarios_repo.create_many(uow.conn, user_id=user_id, rows=[_draft(eid)])
        await scenarios_repo.mark_started(uow.conn, scenario_id=created[0].id, session_id=sid)
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)
    }
    result = await score_scenario.run(ctx, scenario_id=str(created[0].id))
    assert result == {"scored": False, "reason": "empty transcript"}


async def test_score_scenario_preserves_started_on_eval_failure(
    pool: asyncpg.Pool, user_id: UUID, monkeypatch: pytest.MonkeyPatch
) -> None:
    from bubbles.ai import extraction
    from bubbles.db.repo import session_logs as session_logs_repo
    from bubbles.db.uow import UnitOfWork
    from bubbles.workers.jobs import score_scenario

    eid = await _entity(pool, user_id)
    async with pool.acquire() as con:
        srow = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'ended') RETURNING id",
            user_id,
        )
    assert srow is not None
    sid: UUID = srow["id"]
    async with pool.acquire() as con:
        await session_logs_repo.append(con, session_id=sid, role="user", content="hi")
    async with UnitOfWork(pool) as uow:
        created = await scenarios_repo.create_many(uow.conn, user_id=user_id, rows=[_draft(eid)])
        await scenarios_repo.mark_started(uow.conn, scenario_id=created[0].id, session_id=sid)

    async def _fail(*_a: Any, **_kw: Any) -> tuple[bool | None, str | None]:
        return (None, None)

    monkeypatch.setattr(extraction, "evaluate_conversation_mission", _fail)
    monkeypatch.setattr(score_scenario, "evaluate_conversation_mission", _fail)
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)
    }
    result = await score_scenario.run(ctx, scenario_id=str(created[0].id))
    assert result == {"scored": False, "reason": "eval_failed"}
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "SELECT status, passed FROM scenarios WHERE id = $1", created[0].id
        )
    assert row is not None
    assert row["status"] == "started"  # NOT 'completed' -- retry path preserved
    assert row["passed"] is None
