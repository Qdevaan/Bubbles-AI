"""Entities + relations repo integration tests."""

from __future__ import annotations

from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import entities as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


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
