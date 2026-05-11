# v5 Port — Batch 1: Entity Routes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port v2's entity-related HTTP endpoints into `server/` (Bubbles Brain API v5) — `GET /v1/graph_export/{user_id}`, `GET /v1/entity_timeline/{entity_id}`, `DELETE /v1/sessions/{id}`, `DELETE /v1/memories/{id}` — improving on v2 (JWT-derived ownership, soft deletes, a real `session_entities` link table, pagination).

**Architecture:** New Alembic revision `0002` adds a `session_entities` link table; the `extract_knowledge` ARQ job populates it; `entities_repo.timeline()` is rewritten to use it. New repo methods + Pydantic schemas + four route handlers, all following v5's existing patterns (typed errors, `CurrentUserDep` + `require_ownership`, `PoolDep` + `UnitOfWork`/`transaction`, Pydantic `_Base` schemas). Route tests are integration tests (testcontainers Postgres) that override `get_pool` and `current_user`.

**Tech Stack:** Python 3.13, FastAPI, asyncpg, Alembic (async, raw-SQL), Pydantic v2, pytest + pytest-asyncio + testcontainers, ruff, mypy --strict, `uv` + `make`.

**Spec:** `docs/superpowers/specs/2026-05-11-v5-port-batch1-entity-routes-design.md`

**Working directory for all commands:** `server/` (the v5 package root — has the `Makefile`, `pyproject.toml`, `alembic.ini`). Run integration tests with `RUN_INTEGRATION=1` (needs Docker). Plain `make test` (no env var) still runs lint + mypy + the unit tests and must stay green.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `server/alembic/versions/2026_05_11_0002_session_entities.py` | create | Forward migration: `session_entities` table + indexes; reversible. |
| `server/tests/integration/fixtures/baseline.sql` | modify | Add `events`, `tasks`, `session_entities` table DDL so the test DB matches prod. |
| `server/tests/integration/conftest.py` | modify | Add `events`, `tasks`, `session_entities` to the teardown `DROP` list. |
| `server/src/bubbles/db/repo/entities.py` | modify | `+link_session_entity()`, rewrite `timeline()`, `+events_mentioning()`, `+tasks_mentioning()`, `+list_all_relations()`, add `include_archived` param to `list_for_user()`. |
| `server/src/bubbles/db/repo/memories.py` | modify | `+get(conn, memory_id) -> Memory | None`. |
| `server/src/bubbles/workers/jobs/extract_knowledge.py` | modify | Call `link_session_entity` for each extracted entity; report `links` count. |
| `server/src/bubbles/api/v1/_schemas.py` | modify | `+GraphNode`, `+GraphLink`, `+GraphExportResponse`, `+TimelineSession`, `+TimelineEvent`, `+TimelineTask`, `+EntityTimelineResponse`. |
| `server/src/bubbles/api/v1/entities.py` | modify | `+GET /graph_export/{user_id}`, `+GET /entity_timeline/{entity_id}`. |
| `server/src/bubbles/api/v1/sessions.py` | modify | `+DELETE /sessions/{session_id}`. |
| `server/src/bubbles/api/v1/memories.py` | create | `DELETE /memories/{memory_id}`. |
| `server/src/bubbles/api/router.py` | modify | Mount `memories_router`. |
| `server/tests/integration/test_repo_entities.py` | modify | Tests for the new entities-repo methods + rewritten `timeline`. |
| `server/tests/integration/test_repo_memories.py` | create | Tests for `memories_repo.get` + `soft_delete`. |
| `server/tests/integration/test_worker_extract_knowledge.py` | create | Test that the worker writes `session_entities` rows. |
| `server/tests/integration/test_routes_entities_admin.py` | create | Route tests for `graph_export` + `entity_timeline`. |
| `server/tests/integration/test_routes_sessions.py` | create | Route test for `DELETE /sessions/{id}`. |
| `server/tests/integration/test_routes_memories.py` | create | Route test for `DELETE /memories/{id}`. |
| `Documentation/server-vs-server_v2-review.md` | modify | §5: move entity routes out of "gaps"; note the link table + backfill follow-up. |

---

## Task 1: Schema — `session_entities` migration + test fixtures

**Files:**
- Create: `server/alembic/versions/2026_05_11_0002_session_entities.py`
- Modify: `server/tests/integration/fixtures/baseline.sql`
- Modify: `server/tests/integration/conftest.py`

- [ ] **Step 1: Write the Alembic migration**

Create `server/alembic/versions/2026_05_11_0002_session_entities.py`:

```python
"""session_entities link table

Tracks which entities were mentioned in which sessions, so the entity
timeline can show real linked sessions instead of v2's single
``sessions.target_entity_id`` + name-match heuristic.

The table starts empty; old sessions are not backfilled here (a one-off
backfill worker job is a separate follow-up). Going forward the
``extract_knowledge`` ARQ job writes a row per (session, entity) it extracts.

Revision ID: 0002
Revises: 0001
Create Date: 2026-05-11 21:30:00 UTC
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS session_entities (
            session_id    uuid        NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            entity_id     uuid        NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
            user_id       uuid        NOT NULL,
            mention_count integer     NOT NULL DEFAULT 1,
            first_seen_at timestamptz NOT NULL DEFAULT now(),
            last_seen_at  timestamptz NOT NULL DEFAULT now(),
            PRIMARY KEY (session_id, entity_id)
        );
        CREATE INDEX IF NOT EXISTS session_entities_entity_idx
            ON session_entities (entity_id, last_seen_at DESC);
        CREATE INDEX IF NOT EXISTS session_entities_user_idx
            ON session_entities (user_id, last_seen_at DESC);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX IF EXISTS session_entities_user_idx;
        DROP INDEX IF EXISTS session_entities_entity_idx;
        DROP TABLE IF EXISTS session_entities;
        """
    )
```

