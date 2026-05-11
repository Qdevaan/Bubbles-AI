"""Entities + relations repo integration tests."""

from __future__ import annotations

from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import entities as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def _make_session(pool: asyncpg.Pool, user_id: UUID, title: str = "s") -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, $2, 'active') RETURNING id",
            user_id,
            title,
        )
    assert row is not None
    sid: UUID = row["id"]
    return sid


async def test_upsert_increments_mentions(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        first = await repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="alice", entity_type="person"
        )
    async with UnitOfWork(pool) as uow:
        second = await repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="alice", entity_type="person"
        )
    assert first.id == second.id
    assert second.mention_count == 2


async def test_upsert_relation_strengthens(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        a = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="a", entity_type="x")
        b = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="b", entity_type="x")
        r1 = await repo.upsert_relation(
            uow.conn, user_id=user_id, source_id=a.id, target_id=b.id, relation="knows"
        )
        r2 = await repo.upsert_relation(
            uow.conn, user_id=user_id, source_id=a.id, target_id=b.id, relation="knows"
        )
    assert r1.id == r2.id
    assert r2.strength > r1.strength


async def test_search_by_name(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        await repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="alice", entity_type="person"
        )
        await repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="bob", entity_type="person"
        )
    async with pool.acquire() as con:
        hits = await repo.search_by_name(con, user_id=user_id, query="ali")
    assert len(hits) == 1
    assert hits[0].canonical_name == "alice"


async def test_link_session_entity_upserts(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        ent = await repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="acme", entity_type="org"
        )
    sid = await _make_session(pool, user_id)
    async with UnitOfWork(pool) as uow:
        await repo.link_session_entity(uow.conn, session_id=sid, entity_id=ent.id, user_id=user_id)
    async with UnitOfWork(pool) as uow:
        await repo.link_session_entity(uow.conn, session_id=sid, entity_id=ent.id, user_id=user_id)
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "SELECT mention_count FROM session_entities WHERE session_id=$1 AND entity_id=$2",
            sid,
            ent.id,
        )
    assert row is not None
    assert row["mention_count"] == 2


async def test_timeline_returns_only_linked_sessions(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        ent = await repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="bob", entity_type="person"
        )
    linked = await _make_session(pool, user_id, "linked")
    _other = await _make_session(pool, user_id, "other")  # not linked -> must not appear
    async with UnitOfWork(pool) as uow:
        await repo.link_session_entity(
            uow.conn, session_id=linked, entity_id=ent.id, user_id=user_id
        )
    async with pool.acquire() as con:
        rows = await repo.timeline(con, entity_id=ent.id, user_id=user_id)
    assert [r["session_id"] for r in rows] == [linked]


async def test_timeline_excludes_deleted_sessions(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        ent = await repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="c", entity_type="x"
        )
    sid = await _make_session(pool, user_id)
    async with UnitOfWork(pool) as uow:
        await repo.link_session_entity(uow.conn, session_id=sid, entity_id=ent.id, user_id=user_id)
    async with pool.acquire() as con:
        await con.execute("UPDATE sessions SET deleted_at = now() WHERE id = $1", sid)
        rows = await repo.timeline(con, entity_id=ent.id, user_id=user_id)
    assert rows == []


async def test_events_and_tasks_mentioning(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as con:
        await con.execute(
            "INSERT INTO events (user_id, title) VALUES ($1, 'Lunch with Acme team')", user_id
        )
        await con.execute("INSERT INTO events (user_id, title) VALUES ($1, 'Unrelated')", user_id)
        await con.execute(
            "INSERT INTO tasks (user_id, title) VALUES ($1, 'Email acme contract')", user_id
        )
        ev = await repo.events_mentioning(con, user_id=user_id, name="acme")
        tk = await repo.tasks_mentioning(con, user_id=user_id, name="ACME")
    assert [e["title"] for e in ev] == ["Lunch with Acme team"]
    assert [t["title"] for t in tk] == ["Email acme contract"]


async def test_list_all_relations_orders_by_strength(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        a = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="a", entity_type="x")
        b = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="b", entity_type="x")
        c = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="c", entity_type="x")
        await repo.upsert_relation(
            uow.conn, user_id=user_id, source_id=a.id, target_id=b.id, relation="weak", strength=0.5
        )
        await repo.upsert_relation(
            uow.conn,
            user_id=user_id,
            source_id=a.id,
            target_id=c.id,
            relation="strong",
            strength=9.0,
        )
    async with pool.acquire() as con:
        rels = await repo.list_all_relations(con, user_id=user_id)
    assert [r.relation for r in rels] == ["strong", "weak"]


async def test_list_for_user_include_archived(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        _e1 = await repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="live", entity_type="x"
        )
        e2 = await repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="gone", entity_type="x"
        )
        await repo.soft_delete(uow.conn, entity_id=e2.id, user_id=user_id)
    async with pool.acquire() as con:
        default = await repo.list_for_user(con, user_id=user_id)
        with_archived = await repo.list_for_user(con, user_id=user_id, include_archived=True)
    assert {e.canonical_name for e in default} == {"live"}
    assert {e.canonical_name for e in with_archived} == {"live", "gone"}
