# Personalized Roleplay Scenarios Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate personalized roleplay practice scenarios from the user's knowledge graph (people, tasks, events), delivered as a browsable feed plus an on-demand endpoint.

**Architecture:** A dedicated `scenarios` subsystem — a `scenarios` table, a repo, an LLM generator shared by a feed worker and an on-demand route, four `/v1/scenarios` endpoints, and a post-session scoring worker. Feed generation and scoring run in ARQ workers; on-demand generation is a rate-limited endpoint. The wingman turn loop is untouched.

**Tech Stack:** Python 3.12, FastAPI, asyncpg, Alembic (raw-SQL migrations), ARQ workers, Jinja2 prompts, pytest + testcontainers.

**Spec:** `docs/superpowers/specs/2026-05-22-personalized-roleplay-scenarios-design.md`

---

## Conventions for every task

- **Working directory:** all commands run from `server/`. Shell is PowerShell.
- **Commit per task** on the current branch `feat/personalized-roleplay`. Commit messages use `feat(scenarios): …`; **do not** add a `Co-Authored-By` trailer.
- **Lint/type gates** (run before each commit): `uv run ruff check src tests`, `uv run ruff format src tests`, `uv run mypy`.
- **Unit tests:** `uv run pytest tests/unit/<file> -q` — real red/green.
- **Integration tests** need Docker Desktop running. Set `$env:RUN_INTEGRATION='1'` first; without it they **skip** (not fail). When a step says "verify it fails", that requires Docker up.
- No placeholders: every function below is shown in full. Implement it as written.

---

## Task 1: `scenarios` table — migration, baseline, model

**Files:**
- Create: `server/alembic/versions/2026_05_22_0006_scenarios.py`
- Modify: `server/tests/integration/fixtures/baseline.sql` (append a table block)
- Modify: `server/tests/integration/conftest.py:75-81` (teardown DROP list)
- Modify: `server/src/bubbles/db/models.py` (append `Scenario` dataclass)

- [ ] **Step 1: Write the migration**

Create `server/alembic/versions/2026_05_22_0006_scenarios.py`:

```python
"""scenarios — graph-generated roleplay practice

New table; not present in the live Supabase schema yet. ``CREATE TABLE IF
NOT EXISTS`` keeps the migration idempotent and safe to re-run, matching
0002-0005.

Revision ID: 0006
Revises: 0005
Create Date: 2026-05-22 00:00:00 UTC
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS scenarios (
            id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id          uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
            target_entity_id uuid        REFERENCES entities(id) ON DELETE SET NULL,
            title            text        NOT NULL,
            situation        text        NOT NULL,
            goal             text        NOT NULL,
            success_criteria text        NOT NULL,
            difficulty       text        NOT NULL DEFAULT 'medium'
                                 CHECK (difficulty IN ('easy', 'medium', 'hard')),
            role_mode        text        NOT NULL DEFAULT 'default',
            opening_line     text        NOT NULL,
            source           jsonb       NOT NULL DEFAULT '{}'::jsonb,
            status           text        NOT NULL DEFAULT 'suggested'
                                 CHECK (status IN ('suggested','started','completed','dismissed')),
            session_id       uuid        REFERENCES sessions(id) ON DELETE SET NULL,
            passed           boolean,
            score_feedback   text,
            created_at       timestamptz NOT NULL DEFAULT now(),
            updated_at       timestamptz NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS idx_scenarios_user_status
            ON scenarios (user_id, status);
        CREATE INDEX IF NOT EXISTS idx_scenarios_user_entity
            ON scenarios (user_id, target_entity_id);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX IF EXISTS idx_scenarios_user_entity;
        DROP INDEX IF EXISTS idx_scenarios_user_status;
        DROP TABLE IF EXISTS scenarios;
        """
    )
```

- [ ] **Step 2: Add the table to the test baseline**

In `server/tests/integration/fixtures/baseline.sql`, append this block at the **end of the file** (it references `entities` and `sessions`, which the baseline already defines earlier):

```sql

CREATE TABLE scenarios (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    target_entity_id uuid REFERENCES entities(id) ON DELETE SET NULL,
    title            text NOT NULL,
    situation        text NOT NULL,
    goal             text NOT NULL,
    success_criteria text NOT NULL,
    difficulty       text NOT NULL DEFAULT 'medium'
                         CHECK (difficulty IN ('easy', 'medium', 'hard')),
    role_mode        text NOT NULL DEFAULT 'default',
    opening_line     text NOT NULL,
    source           jsonb NOT NULL DEFAULT '{}'::jsonb,
    status           text NOT NULL DEFAULT 'suggested'
                         CHECK (status IN ('suggested','started','completed','dismissed')),
    session_id       uuid REFERENCES sessions(id) ON DELETE SET NULL,
    passed           boolean,
    score_feedback   text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_scenarios_user_status ON scenarios (user_id, status);
CREATE INDEX idx_scenarios_user_entity ON scenarios (user_id, target_entity_id);
```

- [ ] **Step 3: Add `scenarios` to the integration teardown**

In `server/tests/integration/conftest.py`, the `pool` fixture's teardown drops every test table. Edit the `DROP TABLE IF EXISTS` statement — change the first line of the table list to include `scenarios`:

Replace:
```python
                DROP TABLE IF EXISTS feedback, session_analytics, coaching_reports, highlights,
```
with:
```python
                DROP TABLE IF EXISTS scenarios, feedback, session_analytics, coaching_reports,
                    highlights,
```

- [ ] **Step 4: Add the `Scenario` model**

Append to `server/src/bubbles/db/models.py` (the file already imports `Any`, `datetime`, `UUID` and uses `@dataclass(frozen=True, slots=True)`):

```python
@dataclass(frozen=True, slots=True)
class Scenario:
    id: UUID
    user_id: UUID
    target_entity_id: UUID | None
    title: str
    situation: str
    goal: str
    success_criteria: str
    difficulty: str
    role_mode: str
    opening_line: str
    source: dict[str, Any]
    status: str
    session_id: UUID | None
    passed: bool | None
    score_feedback: str | None
    created_at: datetime
    updated_at: datetime
```

- [ ] **Step 5: Verify the migration runs**

Run: `uv run alembic upgrade head` then `uv run alembic downgrade -1` then `uv run alembic upgrade head`
Expected: each completes with no error; `0006` applies and reverts cleanly.

- [ ] **Step 6: Lint + commit**

Run: `uv run ruff check src tests; uv run ruff format src tests; uv run mypy`
Expected: all clean.

```powershell
git add server/alembic/versions/2026_05_22_0006_scenarios.py server/tests/integration/fixtures/baseline.sql server/tests/integration/conftest.py server/src/bubbles/db/models.py
git commit -m "feat(scenarios): add scenarios table, migration 0006, Scenario model"
```

---

## Task 2: `scenarios` repo

**Files:**
- Create: `server/src/bubbles/db/repo/scenarios.py`
- Test: `server/tests/integration/test_repo_scenarios.py`

- [ ] **Step 1: Write the failing test**

Create `server/tests/integration/test_repo_scenarios.py`:

```python
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
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `$env:RUN_INTEGRATION='1'; uv run pytest tests/integration/test_repo_scenarios.py -q`
Expected: FAIL — `ModuleNotFoundError: bubbles.db.repo.scenarios`.

- [ ] **Step 3: Write the repo**

Create `server/src/bubbles/db/repo/scenarios.py`:

```python
"""Scenarios repo — graph-generated roleplay practice."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Final
from uuid import UUID

import asyncpg

from bubbles.db.models import Scenario

_COLS: Final[str] = (
    "id, user_id, target_entity_id, title, situation, goal, success_criteria, "
    "difficulty, role_mode, opening_line, source, status, session_id, passed, "
    "score_feedback, created_at, updated_at"
)


@dataclass(frozen=True, slots=True)
class NewScenario:
    """A scenario draft from the generator, before it is persisted."""

    target_entity_id: UUID | None
    title: str
    situation: str
    goal: str
    success_criteria: str
    difficulty: str
    role_mode: str
    opening_line: str
    source: dict[str, Any]


def _source(raw: Any) -> dict[str, Any]:
    if isinstance(raw, str):
        loaded: Any = json.loads(raw)
        return dict(loaded) if isinstance(loaded, dict) else {}
    return dict(raw) if raw else {}


def _row(r: asyncpg.Record) -> Scenario:
    return Scenario(
        id=r["id"],
        user_id=r["user_id"],
        target_entity_id=r["target_entity_id"],
        title=r["title"],
        situation=r["situation"],
        goal=r["goal"],
        success_criteria=r["success_criteria"],
        difficulty=r["difficulty"],
        role_mode=r["role_mode"],
        opening_line=r["opening_line"],
        source=_source(r["source"]),
        status=r["status"],
        session_id=r["session_id"],
        passed=r["passed"],
        score_feedback=r["score_feedback"],
        created_at=r["created_at"],
        updated_at=r["updated_at"],
    )


async def create_many(
    conn: asyncpg.Connection, *, user_id: UUID, rows: list[NewScenario]
) -> list[Scenario]:
    out: list[Scenario] = []
    for r in rows:
        row = await conn.fetchrow(
            f"""
            INSERT INTO scenarios (
                user_id, target_entity_id, title, situation, goal,
                success_criteria, difficulty, role_mode, opening_line, source
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb)
            RETURNING {_COLS}
            """,
            user_id,
            r.target_entity_id,
            r.title,
            r.situation,
            r.goal,
            r.success_criteria,
            r.difficulty,
            r.role_mode,
            r.opening_line,
            json.dumps(r.source),
        )
        assert row is not None
        out.append(_row(row))
    return out


async def list_for_user(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    status: str = "suggested",
    limit: int = 50,
    offset: int = 0,
) -> list[Scenario]:
    rows = await conn.fetch(
        f"""
        SELECT {_COLS} FROM scenarios
        WHERE user_id = $1 AND status = $2
        ORDER BY created_at DESC
        LIMIT $3 OFFSET $4
        """,
        user_id,
        status,
        limit,
        offset,
    )
    return [_row(r) for r in rows]


async def get(conn: asyncpg.Connection, scenario_id: UUID) -> Scenario | None:
    row = await conn.fetchrow(f"SELECT {_COLS} FROM scenarios WHERE id = $1", scenario_id)
    return _row(row) if row is not None else None


async def get_by_session(conn: asyncpg.Connection, *, session_id: UUID) -> Scenario | None:
    row = await conn.fetchrow(
        f"SELECT {_COLS} FROM scenarios WHERE session_id = $1", session_id
    )
    return _row(row) if row is not None else None


async def count_active(conn: asyncpg.Connection, *, user_id: UUID) -> int:
    n: int | None = await conn.fetchval(
        "SELECT COUNT(*)::int FROM scenarios WHERE user_id = $1 AND status = 'suggested'",
        user_id,
    )
    return n or 0


async def used_source_ids(
    conn: asyncpg.Connection, *, user_id: UUID
) -> tuple[set[UUID], set[UUID]]:
    """Task ids and event ids referenced by every non-dismissed scenario."""
    rows = await conn.fetch(
        "SELECT source FROM scenarios WHERE user_id = $1 AND status <> 'dismissed'",
        user_id,
    )
    tasks: set[UUID] = set()
    events: set[UUID] = set()
    for r in rows:
        src = _source(r["source"])
        for key, bucket in (("tasks", tasks), ("events", events)):
            for raw in src.get(key, []) or []:
                try:
                    bucket.add(UUID(str(raw)))
                except (ValueError, AttributeError):
                    continue
    return tasks, events


async def mark_started(
    conn: asyncpg.Connection, *, scenario_id: UUID, session_id: UUID
) -> Scenario | None:
    """Flip a suggested scenario to started. Returns ``None`` if it was not suggested."""
    row = await conn.fetchrow(
        f"""
        UPDATE scenarios
        SET status = 'started', session_id = $2, updated_at = now()
        WHERE id = $1 AND status = 'suggested'
        RETURNING {_COLS}
        """,
        scenario_id,
        session_id,
    )
    return _row(row) if row is not None else None


async def mark_dismissed(
    conn: asyncpg.Connection, *, scenario_id: UUID
) -> Scenario | None:
    """Dismiss a suggested scenario. Returns ``None`` if it was not suggested."""
    row = await conn.fetchrow(
        f"""
        UPDATE scenarios
        SET status = 'dismissed', updated_at = now()
        WHERE id = $1 AND status = 'suggested'
        RETURNING {_COLS}
        """,
        scenario_id,
    )
    return _row(row) if row is not None else None


async def mark_completed(
    conn: asyncpg.Connection,
    *,
    scenario_id: UUID,
    passed: bool | None,
    feedback: str | None,
) -> Scenario | None:
    row = await conn.fetchrow(
        f"""
        UPDATE scenarios
        SET status = 'completed', passed = $2, score_feedback = $3, updated_at = now()
        WHERE id = $1
        RETURNING {_COLS}
        """,
        scenario_id,
        passed,
        feedback,
    )
    return _row(row) if row is not None else None
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `$env:RUN_INTEGRATION='1'; uv run pytest tests/integration/test_repo_scenarios.py -q`
Expected: PASS — 5 tests.

- [ ] **Step 5: Lint + commit**

Run: `uv run ruff check src tests; uv run ruff format src tests; uv run mypy`

```powershell
git add server/src/bubbles/db/repo/scenarios.py server/tests/integration/test_repo_scenarios.py
git commit -m "feat(scenarios): add scenarios repo with status lifecycle + source dedup"
```

---

## Task 3: `recent_tasks` / `recent_events` graph readers

**Files:**
- Modify: `server/src/bubbles/db/repo/entities.py` (append two functions)
- Test: `server/tests/integration/test_repo_entities_recent.py`

- [ ] **Step 1: Write the failing test**

Create `server/tests/integration/test_repo_entities_recent.py`:

```python
"""recent_tasks / recent_events repo integration tests."""

from __future__ import annotations

from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import entities as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def test_recent_tasks_orders_and_excludes(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        t1 = await repo.insert_task(uow.conn, user_id=user_id, session_id=None, title="task one")
        t2 = await repo.insert_task(uow.conn, user_id=user_id, session_id=None, title="task two")
        assert t1 is not None and t2 is not None
        all_rows = await repo.recent_tasks(uow.conn, user_id=user_id, limit=10)
        excl = await repo.recent_tasks(uow.conn, user_id=user_id, limit=10, exclude_ids={t1})
    assert {r["id"] for r in all_rows} == {t1, t2}
    assert {r["id"] for r in excl} == {t2}


async def test_recent_events_orders_and_excludes(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        e1 = await repo.insert_event(uow.conn, user_id=user_id, session_id=None, title="event one")
        e2 = await repo.insert_event(uow.conn, user_id=user_id, session_id=None, title="event two")
        assert e1 is not None and e2 is not None
        all_rows = await repo.recent_events(uow.conn, user_id=user_id, limit=10)
        excl = await repo.recent_events(uow.conn, user_id=user_id, limit=10, exclude_ids={e2})
    assert {r["id"] for r in all_rows} == {e1, e2}
    assert {r["id"] for r in excl} == {e1}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `$env:RUN_INTEGRATION='1'; uv run pytest tests/integration/test_repo_entities_recent.py -q`
Expected: FAIL — `AttributeError: module 'bubbles.db.repo.entities' has no attribute 'recent_tasks'`.

- [ ] **Step 3: Add the two functions**

Append to `server/src/bubbles/db/repo/entities.py`:

```python
async def recent_tasks(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    limit: int = 12,
    exclude_ids: set[UUID] | None = None,
) -> list[asyncpg.Record]:
    """Newest tasks for the user, excluding any id in ``exclude_ids``."""
    return list(
        await conn.fetch(
            """
            SELECT id, title, status, priority, created_at
            FROM tasks
            WHERE user_id = $1 AND NOT (id = ANY($3::uuid[]))
            ORDER BY created_at DESC
            LIMIT $2
            """,
            user_id,
            limit,
            list(exclude_ids or []),
        )
    )


async def recent_events(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    limit: int = 12,
    exclude_ids: set[UUID] | None = None,
) -> list[asyncpg.Record]:
    """Newest events for the user, excluding any id in ``exclude_ids``."""
    return list(
        await conn.fetch(
            """
            SELECT id, title, due_text, description, created_at
            FROM events
            WHERE user_id = $1 AND NOT (id = ANY($3::uuid[]))
            ORDER BY created_at DESC
            LIMIT $2
            """,
            user_id,
            limit,
            list(exclude_ids or []),
        )
    )
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `$env:RUN_INTEGRATION='1'; uv run pytest tests/integration/test_repo_entities_recent.py -q`
Expected: PASS — 2 tests.

- [ ] **Step 5: Lint + commit**

Run: `uv run ruff check src tests; uv run ruff format src tests; uv run mypy`

```powershell
git add server/src/bubbles/db/repo/entities.py server/tests/integration/test_repo_entities_recent.py
git commit -m "feat(scenarios): add recent_tasks/recent_events graph readers"
```

---

## Task 4: scenario generator — router chain, prompt, `ai/scenarios.py`

**Files:**
- Modify: `server/src/bubbles/ai/router.py` (add a `TaskChain` to `DEFAULT_CHAINS`)
- Create: `server/src/bubbles/ai/prompts/scenarios/generate.jinja`
- Create: `server/src/bubbles/ai/scenarios.py`
- Test: `server/tests/unit/test_scenarios_generator.py`

- [ ] **Step 1: Write the failing test**

Create `server/tests/unit/test_scenarios_generator.py`:

```python
"""Unit tests for the scenario generator's pure JSON parser."""