- [ ] **Step 2: Verify the migration is well-formed (offline SQL render)**

Run (from `server/`): `uv run alembic upgrade head --sql`
Expected: prints SQL including `CREATE TABLE ... session_entities ...` and exits 0 (no Python errors, revision graph resolves `0001 -> 0002`).

- [ ] **Step 3: Add the new tables to `baseline.sql`**

The integration test DB is built from `server/tests/integration/fixtures/baseline.sql` (NOT from migrations — mirrors how `0001` is a no-op against the existing Supabase schema). Append these three tables. Insert them **after** the `entities` and `sessions` table definitions (so the FKs resolve) — a good spot is right before the final/`memory` table block, or at the end of the file *if* `entities` and `sessions` are already defined above (they are). Add:

```sql
-- events (mentioned-by-name in entity timeline; no entity FK in prod schema)
CREATE TABLE events (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id uuid,
    title text NOT NULL,
    description text,
    due_text text,
    start_time timestamptz,
    end_time timestamptz,
    location text,
    is_all_day boolean DEFAULT false,
    is_completed boolean DEFAULT false,
    external_event_id text,
    sync_provider text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- tasks (mentioned-by-name in entity timeline)
CREATE TABLE tasks (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    due_date timestamptz,
    priority text DEFAULT 'medium',
    status text DEFAULT 'pending',
    category text,
    source_session_id uuid,
    completed_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- session_entities (mirrors migration 0002)
CREATE TABLE session_entities (
    session_id uuid NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    entity_id uuid NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    mention_count integer NOT NULL DEFAULT 1,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (session_id, entity_id)
);
CREATE INDEX session_entities_entity_idx ON session_entities (entity_id, last_seen_at DESC);
CREATE INDEX session_entities_user_idx ON session_entities (user_id, last_seen_at DESC);
```

> If `baseline.sql` uses `uuid_generate_v4()` rather than `gen_random_uuid()`, match whatever the surrounding tables use. Check the existing `sessions`/`entities` DDL in that file and copy its `DEFAULT` style.

- [ ] **Step 4: Add the new tables to the conftest teardown DROP list**

In `server/tests/integration/conftest.py`, the `pool` fixture's `finally:` block runs a `DROP TABLE IF EXISTS ...` statement. Add `session_entities`, `events`, `tasks` to it. New statement:

```python
            await con.execute(
                """
                DROP SCHEMA IF EXISTS auth CASCADE;
                DROP TABLE IF EXISTS session_entities, events, tasks,
                    user_rewards, rewards, user_quests, quest_definitions,
                    user_gamification, user_mistakes, memory, user_personas,
                    entity_relations, entities, sessions CASCADE;
                """
            )
```

(`session_entities` first so it goes before `sessions`/`entities`; `CASCADE` makes order moot anyway but keep it tidy.)

- [ ] **Step 5: Smoke-check the fixtures load**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_repo_entities.py -q`
Expected: PASS (the existing entity-repo tests still pass against the updated `baseline.sql` — confirms the new DDL didn't break the schema load). If Docker is unavailable in your environment, run `make test` instead and note that the integration step must be run by CI; do not skip writing the fixtures.

- [ ] **Step 6: Run lint + typecheck**

Run (from `server/`): `make lint && make typecheck`
Expected: PASS (the new migration file is ruff-formatted by the alembic post-write hook; if `make lint` flags it, run `make fmt`).

- [ ] **Step 7: Commit**

```bash
git add server/alembic/versions/2026_05_11_0002_session_entities.py \
        server/tests/integration/fixtures/baseline.sql \
        server/tests/integration/conftest.py
git commit -m "feat(server): add session_entities link table (migration 0002 + test fixtures)"
```

---

## Task 2: `entities_repo` — link, timeline rewrite, name-match queries, relations list

**Files:**
- Modify: `server/src/bubbles/db/repo/entities.py`
- Test: `server/tests/integration/test_repo_entities.py`

- [ ] **Step 1: Write the failing tests**

Append to `server/tests/integration/test_repo_entities.py` (it already imports `from bubbles.db.repo import entities as repo`, `from bubbles.db.uow import UnitOfWork`, `asyncpg`, `pytest`, `from uuid import UUID`, and has `pytestmark = pytest.mark.integration`). Add `from datetime import datetime, timedelta, UTC` and `from uuid import uuid4` at the top if not present.

```python
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


async def test_link_session_entity_upserts(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        ent = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="acme", entity_type="org")
    sid = await _make_session(pool, user_id)
    async with UnitOfWork(pool) as uow:
        await repo.link_session_entity(uow.conn, session_id=sid, entity_id=ent.id, user_id=user_id)
    async with UnitOfWork(pool) as uow:
        await repo.link_session_entity(uow.conn, session_id=sid, entity_id=ent.id, user_id=user_id)
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "SELECT mention_count FROM session_entities WHERE session_id=$1 AND entity_id=$2", sid, ent.id
        )
    assert row is not None
    assert row["mention_count"] == 2


async def test_timeline_returns_only_linked_sessions(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        ent = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="bob", entity_type="person")
    linked = await _make_session(pool, user_id, "linked")
    _other = await _make_session(pool, user_id, "other")  # not linked -> must not appear
    async with UnitOfWork(pool) as uow:
        await repo.link_session_entity(uow.conn, session_id=linked, entity_id=ent.id, user_id=user_id)
    async with pool.acquire() as con:
        rows = await repo.timeline(con, entity_id=ent.id, user_id=user_id)
    assert [r["session_id"] for r in rows] == [linked]


async def test_timeline_excludes_deleted_sessions(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        ent = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="c", entity_type="x")
    sid = await _make_session(pool, user_id)
    async with UnitOfWork(pool) as uow:
        await repo.link_session_entity(uow.conn, session_id=sid, entity_id=ent.id, user_id=user_id)
    async with pool.acquire() as con:
        await con.execute("UPDATE sessions SET deleted_at = now() WHERE id = $1", sid)
        rows = await repo.timeline(con, entity_id=ent.id, user_id=user_id)
    assert rows == []


