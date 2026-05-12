"""extract_knowledge worker — persists entities + session links."""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any
from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import entities as entities_repo
from bubbles.workers.jobs import extract_knowledge

pytestmark = pytest.mark.integration


async def _make_session(pool: asyncpg.Pool, user_id: UUID) -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'active') RETURNING id",
            user_id,
        )
    assert row is not None
    sid: UUID = row["id"]
    return sid


async def test_extract_knowledge_writes_session_links(
    pool: asyncpg.Pool, user_id: UUID, monkeypatch: pytest.MonkeyPatch
) -> None:
    sid = await _make_session(pool, user_id)

    async def _fake_extract(_router: Any, _transcript: str) -> dict[str, Any]:
        return {"entities": [{"canonical_name": "acme", "entity_type": "org"}], "relations": []}

    monkeypatch.setattr(extract_knowledge, "extract_entities", _fake_extract)

    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)
    }
    result = await extract_knowledge.run(
        ctx, user_id=str(user_id), session_id=str(sid), transcript="we met acme"
    )

    assert result["entities"] == 1
    assert result["links"] == 1
    async with pool.acquire() as con:
        rows = await con.fetch("SELECT entity_id FROM session_entities WHERE session_id = $1", sid)
        ents = await entities_repo.list_for_user(con, user_id=user_id)
    assert len(rows) == 1
    assert rows[0]["entity_id"] == ents[0].id
