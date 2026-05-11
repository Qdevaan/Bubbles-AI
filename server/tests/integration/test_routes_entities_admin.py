"""graph_export + entity_timeline route integration tests."""

from __future__ import annotations

from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.db.repo import entities as entities_repo
from bubbles.db.uow import UnitOfWork
from bubbles.deps import get_pool

pytestmark = pytest.mark.integration


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )


async def test_graph_export_nodes_and_links(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with UnitOfWork(pool) as uow:
        a = await entities_repo.upsert_entity(
            uow.conn,
            user_id=user_id,
            canonical_name="a",
            entity_type="person",
            display_name="A",
        )
        b = await entities_repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="b", entity_type="org"
        )
        await entities_repo.upsert_relation(
            uow.conn,
            user_id=user_id,
            source_id=a.id,
            target_id=b.id,
            relation="works_at",
        )
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        resp = await ac.get(f"/v1/graph_export/{user_id}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["user_id"] == str(user_id)
    assert {n["id"] for n in body["nodes"]} == {str(a.id), str(b.id)}
    assert len(body["links"]) == 1
    assert body["links"][0]["relation"] == "works_at"


async def test_graph_export_drops_dangling_links_and_limits(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with UnitOfWork(pool) as uow:
        keep = await entities_repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="keep", entity_type="x"
        )
        # bump keep's mention_count so it wins the limit cut
        await entities_repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="keep", entity_type="x"
        )
        drop = await entities_repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="drop", entity_type="x"
        )
        await entities_repo.upsert_relation(
            uow.conn,
            user_id=user_id,
            source_id=keep.id,
            target_id=drop.id,
            relation="r",
        )
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        resp = await ac.get(f"/v1/graph_export/{user_id}", params={"limit": 1})
    assert resp.status_code == 200
    body = resp.json()
    assert [n["id"] for n in body["nodes"]] == [str(keep.id)]
    assert body["links"] == []  # the only link points at the dropped node


async def test_graph_export_filters_by_entity_type(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with UnitOfWork(pool) as uow:
        await entities_repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="alice", entity_type="person"
        )
        await entities_repo.upsert_entity(
            uow.conn, user_id=user_id, canonical_name="acme", entity_type="org"
        )
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        resp = await ac.get(f"/v1/graph_export/{user_id}", params={"entity_type": "person"})
    assert resp.status_code == 200
    assert {n["type"] for n in resp.json()["nodes"]} == {"person"}


async def test_graph_export_empty_for_fresh_user(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        resp = await ac.get(f"/v1/graph_export/{user_id}")
    assert resp.status_code == 200
    assert resp.json() == {"user_id": str(user_id), "nodes": [], "links": []}


async def test_graph_export_forbidden_for_other_user(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        resp = await ac.get(f"/v1/graph_export/{uuid4()}")
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "forbidden"