async def test_events_and_tasks_mentioning(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as con:
        await con.execute("INSERT INTO events (user_id, title) VALUES ($1, 'Lunch with Acme team')", user_id)
        await con.execute("INSERT INTO events (user_id, title) VALUES ($1, 'Unrelated')", user_id)
        await con.execute("INSERT INTO tasks (user_id, title) VALUES ($1, 'Email acme contract')", user_id)
        ev = await repo.events_mentioning(con, user_id=user_id, name="acme")
        tk = await repo.tasks_mentioning(con, user_id=user_id, name="ACME")
    assert [e["title"] for e in ev] == ["Lunch with Acme team"]
    assert [t["title"] for t in tk] == ["Email acme contract"]


async def test_list_all_relations_orders_by_strength(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        a = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="a", entity_type="x")
        b = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="b", entity_type="x")
        c = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="c", entity_type="x")
        await repo.upsert_relation(uow.conn, user_id=user_id, source_id=a.id, target_id=b.id, relation="weak", strength=0.5)
        await repo.upsert_relation(uow.conn, user_id=user_id, source_id=a.id, target_id=c.id, relation="strong", strength=9.0)
    async with pool.acquire() as con:
        rels = await repo.list_all_relations(con, user_id=user_id)
    assert [r.relation for r in rels] == ["strong", "weak"]


async def test_list_for_user_include_archived(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        e1 = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="live", entity_type="x")
        e2 = await repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="gone", entity_type="x")
        await repo.soft_delete(uow.conn, entity_id=e2.id, user_id=user_id)
    async with pool.acquire() as con:
        default = await repo.list_for_user(con, user_id=user_id)
        with_archived = await repo.list_for_user(con, user_id=user_id, include_archived=True)
    assert {e.canonical_name for e in default} == {"live"}
    assert {e.canonical_name for e in with_archived} == {"live", "gone"}
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_repo_entities.py -q -k "link_session_entity or timeline or mentioning or list_all_relations or include_archived"`
Expected: FAIL — `AttributeError: module 'bubbles.db.repo.entities' has no attribute 'link_session_entity'` (etc.), and `timeline` returns wrong rows.

- [ ] **Step 3: Implement the repo changes**

In `server/src/bubbles/db/repo/entities.py`:

(a) Add a column constant near `_ENTITY_COLS` / `_REL_COLS`:

```python
_SESSION_ENTITY_COLS = "session_id, entity_id, user_id, mention_count, first_seen_at, last_seen_at"
```

(b) Add `include_archived` to `list_for_user` — replace the existing function body's query:

```python
async def list_for_user(
    conn: asyncpg.Connection, *, user_id: UUID, limit: int = 200, include_archived: bool = False
) -> list[Entity]:
    rows = await conn.fetch(
        f"""
        SELECT {_ENTITY_COLS}
        FROM entities
        WHERE user_id = $1 AND ($3 OR is_archived = false)
        ORDER BY last_seen_at DESC NULLS LAST, mention_count DESC
        LIMIT $2
        """,
        user_id,
        limit,
        include_archived,
    )
    return [_row_to_entity(r) for r in rows]
```

(c) Add `link_session_entity`:

```python
async def link_session_entity(
    conn: asyncpg.Connection, *, session_id: UUID, entity_id: UUID, user_id: UUID
) -> None:
    await conn.execute(
        """
        INSERT INTO session_entities (session_id, entity_id, user_id)
        VALUES ($1, $2, $3)
        ON CONFLICT (session_id, entity_id) DO UPDATE SET
            mention_count = session_entities.mention_count + 1,
            last_seen_at = now()
        """,
        session_id,
        entity_id,
        user_id,
    )
```

(d) **Replace** the existing `timeline` function (the one with the bogus `JOIN sessions s ON s.user_id = e.user_id`) with:

```python
async def timeline(
    conn: asyncpg.Connection,
    *,
    entity_id: UUID,
    user_id: UUID,
    since: datetime | None = None,
    limit: int = 50,
) -> list[asyncpg.Record]:
    """Sessions where this entity was mentioned, newest first."""
    return list(
        await conn.fetch(
            """
            SELECT s.id AS session_id, s.title, s.created_at
            FROM session_entities se
            JOIN sessions s ON s.id = se.session_id AND s.deleted_at IS NULL
            WHERE se.entity_id = $1
              AND se.user_id = $2
              AND ($3::timestamptz IS NULL OR se.last_seen_at >= $3)
            ORDER BY se.last_seen_at DESC
            LIMIT $4
            """,
            entity_id,
            user_id,
            since,
            limit,
        )
    )
```

(e) Add `events_mentioning`, `tasks_mentioning`, `list_all_relations` at the end of the file:

```python
async def events_mentioning(
    conn: asyncpg.Connection, *, user_id: UUID, name: str, limit: int = 10
) -> list[asyncpg.Record]:
    return list(
        await conn.fetch(
            """
            SELECT id, title, due_text, description, created_at
            FROM events
            WHERE user_id = $1 AND title ILIKE '%' || $2 || '%'
            ORDER BY created_at DESC
            LIMIT $3
            """,
            user_id,
            name,
            limit,
        )
    )


async def tasks_mentioning(
    conn: asyncpg.Connection, *, user_id: UUID, name: str, limit: int = 10
) -> list[asyncpg.Record]:
    return list(
        await conn.fetch(
            """
            SELECT id, title, status, priority, created_at
            FROM tasks
            WHERE user_id = $1 AND title ILIKE '%' || $2 || '%'
            ORDER BY created_at DESC
            LIMIT $3
            """,
            user_id,
            name,
            limit,
        )
    )