from __future__ import annotations

import json
from uuid import uuid4

from bubbles.ai.scenarios import parse_scenarios


def _item(**over: object) -> dict[str, object]:
    base: dict[str, object] = {
        "target_person": "Sarah",
        "title": "Ask for a raise",
        "situation": "You meet your manager.",
        "goal": "Negotiate confidently",
        "success_criteria": "Made the ask",
        "difficulty": "hard",
        "role_mode": "busy",
        "opening_line": "You wanted to see me?",
        "source_refs": [],
    }
    base.update(over)
    return base


def test_parse_valid_scenario_remaps_refs() -> None:
    pid, tid = uuid4(), uuid4()
    text = json.dumps({"scenarios": [_item(source_refs=["T0"])]})
    rows = parse_scenarios(
        text,
        people_by_name={"sarah": pid},
        task_refs={"T0": tid},
        event_refs={},
        limit=5,
    )
    assert len(rows) == 1
    assert rows[0].target_entity_id == pid
    assert rows[0].difficulty == "hard"
    assert rows[0].source["tasks"] == [str(tid)]
    assert rows[0].source["events"] == []


def test_parse_drops_unknown_person() -> None:
    text = json.dumps({"scenarios": [_item(target_person="ghost")]})
    rows = parse_scenarios(
        text, people_by_name={"sarah": uuid4()}, task_refs={}, event_refs={}, limit=5
    )
    assert rows == []


def test_parse_drops_missing_required_field() -> None:
    text = json.dumps({"scenarios": [_item(title="")]})
    rows = parse_scenarios(
        text, people_by_name={"sarah": uuid4()}, task_refs={}, event_refs={}, limit=5
    )
    assert rows == []


def test_parse_bad_difficulty_falls_back_to_medium() -> None:
    text = json.dumps({"scenarios": [_item(difficulty="impossible")]})
    rows = parse_scenarios(
        text, people_by_name={"sarah": uuid4()}, task_refs={}, event_refs={}, limit=5
    )
    assert len(rows) == 1
    assert rows[0].difficulty == "medium"


def test_parse_invalid_json_returns_empty() -> None:
    rows = parse_scenarios(
        "not json at all",
        people_by_name={"sarah": uuid4()},
        task_refs={},
        event_refs={},
        limit=5,
    )
    assert rows == []


def test_parse_respects_limit() -> None:
    text = json.dumps({"scenarios": [_item(title=f"t{i}") for i in range(5)]})
    rows = parse_scenarios(
        text, people_by_name={"sarah": uuid4()}, task_refs={}, event_refs={}, limit=2
    )
    assert len(rows) == 2
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `uv run pytest tests/unit/test_scenarios_generator.py -q`
Expected: FAIL — `ModuleNotFoundError: bubbles.ai.scenarios`.

- [ ] **Step 3: Register the `scenario.generate` task chain**

In `server/src/bubbles/ai/router.py`, the `DEFAULT_CHAINS` tuple ends with the `analytics.mission_eval` chain. Edit — replace:

```python
    TaskChain(
        "analytics.mission_eval", ("cerebras", "groq", "gemini"), temperature=0.0, max_tokens=300
    ),
)
```
with:
```python
    TaskChain(
        "analytics.mission_eval", ("cerebras", "groq", "gemini"), temperature=0.0, max_tokens=300
    ),
    TaskChain(
        "scenario.generate", ("cerebras", "groq", "gemini"), temperature=0.8, max_tokens=2000
    ),
)
```

- [ ] **Step 4: Write the prompt**

Create `server/src/bubbles/ai/prompts/scenarios/generate.jinja`:

```jinja
You design realistic roleplay practice scenarios so the user can rehearse
real conversations before having them.

Generate up to {{ count }} scenario(s), grounded ONLY in the real people,
tasks and events listed below. Never invent a person, task, or event.

People the user knows:
{% for p in people %}
- {{ p.name }}{% if p.description %} — {{ p.description }}{% endif %}
{% endfor %}

{% if tasks %}
Open tasks (cite by id in source_refs):
{% for t in tasks %}
- [{{ t.ref }}] {{ t.title }}
{% endfor %}
{% endif %}
{% if events %}
Recent events (cite by id in source_refs):
{% for e in events %}
- [{{ e.ref }}] {{ e.title }}{% if e.due_text %} ({{ e.due_text }}){% endif %}
{% endfor %}
{% endif %}
{% if persona_goals %}
The user's communication goals: {{ persona_goals | join(", ") }}.
{% endif %}

Return strictly valid JSON, nothing else:
{
  "scenarios": [
    {
      "target_person": "<exact name from the People list>",
      "title": "<short label, max 8 words>",
      "situation": "<2-3 sentences the user reads before starting>",
      "goal": "<what the user is practicing>",
      "success_criteria": "<how to tell the user did well>",
      "difficulty": "easy|medium|hard",
      "role_mode": "<how the other person behaves, e.g. 'busy and direct'>",
      "opening_line": "<the first line the other person says>",
      "source_refs": ["<task/event ids used, e.g. T0, E1>"]
    }
  ]
}

Rules:
- target_person MUST be copied exactly from the People list.
- Prefer scenarios anchored to a task or event; cite them in source_refs.
  If none fit, a relationship-based scenario with empty source_refs is fine.
- Spread difficulty across the set.
- opening_line is spoken by target_person, in their voice.
- Output only the JSON object.
```

- [ ] **Step 5: Write the generator**

Create `server/src/bubbles/ai/scenarios.py`:

