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