async def list_all_relations(
    conn: asyncpg.Connection, *, user_id: UUID, limit: int = 2000
) -> list[EntityRelation]:
    rows = await conn.fetch(
        f"""
        SELECT {_REL_COLS}
        FROM entity_relations
        WHERE user_id = $1
        ORDER BY strength DESC
        LIMIT $2
        """,
        user_id,
        limit,
    )
    return [_row_to_relation(r) for r in rows]
```

> Note: `_REL_COLS` is `id, user_id, source_id, target_id, relation, strength, created_at` — `_row_to_relation` already exists and handles those.

- [ ] **Step 4: Run tests to verify they pass**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_repo_entities.py -q`
Expected: PASS (all, including the pre-existing ones).

- [ ] **Step 5: Run lint + typecheck**

Run (from `server/`): `make lint && make typecheck`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add server/src/bubbles/db/repo/entities.py server/tests/integration/test_repo_entities.py
git commit -m "feat(server): entities repo — session links, real timeline, name-match + relations queries"
```

---

## Task 3: `memories_repo.get()`

**Files:**
- Modify: `server/src/bubbles/db/repo/memories.py`
- Test: `server/tests/integration/test_repo_memories.py` (create)

- [ ] **Step 1: Write the failing test**

Create `server/tests/integration/test_repo_memories.py`:

```python
"""Memory repo integration tests."""

from __future__ import annotations

from uuid import UUID, uuid4

import asyncpg
import pytest