```python
"""Personalized roleplay scenario generator.

Builds practice scenarios from the user's knowledge graph (people, open
tasks, recent events). Used by the ``generate_scenarios`` worker (feed
top-up) and ``POST /v1/scenarios/generate`` (on-demand). ``generate`` never
raises — a failure yields an empty list and the caller degrades.
"""

from __future__ import annotations

import json
from typing import Any, Final
from uuid import UUID

import asyncpg

from bubbles.ai.prompts.loader import render
from bubbles.ai.providers.base import ChatMessage, Role
from bubbles.ai.router import LLMRouter
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.db.repo import entities as entities_repo
from bubbles.db.repo import personas as personas_repo
from bubbles.db.repo import scenarios as scenarios_repo

log = get_logger(__name__)

_VALID_DIFFICULTY: Final[frozenset[str]] = frozenset({"easy", "medium", "hard"})
_MAX_CANDIDATES: Final[int] = 12
_MAX_PEOPLE: Final[int] = 40


def parse_scenarios(
    text: str,
    *,
    people_by_name: dict[str, UUID],
    task_refs: dict[str, UUID],
    event_refs: dict[str, UUID],
    limit: int,
) -> list[scenarios_repo.NewScenario]:
    """Parse the LLM JSON into validated ``NewScenario`` rows. Pure; never raises."""
    try:
        data: Any = json.loads(text)
    except (ValueError, TypeError):
        return []
    items = data.get("scenarios") if isinstance(data, dict) else None
    if not isinstance(items, list):
        return []

    out: list[scenarios_repo.NewScenario] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        person_id = people_by_name.get(str(item.get("target_person", "")).strip().lower())
        if person_id is None:
            continue  # grounded in an unknown person — drop
        title = str(item.get("title", "")).strip()
        situation = str(item.get("situation", "")).strip()
        goal = str(item.get("goal", "")).strip()
        criteria = str(item.get("success_criteria", "")).strip()
        opening = str(item.get("opening_line", "")).strip()
        if not (title and situation and goal and criteria and opening):
            continue
        difficulty = str(item.get("difficulty", "medium")).strip().lower()
        if difficulty not in _VALID_DIFFICULTY:
            difficulty = "medium"
        role_mode = str(item.get("role_mode", "default")).strip()[:60] or "default"
        raw_refs = item.get("source_refs")
        refs = [r for r in raw_refs if isinstance(r, str)] if isinstance(raw_refs, list) else []
        task_ids = [task_refs[r] for r in refs if r in task_refs]
        event_ids = [event_refs[r] for r in refs if r in event_refs]
        out.append(
            scenarios_repo.NewScenario(
                target_entity_id=person_id,
                title=title[:200],
                situation=situation,
                goal=goal,
                success_criteria=criteria,
                difficulty=difficulty,
                role_mode=role_mode,
                opening_line=opening,
                source={
                    "entity_id": str(person_id),
                    "tasks": [str(t) for t in task_ids],
                    "events": [str(e) for e in event_ids],
                },
            )
        )
        if len(out) >= limit:
            break
    return out


async def generate(
    conn: asyncpg.Connection,
    router: LLMRouter,
    *,
    user_id: UUID,
    count: int,
    target_entity_id: UUID | None = None,
) -> list[scenarios_repo.NewScenario]:
    """Generate up to ``count`` scenarios grounded in the user's graph.

    Returns ``[]`` on any failure — never raises.
    """
    if count <= 0:
        return []
    try:
        people = await entities_repo.list_for_user(conn, user_id=user_id, limit=_MAX_PEOPLE)
        people = [e for e in people if (e.entity_type or "").lower() == "person"]
        if target_entity_id is not None:
            people = [e for e in people if e.id == target_entity_id]
        if not people:
            return []

        used_tasks, used_events = await scenarios_repo.used_source_ids(conn, user_id=user_id)
        if target_entity_id is not None:
            name = people[0].display_name or people[0].canonical_name
            task_rows = await entities_repo.tasks_mentioning(
                conn, user_id=user_id, name=name, limit=_MAX_CANDIDATES
            )
            event_rows = await entities_repo.events_mentioning(
                conn, user_id=user_id, name=name, limit=_MAX_CANDIDATES
            )
            task_rows = [r for r in task_rows if r["id"] not in used_tasks]
            event_rows = [r for r in event_rows if r["id"] not in used_events]
        else:
            task_rows = await entities_repo.recent_tasks(
                conn, user_id=user_id, limit=_MAX_CANDIDATES, exclude_ids=used_tasks
            )
            event_rows = await entities_repo.recent_events(
                conn, user_id=user_id, limit=_MAX_CANDIDATES, exclude_ids=used_events
            )

        persona = await personas_repo.get(conn, user_id)
        persona_goals = list(persona.primary_goals) if persona is not None else []

        people_by_name = {
            (e.display_name or e.canonical_name).strip().lower(): e.id for e in people
        }
        task_refs = {f"T{i}": r["id"] for i, r in enumerate(task_rows)}
        event_refs = {f"E{i}": r["id"] for i, r in enumerate(event_rows)}

        prompt = render(
            "scenarios/generate.jinja",
            count=count,
            people=[
                {"name": e.display_name or e.canonical_name, "description": e.description or ""}
                for e in people
            ],
            tasks=[{"ref": f"T{i}", "title": r["title"]} for i, r in enumerate(task_rows)],
            events=[
                {"ref": f"E{i}", "title": r["title"], "due_text": r["due_text"] or ""}
                for i, r in enumerate(event_rows)
            ],
            persona_goals=persona_goals,
        )
        completion = await router.complete(
            "scenario.generate",
            [ChatMessage(role=Role.user, content=prompt)],
            response_format="json",
        )
    except UpstreamUnavailable as exc:
        log.warning("scenario_generate_upstream", error=str(exc), user_id=str(user_id))
        return []
    except Exception as exc:  # graph read failed — degrade, never raise
        log.warning("scenario_generate_failed", error=str(exc), user_id=str(user_id))
        return []

    return parse_scenarios(
        completion.text,
        people_by_name=people_by_name,
        task_refs=task_refs,
        event_refs=event_refs,
        limit=count,
    )
```

- [ ] **Step 6: Run the test, verify it passes**

Run: `uv run pytest tests/unit/test_scenarios_generator.py -q`
Expected: PASS — 6 tests.

- [ ] **Step 7: Verify the prompt renders + chain registered**

Run: `uv run python -c "from bubbles.ai.prompts.loader import render; print(render('scenarios/generate.jinja', count=2, people=[{'name':'Sarah','description':''}], tasks=[], events=[], persona_goals=[]))"`
Expected: prints the rendered prompt with no Jinja error.
Run: `uv run python -c "from bubbles.ai.router import DEFAULT_CHAINS; assert any(c.task=='scenario.generate' for c in DEFAULT_CHAINS)"`
Expected: no output, exit 0.

- [ ] **Step 8: Lint + commit**

Run: `uv run ruff check src tests; uv run ruff format src tests; uv run mypy`

```powershell
git add server/src/bubbles/ai/router.py server/src/bubbles/ai/scenarios.py server/src/bubbles/ai/prompts/scenarios/generate.jinja server/tests/unit/test_scenarios_generator.py
git commit -m "feat(scenarios): add scenario generator, prompt, and router chain"
```

---

## Task 5: scenario wire schemas

**Files:**
- Modify: `server/src/bubbles/api/v1/_schemas.py` (append three classes)

- [ ] **Step 1: Add the schemas**

Append to `server/src/bubbles/api/v1/_schemas.py` (the file already defines `_Base`, imports `UUID`, `datetime`):

```python
class ScenarioOut(_Base):
    id: UUID
    target_entity_id: UUID | None
    title: str
    situation: str
    goal: str
    success_criteria: str
    difficulty: str
    role_mode: str
    opening_line: str
    status: str
    session_id: UUID | None
    passed: bool | None
    score_feedback: str | None
    created_at: datetime


class GenerateScenarioRequest(_Base):
    target_entity_id: UUID


class StartScenarioResponse(_Base):
    session_id: UUID
    scenario: ScenarioOut
```

- [ ] **Step 2: Verify the schemas import**

