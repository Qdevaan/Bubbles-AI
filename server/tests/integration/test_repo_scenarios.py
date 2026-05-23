"""scenarios repo integration tests."""

from __future__ import annotations

from uuid import UUID, uuid4

import asyncpg
import pytest

from bubbles.db.repo import scenarios as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def _entity(pool: asyncpg.Pool, owner: UUID, name: str = "sarah") -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO entities (user_id, canonical_name, entity_type) "
            "VALUES ($1, $2, 'person') RETURNING id",
            owner,
            name,
        )
    assert row is not None
    eid: UUID = row["id"]
    return eid


async def _session(pool: asyncpg.Pool, owner: UUID) -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'active') RETURNING id",
            owner,
        )
    assert row is not None
    sid: UUID = row["id"]
    return sid


def _draft(
    entity_id: UUID, *, title: str = "Ask for a raise", tasks: list[str] | None = None
) -> repo.NewScenario:
    return repo.NewScenario(
        target_entity_id=entity_id,
        title=title,
        situation="You sit down with your manager.",
        goal="Practice negotiating",
        success_criteria="Stayed calm and made the ask",
        difficulty="medium",
        role_mode="busy and direct",
        opening_line="You wanted to see me?",
        source={"entity_id": str(entity_id), "tasks": tasks or [], "events": []},
    )


async def test_create_many_and_list(pool: asyncpg.Pool, user_id: UUID) -> None:
    eid = await _entity(pool, user_id)
    async with UnitOfWork(pool) as uow:
        created = await repo.create_many(uow.conn, user_id=user_id, rows=[_draft(eid)])
    assert len(created) == 1
    assert created[0].status == "suggested"
    assert created[0].target_entity_id == eid
    assert created[0].source["tasks"] == []
    async with UnitOfWork(pool) as uow:
        rows = await repo.list_for_user(uow.conn, user_id=user_id, status="suggested")
    assert [r.id for r in rows] == [created[0].id]


async def test_count_active_only_counts_suggested(pool: asyncpg.Pool, user_id: UUID) -> None:
    eid = await _entity(pool, user_id)
    async with UnitOfWork(pool) as uow:
        created = await repo.create_many(
            uow.conn, user_id=user_id, rows=[_draft(eid), _draft(eid, title="b")]
        )
        await repo.mark_dismissed(uow.conn, scenario_id=created[0].id)
        n = await repo.count_active(uow.conn, user_id=user_id)
    assert n == 1


async def test_used_source_ids_skips_dismissed(pool: asyncpg.Pool, user_id: UUID) -> None:
    eid = await _entity(pool, user_id)
    t1, t2 = str(uuid4()), str(uuid4())
    async with UnitOfWork(pool) as uow:
        created = await repo.create_many(
            uow.conn,
            user_id=user_id,
            rows=[_draft(eid, tasks=[t1]), _draft(eid, title="b", tasks=[t2])],
        )
        await repo.mark_dismissed(uow.conn, scenario_id=created[1].id)
        tasks, events = await repo.used_source_ids(uow.conn, user_id=user_id)
    assert tasks == {UUID(t1)}
    assert events == set()


async def test_mark_started_links_session_and_guards_status(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    eid = await _entity(pool, user_id)
    sid = await _session(pool, user_id)
    async with UnitOfWork(pool) as uow:
        created = await repo.create_many(uow.conn, user_id=user_id, rows=[_draft(eid)])
        started = await repo.mark_started(uow.conn, scenario_id=created[0].id, session_id=sid)
        again = await repo.mark_started(uow.conn, scenario_id=created[0].id, session_id=sid)
    assert started is not None and started.status == "started"
    assert started.session_id == sid
    assert again is None  # already started — status guard fires


async def test_mark_completed_and_get_by_session(pool: asyncpg.Pool, user_id: UUID) -> None:
    eid = await _entity(pool, user_id)
    sid = await _session(pool, user_id)
    async with UnitOfWork(pool) as uow:
        created = await repo.create_many(uow.conn, user_id=user_id, rows=[_draft(eid)])
        await repo.mark_started(uow.conn, scenario_id=created[0].id, session_id=sid)
        completed = await repo.mark_completed(
            uow.conn, scenario_id=created[0].id, passed=True, feedback="great"
        )
        by_session = await repo.get_by_session(uow.conn, session_id=sid)
    assert completed is not None and completed.status == "completed"
    assert completed.passed is True
    assert by_session is not None and by_session.id == created[0].id


async def test_mark_completed_rejects_non_started(pool: asyncpg.Pool, user_id: UUID) -> None:
    eid = await _entity(pool, user_id)
    async with UnitOfWork(pool) as uow:
        created = await repo.create_many(uow.conn, user_id=user_id, rows=[_draft(eid)])
        # still 'suggested' — never started — must not complete
        bad = await repo.mark_completed(
            uow.conn, scenario_id=created[0].id, passed=True, feedback="x"
        )
    assert bad is None


async def test_get_returns_row_and_none(pool: asyncpg.Pool, user_id: UUID) -> None:
    eid = await _entity(pool, user_id)
    async with UnitOfWork(pool) as uow:
        created = await repo.create_many(uow.conn, user_id=user_id, rows=[_draft(eid)])
        found = await repo.get(uow.conn, created[0].id)
        missing = await repo.get(uow.conn, uuid4())
    assert found is not None and found.id == created[0].id
    assert missing is None