from bubbles.db.repo import memories as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def test_get_returns_row_even_when_archived(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        m = await repo.insert(uow.conn, user_id=user_id, content="hello")
    async with pool.acquire() as con:
        got = await repo.get(con, m.id)
    assert got is not None
    assert got.id == m.id
    assert got.content == "hello"

    async with UnitOfWork(pool) as uow:
        ok = await repo.soft_delete(uow.conn, memory_id=m.id, user_id=user_id)
    assert ok is True
    async with pool.acquire() as con:
        got2 = await repo.get(con, m.id)
    assert got2 is not None
    assert got2.is_archived is True

    # second soft_delete is a no-op (already archived)
    async with UnitOfWork(pool) as uow:
        ok2 = await repo.soft_delete(uow.conn, memory_id=m.id, user_id=user_id)
    assert ok2 is False


async def test_get_unknown_id_returns_none(pool: asyncpg.Pool) -> None:
    async with pool.acquire() as con:
        assert await repo.get(con, uuid4()) is None
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_repo_memories.py -q`
Expected: FAIL — `AttributeError: module 'bubbles.db.repo.memories' has no attribute 'get'`.

- [ ] **Step 3: Implement `get`**

In `server/src/bubbles/db/repo/memories.py`, add after `list_for_user` (it can reuse the module-level `_COLS` constant and the `_row` helper):

```python
async def get(conn: asyncpg.Connection, memory_id: UUID) -> Memory | None:
    row = await conn.fetchrow(f"SELECT {_COLS} FROM memory WHERE id = $1", memory_id)
    return _row(row) if row is not None else None
```

(`UUID` is already imported at the top of `memories.py`.)

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_repo_memories.py -q`
Expected: PASS.

- [ ] **Step 5: Lint + typecheck, then commit**

```bash
make lint && make typecheck
git add server/src/bubbles/db/repo/memories.py server/tests/integration/test_repo_memories.py
git commit -m "feat(server): memories repo — get(memory_id)"
```

---

## Task 4: `extract_knowledge` worker writes `session_entities` links

**Files:**
- Modify: `server/src/bubbles/workers/jobs/extract_knowledge.py`
- Test: `server/tests/integration/test_worker_extract_knowledge.py` (create)

- [ ] **Step 1: Write the failing test**

Create `server/tests/integration/test_worker_extract_knowledge.py`. The job only touches `ctx["bubbles"].ai.router` (passed straight into `extract_entities`) and `ctx["bubbles"].pool`, so a `types.SimpleNamespace` is enough for the ctx, and we monkeypatch `extract_entities` itself rather than building a full `LLMRouter` stub:

```python
"""extract_knowledge worker — persists entities + session links."""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any
from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import entities as entities_repo
from bubbles.db.uow import UnitOfWork  # noqa: F401  (kept for parity with other repo tests)
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

    ctx = {"bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)}
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
```

> `extract_knowledge.py` does `from bubbles.ai.extraction import extract_entities`, so `monkeypatch.setattr(extract_knowledge, "extract_entities", ...)` swaps the name the module actually calls. (If you prefer a real `LLMRouter` stub instead, `tests/unit/test_routes_consultant.py` shows the `_Stub` provider + `TaskChain` shape — but the monkeypatch above is sufficient and the supported approach for this test.)

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_worker_extract_knowledge.py -q`
Expected: FAIL — `KeyError: 'links'` (the job doesn't return a `links` key yet) and/or zero `session_entities` rows.

- [ ] **Step 3: Implement the worker change**

In `server/src/bubbles/workers/jobs/extract_knowledge.py`, inside the `async with UnitOfWork(bub.pool) as uow:` block, in the `for item in raw_entities:` loop, **after** `entity_ids[name] = entity.id` and `saved_entities += 1`, add the link write, and track a counter:

```python
    entity_ids: dict[str, UUID] = {}
    saved_entities = 0
    saved_relations = 0
    saved_links = 0
    session_uuid = UUID(session_id)

    async with UnitOfWork(bub.pool) as uow:
        for item in raw_entities:
            name = (item.get("canonical_name") or "").strip().lower()
            etype = (item.get("entity_type") or "topic").strip().lower()
            if not name:
                continue
            entity = await entities_repo.upsert_entity(
                uow.conn,
                user_id=user_uuid,
                canonical_name=name,
                entity_type=etype,
                display_name=item.get("display_name"),
                aliases=list(item.get("aliases") or []),
                description=item.get("description"),
            )
            entity_ids[name] = entity.id
            saved_entities += 1
            await entities_repo.link_session_entity(
                uow.conn, session_id=session_uuid, entity_id=entity.id, user_id=user_uuid
            )
            saved_links += 1
        # ... existing relations loop unchanged ...
```

Update the closing `log.info(...)` to include `links=saved_links` and the return statement to:

```python
    return {"entities": saved_entities, "relations": saved_relations, "links": saved_links}
```

Also update the early-return on `UpstreamUnavailable` to `return {"entities": 0, "relations": 0, "links": 0}` for shape consistency.

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_worker_extract_knowledge.py -q`
Expected: PASS.

- [ ] **Step 5: Lint + typecheck, then commit**

```bash
make lint && make typecheck
git add server/src/bubbles/workers/jobs/extract_knowledge.py server/tests/integration/test_worker_extract_knowledge.py
git commit -m "feat(server): extract_knowledge worker writes session_entities links"
```

---

## Task 5: Schemas for graph export + entity timeline

**Files:**
- Modify: `server/src/bubbles/api/v1/_schemas.py`

- [ ] **Step 1: Add the schemas**

At the top of `server/src/bubbles/api/v1/_schemas.py`, ensure the imports include `datetime` and `Literal`:

```python
from __future__ import annotations

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field
```

Then append a new section after the `# --- entities ---` block (so it sits with the other entity schemas):

```python
# --- entity graph + timeline ----------------------------------------------


class GraphNode(_Base):
    id: UUID
    label: str
    type: str
    description: str | None = None
    mention_count: int = 0
    last_seen_at: datetime | None = None


class GraphLink(_Base):
    source: UUID
    target: UUID
    relation: str
    strength: float


class GraphExportResponse(_Base):
    user_id: UUID
    nodes: list[GraphNode]
    links: list[GraphLink]


class TimelineSession(_Base):
    session_id: UUID
    title: str | None = None
    created_at: datetime
    match: Literal["link"] = "link"


class TimelineEvent(_Base):
    id: UUID
    title: str
    due_text: str | None = None
    description: str | None = None
    created_at: datetime
    match: Literal["name"] = "name"


class TimelineTask(_Base):
    id: UUID
    title: str
    status: str | None = None
    priority: str | None = None
    created_at: datetime
    match: Literal["name"] = "name"


class EntityTimelineResponse(_Base):
    entity_id: UUID
    entity_name: str
    sessions: list[TimelineSession]
    events: list[TimelineEvent]
    tasks: list[TimelineTask]
```

- [ ] **Step 2: Verify it imports and typechecks**

Run (from `server/`): `uv run python -c "from bubbles.api.v1 import _schemas; _schemas.GraphExportResponse(user_id='11111111-1111-1111-1111-111111111111', nodes=[], links=[])"`
Expected: exits 0, no error.

Run: `make lint && make typecheck`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add server/src/bubbles/api/v1/_schemas.py
git commit -m "feat(server): add graph-export + entity-timeline response schemas"
```

---

## Task 6: `GET /v1/graph_export/{user_id}` route

**Files:**
- Modify: `server/src/bubbles/api/v1/entities.py`
- Test: `server/tests/integration/test_routes_entities_admin.py` (create)

- [ ] **Step 1: Write the failing test**

Create `server/tests/integration/test_routes_entities_admin.py`. Pattern for route integration tests: build the app with the `app` fixture (root conftest), override `get_pool` → the `pool` fixture, override `current_user` → a `CurrentUser` with `id=str(user_id)`. Use the `client`-style ASGI transport inline.

```python
"""graph_export + entity_timeline route integration tests."""

from __future__ import annotations

from collections.abc import AsyncIterator
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
    app.dependency_overrides[current_user] = lambda: CurrentUser(id=str(uid), email=None, role="authenticated")


async def _ac(app: FastAPI) -> AsyncIterator[AsyncClient]:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        yield ac


async def test_graph_export_nodes_and_links(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with UnitOfWork(pool) as uow:
        a = await entities_repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="a", entity_type="person", display_name="A")
        b = await entities_repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="b", entity_type="org")
        await entities_repo.upsert_relation(uow.conn, user_id=user_id, source_id=a.id, target_id=b.id, relation="works_at")
    async for ac in _ac(app):
        resp = await ac.get(f"/v1/graph_export/{user_id}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["user_id"] == str(user_id)
    assert {n["id"] for n in body["nodes"]} == {str(a.id), str(b.id)}
    assert len(body["links"]) == 1
    assert body["links"][0]["relation"] == "works_at"


async def test_graph_export_drops_dangling_links_and_limits(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with UnitOfWork(pool) as uow:
        keep = await entities_repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="keep", entity_type="x")
        # bump keep's mention_count so it wins the limit cut
        await entities_repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="keep", entity_type="x")
        drop = await entities_repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="drop", entity_type="x")
        await entities_repo.upsert_relation(uow.conn, user_id=user_id, source_id=keep.id, target_id=drop.id, relation="r")
    async for ac in _ac(app):
        resp = await ac.get(f"/v1/graph_export/{user_id}", params={"limit": 1})
    assert resp.status_code == 200
    body = resp.json()
    assert [n["id"] for n in body["nodes"]] == [str(keep.id)]
    assert body["links"] == []  # the only link points at the dropped node


async def test_graph_export_filters_by_entity_type(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with UnitOfWork(pool) as uow:
        await entities_repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="alice", entity_type="person")
        await entities_repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="acme", entity_type="org")
    async for ac in _ac(app):
        resp = await ac.get(f"/v1/graph_export/{user_id}", params={"entity_type": "person"})
    assert resp.status_code == 200
    assert {n["type"] for n in resp.json()["nodes"]} == {"person"}