Run: `uv run python -c "from bubbles.api.v1._schemas import ScenarioOut, GenerateScenarioRequest, StartScenarioResponse"`
Expected: no output, exit 0.

- [ ] **Step 3: Lint + commit**

Run: `uv run ruff check src tests; uv run ruff format src tests; uv run mypy`

```powershell
git add server/src/bubbles/api/v1/_schemas.py
git commit -m "feat(scenarios): add scenario wire schemas"
```

---

## Task 6: `/v1/scenarios` routes

**Files:**
- Create: `server/src/bubbles/api/v1/scenarios.py`
- Modify: `server/src/bubbles/api/router.py` (register the router)
- Test: `server/tests/integration/test_routes_scenarios.py`

- [ ] **Step 1: Write the failing test**

Create `server/tests/integration/test_routes_scenarios.py`:

```python
"""/v1/scenarios route integration tests."""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence
from typing import Any
from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.ai.providers.base import ChatMessage, Chunk, Completion, ResponseFormat, Usage
from bubbles.ai.router import LLMRouter, TaskChain
from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.core.ratelimit import RateLimitResult
from bubbles.deps import get_pool, get_ratelimiter, get_router

pytestmark = pytest.mark.integration

_SCENARIO_JSON = (
    '{"scenarios": [{"target_person": "sarah", "title": "Ask for a raise",'
    ' "situation": "You meet your manager.", "goal": "Negotiate",'
    ' "success_criteria": "Made the ask", "difficulty": "medium",'
    ' "role_mode": "busy", "opening_line": "You wanted to see me?",'
    ' "source_refs": []}]}'
)


class _Stub:
    name = "stub"
    default_model = "m"

    async def complete(
        self,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
        response_format: ResponseFormat = "text",
        timeout_s: float = 25.0,
    ) -> Completion:
        return Completion(
            text=_SCENARIO_JSON, finish_reason="stop", usage=Usage(3, 5, 8), raw={"model": "stub"}
        )

    async def stream(
        self,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
        timeout_s: float = 25.0,
    ) -> AsyncIterator[Chunk]:
        yield Chunk(text=_SCENARIO_JSON, finish_reason="stop", usage=Usage(3, 5, 8))


class _FakeLimiter:
    async def check(
        self, key: str, *, capacity: int, refill_per_s: float, cost: int = 1
    ) -> RateLimitResult:
        return RateLimitResult(allowed=True, tokens_left=float(capacity), retry_after_s=0)


def _router() -> LLMRouter:
    return LLMRouter([_Stub()], [TaskChain("scenario.generate", ("stub",))])


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[get_router] = _router
    app.dependency_overrides[get_ratelimiter] = lambda: _FakeLimiter()
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )


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


async def test_generate_then_list(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    eid = await _entity(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        gen = await ac.post("/v1/scenarios/generate", json={"target_entity_id": str(eid)})
        lst = await ac.get("/v1/scenarios")
    assert gen.status_code == 201
    assert gen.json()["title"] == "Ask for a raise"
    assert gen.json()["status"] == "suggested"
    body = lst.json()
    assert len(body) == 1
    assert body[0]["target_entity_id"] == str(eid)


async def test_generate_rejects_other_users_entity(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    other = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", other)
    eid = await _entity(pool, other)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post("/v1/scenarios/generate", json={"target_entity_id": str(eid)})
    assert r.status_code == 403


async def test_start_creates_roleplay_session(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    eid = await _entity(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        gen = await ac.post("/v1/scenarios/generate", json={"target_entity_id": str(eid)})
        sid = gen.json()["id"]
        started = await ac.post(f"/v1/scenarios/{sid}/start")
        # Second start must 409 — no longer suggested.
        again = await ac.post(f"/v1/scenarios/{sid}/start")
    assert started.status_code == 200
    body = started.json()
    assert body["scenario"]["status"] == "started"
    session_id = body["session_id"]
    async with pool.acquire() as con:
        mode = await con.fetchval("SELECT mode FROM sessions WHERE id = $1", UUID(session_id))
    assert mode == "roleplay"
    assert again.status_code == 409


async def test_dismiss_then_gone_from_feed(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    eid = await _entity(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        gen = await ac.post("/v1/scenarios/generate", json={"target_entity_id": str(eid)})
        sid = gen.json()["id"]
        dis = await ac.post(f"/v1/scenarios/{sid}/dismiss")
        lst = await ac.get("/v1/scenarios")
    assert dis.status_code == 200
    assert dis.json()["status"] == "dismissed"
    assert lst.json() == []


async def test_start_unknown_scenario_404(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(f"/v1/scenarios/{uuid4()}/start")
    assert r.status_code == 404
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `$env:RUN_INTEGRATION='1'; uv run pytest tests/integration/test_routes_scenarios.py -q`
Expected: FAIL — 404s on `/v1/scenarios/*` (router not registered).

- [ ] **Step 3: Write the routes**

Create `server/src/bubbles/api/v1/scenarios.py`:

```python
"""Personalized roleplay scenario routes.

Scenarios are generated from the user's knowledge graph (see
``bubbles.ai.scenarios``). The feed is topped up by the ``generate_scenarios``
worker; ``POST /scenarios/generate`` is the synchronous on-demand path.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Query

from bubbles.ai import scenarios as scenario_gen
from bubbles.api.v1._schemas import (
    GenerateScenarioRequest,
    ScenarioOut,
    StartScenarioResponse,
)
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import Conflict, NotFound, RateLimited, UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.db.repo import entities as entities_repo
from bubbles.db.repo import scenarios as scenarios_repo
from bubbles.db.repo import sessions as sessions_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep, RateLimiterDep, RouterDep

log = get_logger(__name__)
router = APIRouter(tags=["scenarios"])

_GENERATE_CAPACITY = 10
_GENERATE_REFILL_PER_S = 10 / 60  # ~10 generations per minute


def _to_out(s: object) -> ScenarioOut:
    return ScenarioOut.model_validate(s, from_attributes=True)


@router.get("/scenarios", response_model=list[ScenarioOut])
async def list_scenarios(
    user: CurrentUserDep,
    pool: PoolDep,
    status: str = Query("suggested", pattern="^(suggested|started|completed|dismissed)$"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> list[ScenarioOut]:
    async with transaction(pool) as conn:
        rows = await scenarios_repo.list_for_user(
            conn, user_id=UUID(user.id), status=status, limit=limit, offset=offset
        )
    return [_to_out(r) for r in rows]


@router.post("/scenarios/generate", response_model=ScenarioOut, status_code=201)
async def generate_scenario(
    body: GenerateScenarioRequest,
    user: CurrentUserDep,
    pool: PoolDep,
    llm_router: RouterDep,
    limiter: RateLimiterDep,
) -> ScenarioOut:
    rl = await limiter.check(
        f"scenarios:generate:{user.id}",
        capacity=_GENERATE_CAPACITY,
        refill_per_s=_GENERATE_REFILL_PER_S,
    )
    if not rl.allowed:
        raise RateLimited(rl.retry_after_s)

    user_uuid = UUID(user.id)
    async with transaction(pool) as conn:
        entity = await entities_repo.get_entity(conn, body.target_entity_id)
    if entity is None:
        raise NotFound("entity not found")
    require_ownership(user, str(entity.user_id))

    async with transaction(pool) as conn:
        drafts = await scenario_gen.generate(
            conn,
            llm_router,
            user_id=user_uuid,
            count=1,
            target_entity_id=body.target_entity_id,
        )
    if not drafts:
        raise UpstreamUnavailable("could not generate a scenario — try again")

    async with UnitOfWork(pool) as uow:
        created = await scenarios_repo.create_many(uow.conn, user_id=user_uuid, rows=drafts)
    return _to_out(created[0])


@router.post("/scenarios/{scenario_id}/start", response_model=StartScenarioResponse)
async def start_scenario(
    scenario_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> StartScenarioResponse:
    async with transaction(pool) as conn:
        scenario = await scenarios_repo.get(conn, scenario_id)
    if scenario is None:
        raise NotFound("scenario not found")
    require_ownership(user, str(scenario.user_id))
    if scenario.status != "suggested":
        raise Conflict("scenario is not startable")

    session_context = {
        "scenario": scenario.situation,
        "role_mode": scenario.role_mode,
        "notes": scenario.goal,
        "opening_line": scenario.opening_line,
    }
    async with UnitOfWork(pool) as uow:
        session = await sessions_repo.start(
            uow.conn,
            user_id=UUID(user.id),
            title=scenario.title,
            mode="roleplay",
            session_context=session_context,
        )
        started = await scenarios_repo.mark_started(
            uow.conn, scenario_id=scenario_id, session_id=session.id
        )
    if started is None:
        raise Conflict("scenario is not startable")
    return StartScenarioResponse(session_id=session.id, scenario=_to_out(started))


@router.post("/scenarios/{scenario_id}/dismiss", response_model=ScenarioOut)
async def dismiss_scenario(
    scenario_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> ScenarioOut:
    async with transaction(pool) as conn:
        scenario = await scenarios_repo.get(conn, scenario_id)
    if scenario is None:
        raise NotFound("scenario not found")
    require_ownership(user, str(scenario.user_id))
    async with UnitOfWork(pool) as uow:
        dismissed = await scenarios_repo.mark_dismissed(uow.conn, scenario_id=scenario_id)
    if dismissed is None:
        raise Conflict("scenario cannot be dismissed")
    return _to_out(dismissed)
```

- [ ] **Step 4: Register the router**

In `server/src/bubbles/api/router.py`, add the import next to the other v1 imports (alphabetical — after `persona`):

```python
from bubbles.api.v1.scenarios import router as scenarios_router
```

and add the `include_router` call after `persona_router`:

```python
v1_router.include_router(scenarios_router)
```

- [ ] **Step 5: Run the test, verify it passes**

Run: `$env:RUN_INTEGRATION='1'; uv run pytest tests/integration/test_routes_scenarios.py -q`
Expected: PASS — 5 tests.

- [ ] **Step 6: Lint + commit**

Run: `uv run ruff check src tests; uv run ruff format src tests; uv run mypy`

```powershell
git add server/src/bubbles/api/v1/scenarios.py server/src/bubbles/api/router.py server/tests/integration/test_routes_scenarios.py
git commit -m "feat(scenarios): add /v1/scenarios list/generate/start/dismiss routes"
```

---

## Task 7: `generate_scenarios` feed worker

**Files:**
- Create: `server/src/bubbles/workers/jobs/generate_scenarios.py`
- Modify: `server/src/bubbles/workers/enqueue.py` (append `enqueue_generate_scenarios`)
- Modify: `server/src/bubbles/workers/arq_settings.py` (import + registry entry)
- Test: `server/tests/integration/test_workers_scenarios.py`

- [ ] **Step 1: Write the failing test**

Create `server/tests/integration/test_workers_scenarios.py`:

```python
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
    ctx: dict[str, Any] = {"bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)}
    created = await generate_scenarios.run(ctx, user_id=str(user_id))
    assert created == 0


async def test_generate_scenarios_fills_gap(
    pool: asyncpg.Pool, user_id: UUID, monkeypatch: pytest.MonkeyPatch
) -> None:
    eid = await _entity(pool, user_id)

    async def _two(*_a: Any, **kw: Any) -> list[scenarios_repo.NewScenario]:
        return [_draft(eid) for _ in range(kw["count"])]

    monkeypatch.setattr(generate_scenarios.scenario_gen, "generate", _two)
    ctx: dict[str, Any] = {"bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)}
    created = await generate_scenarios.run(ctx, user_id=str(user_id))
    assert created == 5
    async with pool.acquire() as con:
        n = await con.fetchval(
            "SELECT COUNT(*)::int FROM scenarios WHERE user_id = $1", user_id
        )
    assert n == 5
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `$env:RUN_INTEGRATION='1'; uv run pytest tests/integration/test_workers_scenarios.py -q`
Expected: FAIL — `ImportError: cannot import name 'generate_scenarios'`.

- [ ] **Step 3: Write the worker**

Create `server/src/bubbles/workers/jobs/generate_scenarios.py`:

```python
"""generate_scenarios worker — tops up a user's roleplay scenario feed.

Enqueued from the end_session fan-out. Self-throttling: a no-op when the
feed already holds ``_TARGET_FEED`` suggested scenarios.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from bubbles.ai import scenarios as scenario_gen
from bubbles.core.logging import get_logger
from bubbles.db.repo import scenarios as scenarios_repo
from bubbles.db.uow import UnitOfWork, transaction

log = get_logger(__name__)

_TARGET_FEED = 5


async def run(ctx: dict[str, Any], *, user_id: str) -> int:
    """Generate scenarios until the feed reaches ``_TARGET_FEED``. Returns count created."""
    bub = ctx["bubbles"]
    uid = UUID(user_id)
    async with transaction(bub.pool) as conn:
        active = await scenarios_repo.count_active(conn, user_id=uid)
    gap = _TARGET_FEED - active
    if gap <= 0:
        return 0
    async with transaction(bub.pool) as conn:
        drafts = await scenario_gen.generate(conn, bub.ai.router, user_id=uid, count=gap)
    if not drafts:
        return 0
    async with UnitOfWork(bub.pool) as uow:
        created = await scenarios_repo.create_many(uow.conn, user_id=uid, rows=drafts)
    log.info("generate_scenarios_done", user=user_id, created=len(created))
    return len(created)
```

- [ ] **Step 4: Add the enqueue helper**

Append to `server/src/bubbles/workers/enqueue.py`:

```python
async def enqueue_generate_scenarios(
    arq: ArqRedis, *, user_id: str, session_id: str
) -> Any:
    return await arq.enqueue_job(
        "run",
        _job_name="generate_scenarios",
        user_id=user_id,
        _job_id=f"genscenarios:{_hash_id((user_id, session_id))}",
    )
```

- [ ] **Step 5: Register the job**

In `server/src/bubbles/workers/arq_settings.py`, add `generate_scenarios` to the `from bubbles.workers.jobs import (...)` block (alphabetical — after `extract_knowledge`):

```python
    extract_knowledge,
    generate_scenarios,
    grammar_scan,
```

and add to the `_JOB_REGISTRY` dict:

```python
    "generate_scenarios": generate_scenarios.run,
```

- [ ] **Step 6: Run the test, verify it passes**

Run: `$env:RUN_INTEGRATION='1'; uv run pytest tests/integration/test_workers_scenarios.py -q`
Expected: PASS — 2 tests.

- [ ] **Step 7: Lint + commit**

Run: `uv run ruff check src tests; uv run ruff format src tests; uv run mypy`

```powershell
git add server/src/bubbles/workers/jobs/generate_scenarios.py server/src/bubbles/workers/enqueue.py server/src/bubbles/workers/arq_settings.py server/tests/integration/test_workers_scenarios.py
git commit -m "feat(scenarios): add generate_scenarios feed worker"
```

---

## Task 8: `score_scenario` worker

**Files:**
- Create: `server/src/bubbles/workers/jobs/score_scenario.py`
- Modify: `server/src/bubbles/workers/enqueue.py` (append `enqueue_score_scenario`)
- Modify: `server/src/bubbles/workers/arq_settings.py` (import + registry entry)
- Test: `server/tests/integration/test_workers_scenarios.py` (append)

- [ ] **Step 1: Add the failing test**

Append to `server/tests/integration/test_workers_scenarios.py`:

```python
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
    ctx: dict[str, Any] = {"bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool)}
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
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `$env:RUN_INTEGRATION='1'; uv run pytest tests/integration/test_workers_scenarios.py::test_score_scenario_writes_result_and_awards_xp -q`
Expected: FAIL — `ImportError: cannot import name 'score_scenario'`.

- [ ] **Step 3: Write the worker**

Create `server/src/bubbles/workers/jobs/score_scenario.py`:

```python
"""score_scenario worker — grades a finished roleplay against its scenario.

Enqueued from end_session when the ended session was started from a
scenario. Reuses ``evaluate_conversation_mission`` and awards XP on a pass.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from bubbles.ai.extraction import evaluate_conversation_mission
from bubbles.core.logging import get_logger
from bubbles.db.repo import scenarios as scenarios_repo
from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.db.repo import xp as xp_repo
from bubbles.db.uow import UnitOfWork, transaction

log = get_logger(__name__)

_XP_SCENARIO_PASS = 40
_MIN_TURNS = 4


async def run(ctx: dict[str, Any], *, scenario_id: str) -> dict[str, Any]:
    """Grade the scenario's linked session; persist pass/fail + feedback."""
    bub = ctx["bubbles"]
    sid = UUID(scenario_id)
    async with transaction(bub.pool) as conn:
        scenario = await scenarios_repo.get(conn, sid)
        if scenario is None or scenario.session_id is None:
            return {"scored": False, "reason": "no linked session"}
        transcript = await session_logs_repo.assemble_transcript(
            conn, session_id=scenario.session_id
        )
        user_turns = await session_logs_repo.role_count(
            conn, session_id=scenario.session_id, role="user"
        )
    if not transcript:
        return {"scored": False, "reason": "empty transcript"}

    passed, reason = await evaluate_conversation_mission(
        bub.ai.router,
        criteria=f"{scenario.goal}\n{scenario.success_criteria}",
        transcript=transcript,
        min_turns=_MIN_TURNS,
        user_turns=user_turns,
    )
    async with UnitOfWork(bub.pool) as uow:
        await scenarios_repo.mark_completed(
            uow.conn, scenario_id=sid, passed=passed, feedback=reason
        )
        if passed:
            await xp_repo.record(
                uow.conn,
                user_id=scenario.user_id,
                amount=_XP_SCENARIO_PASS,
                source_type="scenario",
                source_id=str(sid),
                description="Completed a roleplay scenario",
            )
    log.info("score_scenario_done", scenario=scenario_id, passed=passed)
    return {"scored": True, "passed": passed}
```

- [ ] **Step 4: Add the enqueue helper**

Append to `server/src/bubbles/workers/enqueue.py`:

```python
async def enqueue_score_scenario(arq: ArqRedis, *, scenario_id: str) -> Any:
    return await arq.enqueue_job(
        "run",
        _job_name="score_scenario",
        scenario_id=scenario_id,
        _job_id=f"scorescenario:{scenario_id}",
    )
```

- [ ] **Step 5: Register the job**

In `server/src/bubbles/workers/arq_settings.py`, add `score_scenario` to the `from bubbles.workers.jobs import (...)` block (alphabetical — after `rolling_summarize`):

```python
    rolling_summarize,
    score_scenario,
    seed_quests,
```

and add to `_JOB_REGISTRY`:

```python
    "score_scenario": score_scenario.run,
```

- [ ] **Step 6: Run the test, verify it passes**

Run: `$env:RUN_INTEGRATION='1'; uv run pytest tests/integration/test_workers_scenarios.py -q`
Expected: PASS — 3 tests.

- [ ] **Step 7: Lint + commit**

Run: `uv run ruff check src tests; uv run ruff format src tests; uv run mypy`

```powershell
git add server/src/bubbles/workers/jobs/score_scenario.py server/src/bubbles/workers/enqueue.py server/src/bubbles/workers/arq_settings.py server/tests/integration/test_workers_scenarios.py
git commit -m "feat(scenarios): add score_scenario worker with XP award"
```

---

## Task 9: wire `end_session` fan-out

**Files:**
- Modify: `server/src/bubbles/api/v1/sessions.py` (`_enqueue_post_session_jobs` + `end_session`)
- Modify: `server/tests/integration/test_routes_sessions.py` (correct two stale assertions, add one test)

> **Note:** `test_routes_sessions.py` currently asserts the fan-out enqueues exactly `["compute_session_analytics", "extract_knowledge", "compute_embeddings"]`. The current `_enqueue_post_session_jobs` already enqueues five jobs (it also calls `detect_achievements` and `sentiment_scan`), so those two assertions are **already stale**. This task corrects them to the full post-change list.

- [ ] **Step 1: Update the enqueue imports**

In `server/src/bubbles/api/v1/sessions.py`, the import from `bubbles.workers.enqueue` lists five helpers. Replace that block:

```python
from bubbles.workers.enqueue import (
    enqueue_compute_embeddings,
    enqueue_detect_achievements,
    enqueue_extract_knowledge,
    enqueue_sentiment_scan,
    enqueue_session_analytics,
)
```
with:
```python
from bubbles.workers.enqueue import (
    enqueue_compute_embeddings,
    enqueue_detect_achievements,
    enqueue_extract_knowledge,
    enqueue_generate_scenarios,
    enqueue_score_scenario,
    enqueue_sentiment_scan,
    enqueue_session_analytics,
)
```

Also add the scenarios-repo import next to the other repo imports:

```python
from bubbles.db.repo import scenarios as scenarios_repo
```

- [ ] **Step 2: Update `_enqueue_post_session_jobs`**

Replace the whole `_enqueue_post_session_jobs` function in `sessions.py`:

```python
async def _enqueue_post_session_jobs(
    arq: ArqRedis,
    *,
    user_id: str,
    session_id: str,
    transcript: str,
    scenario_id: str | None = None,
) -> None:
    """Best-effort: a queue hiccup must not fail the ``end_session`` write."""
    try:
        await enqueue_session_analytics(
            arq, user_id=user_id, session_id=session_id, transcript=transcript
        )
        await enqueue_extract_knowledge(
            arq, user_id=user_id, session_id=session_id, transcript=transcript
        )
        await enqueue_compute_embeddings(arq, user_id=user_id)
        await enqueue_detect_achievements(arq, user_id=user_id)
        # Score per-turn sentiment, then it re-runs compute_session_analytics so
        # the metrics row picks up avg_sentiment_score / dominant_sentiment.
        await enqueue_sentiment_scan(arq, user_id=user_id, session_id=session_id)
        # Top up the user's personalized roleplay scenario feed.
        await enqueue_generate_scenarios(arq, user_id=user_id, session_id=session_id)
        # If this session was a roleplay started from a scenario, grade it.
        if scenario_id is not None:
            await enqueue_score_scenario(arq, scenario_id=scenario_id)
    except Exception as exc:
        log.warning("post_session_enqueue_failed", error=str(exc), session_id=session_id)
```

- [ ] **Step 3: Pass the linked scenario id from `end_session`**

In `end_session`, replace the post-session enqueue block. Replace:

```python
    transcript = row_transcript or (body.transcript or "")
    if arq is not None and transcript:
        await _enqueue_post_session_jobs(
            arq,
            user_id=str(existing.user_id),
            session_id=str(body.session_id),
            transcript=transcript,
        )
    return _to_out(ended)
```
with:
```python
    transcript = row_transcript or (body.transcript or "")
    if arq is not None and transcript:
        async with transaction(pool) as conn:
            linked = await scenarios_repo.get_by_session(conn, session_id=body.session_id)
        await _enqueue_post_session_jobs(
            arq,
            user_id=str(existing.user_id),
            session_id=str(body.session_id),
            transcript=transcript,
            scenario_id=str(linked.id) if linked is not None else None,
        )
    return _to_out(ended)
```

- [ ] **Step 4: Correct the two stale assertions + add a scenario-linked test**

In `server/tests/integration/test_routes_sessions.py`, in `test_end_session_with_transcript_enqueues_jobs`, replace:

```python
    names = [kw["_job_name"] for (_, kw) in arq.calls]
    assert names == ["compute_session_analytics", "extract_knowledge", "compute_embeddings"]
    assert all(kw.get("user_id") == str(user_id) for (_, kw) in arq.calls)
```
with:
```python
    names = [kw["_job_name"] for (_, kw) in arq.calls]
    assert names == [
        "compute_session_analytics",
        "extract_knowledge",
        "compute_embeddings",
        "detect_achievements",
        "sentiment_scan",
        "generate_scenarios",
    ]
```

In `test_end_session_assembles_transcript_from_rows`, replace:

```python
    assert [kw["_job_name"] for (_, kw) in arq.calls] == [
        "compute_session_analytics",
        "extract_knowledge",
        "compute_embeddings",
    ]
```
with:
```python
    assert [kw["_job_name"] for (_, kw) in arq.calls] == [
        "compute_session_analytics",
        "extract_knowledge",
        "compute_embeddings",
        "detect_achievements",
        "sentiment_scan",
        "generate_scenarios",
    ]
```

Then append this new test to the file:

```python
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
    assert "score_scenario" in names
    score_call = next(kw for (_, kw) in arq.calls if kw["_job_name"] == "score_scenario")
    assert score_call["scenario_id"] == str(scn["id"])
```

- [ ] **Step 5: Run the session route tests, verify they pass**

Run: `$env:RUN_INTEGRATION='1'; uv run pytest tests/integration/test_routes_sessions.py -q`
Expected: PASS — all tests, including the corrected assertions and the new scenario-linked test.

- [ ] **Step 6: Lint + commit**

Run: `uv run ruff check src tests; uv run ruff format src tests; uv run mypy`

```powershell
git add server/src/bubbles/api/v1/sessions.py server/tests/integration/test_routes_sessions.py
git commit -m "feat(scenarios): enqueue generate_scenarios + score_scenario from end_session"
```

---

## Task 10: Documentation — server changes + app requirements

**Files:**
- Create: `Documentation/feature-1-personalized-roleplay.md`

- [ ] **Step 1: Write the documentation**

Create `Documentation/feature-1-personalized-roleplay.md`:

```markdown
# Feature 1 — Personalized Roleplay Scenarios

Generates roleplay practice scenarios from the user's knowledge graph
(people, open tasks, recent events). Delivered as a browsable feed plus an
on-demand "generate for this person" action.

## Server side — what was built

**Table** `scenarios` (migration `0006`): per-user scenario rows —
`title, situation, goal, success_criteria, difficulty, role_mode,
opening_line, target_entity_id, source (jsonb), status, session_id,
passed, score_feedback`. Status lifecycle: `suggested → started →
completed`, or `suggested → dismissed`.

**Generator** `bubbles.ai.scenarios.generate` — pulls the user's person
entities, open tasks and recent events, renders
`ai/prompts/scenarios/generate.jinja`, and calls the `scenario.generate`
LLM task chain. Already-used tasks/events are excluded so the feed does not
repeat itself. Never raises — failure yields an empty list.

**Endpoints** (all under `/v1`, JWT-authenticated, ownership-checked):

| Method | Path | Purpose |
|---|---|---|
| GET  | `/v1/scenarios?status=suggested&limit=&offset=` | The feed. `status` ∈ suggested/started/completed/dismissed. |
| POST | `/v1/scenarios/generate` | Body `{target_entity_id}`. Generates one scenario synchronously (~1-3 s). Rate-limited ~10/min/user. `201` with the scenario; `403` if the entity is not the caller's; `404` unknown entity; `503` if generation failed (retry). |
| POST | `/v1/scenarios/{id}/start` | Creates a roleplay session from the scenario, links it, returns `{session_id, scenario}`. `409` if the scenario is not `suggested`. |
| POST | `/v1/scenarios/{id}/dismiss` | Drops the scenario from the feed. `409` if already started/completed. |

**Workers:**
- `generate_scenarios` — tops the feed up to 5 `suggested` scenarios.
  Enqueued from the `end_session` fan-out; self-throttling (no-op when full).
- `score_scenario` — when a scenario-linked session ends, grades the
  transcript against the scenario's goal + success criteria
  (reuses `evaluate_conversation_mission`), writes `passed` +
  `score_feedback`, and awards 40 XP on a pass (`source_type='scenario'`,
  idempotent).

**Speed:** feed generation and scoring run in ARQ workers; on-demand
generation is a dedicated rate-limited endpoint. The wingman per-turn loop
and its 0.5 s context budget are untouched.

## App side — what is required (Flutter)

1. **Practice screen** — a new screen listing the scenario feed via
   `GET /v1/scenarios`. Each card shows `title`, the person's name, a
   `difficulty` badge, and a snippet of `situation` / `opening_line`.
   Show an empty state when the feed is empty (new users with no graph data).

2. **Generate action** — a "New scenario" button → entity picker (the user
   picks a known person) → `POST /v1/scenarios/generate` with a loading
   spinner (call takes 1-3 s). On `503`, show a "try again" message.

3. **Start a scenario** — tapping a card calls
   `POST /v1/scenarios/{id}/start`. Use the returned `session_id` and the
   scenario's `target_entity_id` to open the existing roleplay session UI.
   **The wingman turn calls for that session must send `mode="roleplay"`
   and `target_entity_id`** (the scenario's `target_entity_id`) so the LLM
   embodies the right person. Show `opening_line` as the partner's first
   message.

4. **Dismiss** — swipe / overflow action on a card →
   `POST /v1/scenarios/{id}/dismiss`; remove it from the list.

5. **Score display** — after a roleplay session started from a scenario
   ends, the server scores it asynchronously. Re-fetch the scenario
   (`GET /v1/scenarios?status=completed`) to show `passed` and
   `score_feedback` on a results screen.

6. **No app-side generation logic** — scenarios are entirely server-built;
   the app only lists, generates-on-demand, starts, and dismisses.
```

- [ ] **Step 2: Commit**

```powershell
git add Documentation/feature-1-personalized-roleplay.md
git commit -m "docs(scenarios): server changes + app-side requirements for Feature 1"
```

---

## Final verification

- [ ] Run the full lint + type gate: `uv run ruff check src tests; uv run ruff format --check src tests; uv run mypy` — all clean.
- [ ] Run the unit suite: `uv run pytest tests/unit -q` — green.
- [ ] Run the integration suite (Docker required): `$env:RUN_INTEGRATION='1'; uv run pytest tests/integration -q` — green.
- [ ] Confirm `scenario.generate` is registered: `uv run python -c "from bubbles.ai.router import DEFAULT_CHAINS; assert any(c.task=='scenario.generate' for c in DEFAULT_CHAINS)"`.
- [ ] Confirm the router is mounted: `uv run python -c "from bubbles.app import create_app; print([r.path for r in create_app().routes if 'scenario' in r.path])"` — lists the four `/v1/scenarios` paths.

## Self-review notes

- **Spec coverage:** all 14 scope items map to tasks — migration/table/baseline/teardown (T1), model (T1), repo (T2), `recent_tasks`/`recent_events` (T3), generator + prompt (T4), router chain (T4), schemas (T5), four routes + router registration (T6), `generate_scenarios` worker + enqueue + registration (T7), `score_scenario` worker + enqueue + registration (T8), `end_session` fan-out (T9). All five spec test files are produced (repo, routes, workers, generator unit, sessions extension).
- **Type consistency:** `NewScenario` (defined T2) is the generator's output type and the repo's `create_many` input — used identically in T4, T6, T7. `parse_scenarios` / `generate` signatures in T4 match their callers in T6/T7. `_enqueue_post_session_jobs`' new `scenario_id` param (T9) matches the `enqueue_score_scenario` helper (T8).
- **Pre-existing issue corrected:** T9 Step 4 fixes two `test_routes_sessions.py` assertions that were already stale against the current five-job fan-out.
```