async def test_graph_export_empty_for_fresh_user(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async for ac in _ac(app):
        resp = await ac.get(f"/v1/graph_export/{user_id}")
    assert resp.status_code == 200
    assert resp.json() == {"user_id": str(user_id), "nodes": [], "links": []}


async def test_graph_export_forbidden_for_other_user(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async for ac in _ac(app):
        resp = await ac.get(f"/v1/graph_export/{uuid4()}")
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "forbidden"
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_routes_entities_admin.py -q -k graph_export`
Expected: FAIL — 404 (route not registered).

- [ ] **Step 3: Implement the route**

In `server/src/bubbles/api/v1/entities.py`:

Add imports at the top (merge with existing):

```python
from fastapi import APIRouter, Query, Response

from bubbles.api.v1._schemas import (
    EntityAnswer,
    EntityQueryRequest,
    EntitySummary,
    EntityTimelineResponse,
    GraphExportResponse,
    GraphLink,
    GraphNode,
    TimelineEvent,
    TimelineSession,
    TimelineTask,
)
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import NotFound
from bubbles.db.uow import transaction
```

Add the handler (place it after `ask_entity`, before `delete_entity`):

```python
@router.get("/graph_export/{user_id}", response_model=GraphExportResponse)
async def graph_export(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
    limit: int = Query(300, ge=1, le=1000),
    entity_type: str | None = Query(None, max_length=64),
    include_archived: bool = Query(False),
) -> GraphExportResponse:
    require_ownership(user, str(user_id))
    async with transaction(pool) as conn:
        ents = await entities_repo.list_for_user(
            conn, user_id=user_id, limit=limit, include_archived=include_archived
        )
        rels = await entities_repo.list_all_relations(conn, user_id=user_id)
    if entity_type is not None:
        wanted = entity_type.strip().lower()
        ents = [e for e in ents if (e.entity_type or "").lower() == wanted]
    node_ids = {e.id for e in ents}
    nodes = [
        GraphNode(
            id=e.id,
            label=e.display_name or e.canonical_name,
            type=e.entity_type,
            description=e.description,
            mention_count=e.mention_count,
            last_seen_at=e.last_seen_at,
        )
        for e in ents
    ]
    links = [
        GraphLink(source=r.source_id, target=r.target_id, relation=r.relation, strength=r.strength)
        for r in rels
        if r.source_id in node_ids and r.target_id in node_ids
    ]
    return GraphExportResponse(user_id=user_id, nodes=nodes, links=links)
```

> `PoolDep` is already imported in `entities.py` (`from bubbles.deps import PoolDep, RouterDep`). Keep that import; just add `Query`/`Response` to the `fastapi` import line and the new schema names to the `_schemas` import. `transaction` may not be imported yet — add `from bubbles.db.uow import transaction` (the file currently imports `from bubbles.db.uow import transaction` already for `_resolve_entities`; verify and don't double-import).

- [ ] **Step 4: Run tests to verify they pass**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_routes_entities_admin.py -q -k graph_export`
Expected: PASS.

- [ ] **Step 5: Lint + typecheck, then commit**

```bash
make lint && make typecheck
git add server/src/bubbles/api/v1/entities.py server/tests/integration/test_routes_entities_admin.py
git commit -m "feat(server): GET /v1/graph_export/{user_id}"
```

---

## Task 7: `GET /v1/entity_timeline/{entity_id}` route

**Files:**
- Modify: `server/src/bubbles/api/v1/entities.py`
- Test: `server/tests/integration/test_routes_entities_admin.py` (extend)

- [ ] **Step 1: Write the failing tests**

Append to `server/tests/integration/test_routes_entities_admin.py`:

```python
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


async def test_entity_timeline_happy_path(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with UnitOfWork(pool) as uow:
        ent = await entities_repo.upsert_entity(uow.conn, user_id=user_id, canonical_name="acme", entity_type="org", display_name="Acme")
    sid = await _make_session(pool, user_id, "kickoff")
    async with UnitOfWork(pool) as uow:
        await entities_repo.link_session_entity(uow.conn, session_id=sid, entity_id=ent.id, user_id=user_id)
    async with pool.acquire() as con:
        await con.execute("INSERT INTO events (user_id, title) VALUES ($1, 'Demo for Acme')", user_id)
        await con.execute("INSERT INTO tasks (user_id, title) VALUES ($1, 'Send Acme invoice')", user_id)
    async for ac in _ac(app):
        resp = await ac.get(f"/v1/entity_timeline/{ent.id}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["entity_id"] == str(ent.id)
    assert body["entity_name"] == "Acme"
    assert [s["session_id"] for s in body["sessions"]] == [str(sid)]
    assert body["sessions"][0]["match"] == "link"
    assert [e["title"] for e in body["events"]] == ["Demo for Acme"]
    assert body["events"][0]["match"] == "name"
    assert [t["title"] for t in body["tasks"]] == ["Send Acme invoice"]


async def test_entity_timeline_unknown_entity_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async for ac in _ac(app):
        resp = await ac.get(f"/v1/entity_timeline/{uuid4()}")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "not_found"


async def test_entity_timeline_other_users_entity_403(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    # entity owned by a *different* user; caller is user_id
    other = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", other)
    async with UnitOfWork(pool) as uow:
        ent = await entities_repo.upsert_entity(uow.conn, user_id=other, canonical_name="secret", entity_type="x")
    _override(app, pool, user_id)
    async for ac in _ac(app):
        resp = await ac.get(f"/v1/entity_timeline/{ent.id}")
    assert resp.status_code == 403
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_routes_entities_admin.py -q -k entity_timeline`
Expected: FAIL — 404 (route not registered) for the happy-path test.

- [ ] **Step 3: Implement the route**

In `server/src/bubbles/api/v1/entities.py`, add (after `graph_export`, before `delete_entity`):

```python
@router.get("/entity_timeline/{entity_id}", response_model=EntityTimelineResponse)
async def entity_timeline(
    entity_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
    limit: int = Query(50, ge=1, le=200),
    since: datetime | None = Query(None),
) -> EntityTimelineResponse:
    async with transaction(pool) as conn:
        ent = await entities_repo.get_entity(conn, entity_id)
        if ent is None:
            raise NotFound("entity not found")
        require_ownership(user, str(ent.user_id))
        name = ent.display_name or ent.canonical_name
        sess_rows = await entities_repo.timeline(conn, entity_id=entity_id, user_id=ent.user_id, since=since, limit=limit)
        event_rows = await entities_repo.events_mentioning(conn, user_id=ent.user_id, name=name)
        task_rows = await entities_repo.tasks_mentioning(conn, user_id=ent.user_id, name=name)
    return EntityTimelineResponse(
        entity_id=entity_id,
        entity_name=name,
        sessions=[TimelineSession(session_id=r["session_id"], title=r["title"], created_at=r["created_at"]) for r in sess_rows],
        events=[
            TimelineEvent(id=r["id"], title=r["title"], due_text=r["due_text"], description=r["description"], created_at=r["created_at"])
            for r in event_rows
        ],
        tasks=[TimelineTask(id=r["id"], title=r["title"], status=r["status"], priority=r["priority"], created_at=r["created_at"]) for r in task_rows],
    )
```

Add `datetime` to the imports at the top of `entities.py`: `from datetime import datetime`.

- [ ] **Step 4: Run tests to verify they pass**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_routes_entities_admin.py -q`
Expected: PASS (all, including the `graph_export` ones).

- [ ] **Step 5: Lint + typecheck, then commit**

```bash
make lint && make typecheck
git add server/src/bubbles/api/v1/entities.py server/tests/integration/test_routes_entities_admin.py
git commit -m "feat(server): GET /v1/entity_timeline/{entity_id}"
```

---

## Task 8: `DELETE /v1/sessions/{session_id}` route

**Files:**
- Modify: `server/src/bubbles/api/v1/sessions.py`
- Test: `server/tests/integration/test_routes_sessions.py` (create)

- [ ] **Step 1: Write the failing tests**

Create `server/tests/integration/test_routes_sessions.py`:

```python
"""DELETE /v1/sessions/{id} route integration tests."""

from __future__ import annotations

from collections.abc import AsyncIterator
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
    app.dependency_overrides[current_user] = lambda: CurrentUser(id=str(uid), email=None, role="authenticated")


async def _ac(app: FastAPI) -> AsyncIterator[AsyncClient]:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        yield ac


async def _make_session(pool: asyncpg.Pool, owner: UUID) -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'active') RETURNING id", owner
        )
    assert row is not None
    sid: UUID = row["id"]
    return sid


async def test_delete_session_204_then_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    sid = await _make_session(pool, user_id)
    async for ac in _ac(app):
        r1 = await ac.delete(f"/v1/sessions/{sid}")
        r2 = await ac.delete(f"/v1/sessions/{sid}")
        # save_session reads the session and must now 404 (soft-deleted)
        r3 = await ac.post("/v1/save_session", json={"session_id": str(sid), "transcript": "x"})
    assert r1.status_code == 204
    assert r2.status_code == 404
    assert r3.status_code == 404


async def test_delete_unknown_session_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async for ac in _ac(app):
        r = await ac.delete(f"/v1/sessions/{uuid4()}")
    assert r.status_code == 404


async def test_delete_other_users_session_403(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    other = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", other)
    sid = await _make_session(pool, other)
    _override(app, pool, user_id)
    async for ac in _ac(app):
        r = await ac.delete(f"/v1/sessions/{sid}")
    assert r.status_code == 403
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_routes_sessions.py -q`
Expected: FAIL — 405 Method Not Allowed (no DELETE handler on `/v1/sessions/{id}`).

- [ ] **Step 3: Implement the route**

In `server/src/bubbles/api/v1/sessions.py`:
- Add `Response` to the `fastapi` import: `from fastapi import APIRouter, Response, status`.
- Add the handler at the end of the file:

```python
@router.delete("/sessions/{session_id}", status_code=204, response_class=Response)
async def delete_session(
    session_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> Response:
    async with transaction(pool) as conn:
        sess = await sessions_repo.get(conn, session_id)
    if sess is None:
        raise NotFound("session not found")
    require_ownership(user, str(sess.user_id))
    async with UnitOfWork(pool) as uow:
        ok = await sessions_repo.soft_delete(uow.conn, session_id=session_id, user_id=UUID(user.id))
    if not ok:
        raise NotFound("session not found")
    return Response(status_code=204)
```

(`UnitOfWork`, `transaction`, `NotFound`, `require_ownership`, `CurrentUserDep`, `PoolDep`, `sessions_repo`, `UUID` are all already imported in `sessions.py`.)

- [ ] **Step 4: Run tests to verify they pass**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_routes_sessions.py -q`
Expected: PASS.

- [ ] **Step 5: Lint + typecheck, then commit**

```bash
make lint && make typecheck
git add server/src/bubbles/api/v1/sessions.py server/tests/integration/test_routes_sessions.py
git commit -m "feat(server): DELETE /v1/sessions/{session_id} (soft delete)"
```

---

## Task 9: `DELETE /v1/memories/{memory_id}` route + new `memories.py` module + wiring

**Files:**
- Create: `server/src/bubbles/api/v1/memories.py`
- Modify: `server/src/bubbles/api/router.py`
- Test: `server/tests/integration/test_routes_memories.py` (create)

- [ ] **Step 1: Write the failing tests**

Create `server/tests/integration/test_routes_memories.py`:

```python
"""DELETE /v1/memories/{id} route integration tests."""

from __future__ import annotations

from collections.abc import AsyncIterator
from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.db.repo import memories as memories_repo
from bubbles.db.uow import UnitOfWork
from bubbles.deps import get_pool

pytestmark = pytest.mark.integration


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[current_user] = lambda: CurrentUser(id=str(uid), email=None, role="authenticated")


async def _ac(app: FastAPI) -> AsyncIterator[AsyncClient]:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        yield ac


async def test_delete_memory_204_then_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with UnitOfWork(pool) as uow:
        m = await memories_repo.insert(uow.conn, user_id=user_id, content="remember this")
    async for ac in _ac(app):
        r1 = await ac.delete(f"/v1/memories/{m.id}")
        r2 = await ac.delete(f"/v1/memories/{m.id}")
    assert r1.status_code == 204
    assert r2.status_code == 404


async def test_delete_unknown_memory_404(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async for ac in _ac(app):
        r = await ac.delete(f"/v1/memories/{uuid4()}")
    assert r.status_code == 404


async def test_delete_other_users_memory_403(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    other = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", other)
    async with UnitOfWork(pool) as uow:
        m = await memories_repo.insert(uow.conn, user_id=other, content="theirs")
    _override(app, pool, user_id)
    async for ac in _ac(app):
        r = await ac.delete(f"/v1/memories/{m.id}")
    assert r.status_code == 403
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_routes_memories.py -q`
Expected: FAIL — 404 (route not registered).

- [ ] **Step 3: Create the route module**

Create `server/src/bubbles/api/v1/memories.py`:

```python
"""Memory admin routes."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Response

from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import NotFound
from bubbles.db.repo import memories as memories_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep

router = APIRouter(tags=["memories"])


@router.delete("/memories/{memory_id}", status_code=204, response_class=Response)
async def delete_memory(
    memory_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> Response:
    async with transaction(pool) as conn:
        mem = await memories_repo.get(conn, memory_id)
    if mem is None:
        raise NotFound("memory not found")
    require_ownership(user, str(mem.user_id))
    async with UnitOfWork(pool) as uow:
        ok = await memories_repo.soft_delete(uow.conn, memory_id=memory_id, user_id=UUID(user.id))
    if not ok:
        raise NotFound("memory not found")
    return Response(status_code=204)
```

- [ ] **Step 4: Wire it into the router**

In `server/src/bubbles/api/router.py`, add the import and the `include_router` call (keep the others):

```python
from bubbles.api.v1.memories import router as memories_router
...
v1_router.include_router(memories_router)
```

- [ ] **Step 5: Run tests to verify they pass**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_routes_memories.py -q`
Expected: PASS.

- [ ] **Step 6: Lint + typecheck, then commit**

```bash
make lint && make typecheck
git add server/src/bubbles/api/v1/memories.py server/src/bubbles/api/router.py server/tests/integration/test_routes_memories.py
git commit -m "feat(server): DELETE /v1/memories/{memory_id} + memories route module"
```

---

## Task 10: Update the review doc + full gate

**Files:**
- Modify: `Documentation/server-vs-server_v2-review.md`

- [ ] **Step 1: Edit §5 of the review doc**

Open `Documentation/server-vs-server_v2-review.md`. In §5 ("Known gaps / follow-ups"):
- Remove the `graph_export` / `entity_timeline` / `DELETE sessions|memories` items from the gap list (they're now done).
- Add a single follow-up bullet:

```markdown
- **Backfill `session_entities`**: the new `session_entities` link table (migration `0002`) is
  populated going forward by the `extract_knowledge` worker; sessions created before this change
  have no links yet — a one-off `backfill_session_entities` worker job is pending.
```

Also, in §2 (the contract list), the line claiming `graph_export/{user_id}`, `entity_timeline/{entity_id}`, `DELETE entities|sessions|memories` "carried over" is now actually true — leave it, but if you tightened it earlier when the retirement landed, restore those paths to the list.

- [ ] **Step 2: Run the full quality gate**

Run (from `server/`): `make test`
Expected: PASS — `ruff check`, `ruff format --check`, `mypy` strict, and the unit test suite all green.

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest -q`
Expected: PASS — the full suite including all new integration tests. (If Docker isn't available locally, state that clearly; this step is mandatory in CI.)

- [ ] **Step 3: Commit**

```bash
git add Documentation/server-vs-server_v2-review.md
git commit -m "docs(server): mark v2 entity routes as ported in the v5 comparison review"
```

- [ ] **Step 4: Hand off**

Report: Batch 1 complete — 4 new endpoints (`GET /v1/graph_export/{user_id}`, `GET /v1/entity_timeline/{entity_id}`, `DELETE /v1/sessions/{id}`, `DELETE /v1/memories/{id}`), `session_entities` link table (migration `0002`), worker writes links, full quality gate green. Branch `feat/v5-port-v2-endpoints`. Next batch: Gamification HTTP routes (Batch 2) — needs its own spec.

---

## Notes for the implementer

- **Working dir:** all `uv run` / `make` commands run from `server/`. `git` commands run from the repo root (`E:\FYP\FYP_V2\Bubbles-AI`) — paths in this plan are repo-root-relative.
- **Branch:** `feat/v5-port-v2-endpoints` (already created; the retirement commit + specs are on it).
- **Integration tests need Docker** (testcontainers Postgres) and `RUN_INTEGRATION=1`. Without it they auto-skip — but you must still write them; CI runs them.
- **`mypy --strict` is unforgiving:** every new function needs full annotations; `asyncpg.Record` indexing returns `Any`, so when you pull a value out of a `Record` into a typed variable, annotate it (see how `sessions.py` does `sid: UUID = row["id"]`).
- **`ruff format` runs as an alembic post-write hook** — the generated migration file is auto-formatted; if `make lint` complains about any file, `make fmt` then re-stage.
- **Don't double-import**: `entities.py` already imports several of the names the new code needs (`PoolDep`, `RouterDep`, `transaction`, `UUID`, `entities_repo`). Add only what's missing.
