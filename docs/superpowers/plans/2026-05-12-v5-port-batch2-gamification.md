# Batch 2 — Gamification HTTP Routes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the v2 gamification HTTP surface (6 endpoints) into Bubbles Brain API v5 — profile, daily quests, reward catalog + redeem, leaderboard, leaderboard opt-in — backed by new `xp_transactions` / `achievements` / `user_achievements` tables and pure level-math helpers.

**Architecture:** New Alembic migration `0003` adds three tables (no-op against the live Supabase DB, which already has them). New pure module `bubbles/core/gamification.py` holds the level formula. New repos `db/repo/xp.py` and `db/repo/achievements.py`; `db/repo/gamification.py` gains a few queries. New route module `bubbles/api/v1/gamification.py` wires the 6 endpoints with the existing `CurrentUser` + `require_ownership` auth path and `transaction()` / `UnitOfWork` patterns. Wire-schemas live in `_schemas.py`.

**Tech Stack:** Python 3.11, FastAPI, asyncpg, Alembic, Pydantic v2, pytest (+ testcontainers for integration), `uv` / `ruff` / `mypy --strict`. Spec: `docs/superpowers/specs/2026-05-12-v5-port-batch2-gamification-design.md`.

**Working directory for all commands:** `server/` (i.e. `cd server` first). The local gate is `uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest` — `make` is not installed on the dev box. Integration tests are marked `@pytest.mark.integration` and module-level auto-skip unless `RUN_INTEGRATION=1` **and** the docker SDK is importable; locally they collect-skip, which is expected — they run in CI.

**Branch:** create `feat/v5-port-batch2-gamification` off `main` before Task 1 (do not work on `main`). The subagent-driven-development skill handles branch creation if it isn't there yet.

---

### Task 1: DB migration `0003` + test baseline + teardown

**Files:**
- Create: `server/alembic/versions/2026_05_12_0003_gamification_tables.py`
- Modify: `server/tests/integration/fixtures/baseline.sql` (append three `CREATE TABLE` blocks)
- Modify: `server/tests/integration/conftest.py` (extend the teardown `DROP TABLE` list)

- [ ] **Step 1: Write the migration**

Create `server/alembic/versions/2026_05_12_0003_gamification_tables.py`:

```python
"""gamification tables: xp_transactions, achievements, user_achievements

These three tables already exist in the live Supabase database
(``Documentation/db_schema.sql``); ``upgrade()`` is therefore a no-op there
(``CREATE TABLE IF NOT EXISTS``), matching how the ``0001`` baseline behaves.
The test baseline schema (``tests/integration/fixtures/baseline.sql``) gets
the same tables so integration tests can exercise the new repos.

Revision ID: 0003
Revises: 0002
Create Date: 2026-05-12 00:00:00 UTC
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS xp_transactions (
            id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
            amount      integer     NOT NULL,
            source_type text        NOT NULL,
            source_id   text,
            description text,
            created_at  timestamptz NOT NULL DEFAULT now()
        );
        CREATE UNIQUE INDEX IF NOT EXISTS xp_transactions_dedup_idx
            ON xp_transactions (user_id, source_type, source_id) WHERE source_id IS NOT NULL;
        CREATE INDEX IF NOT EXISTS xp_transactions_user_recent_idx
            ON xp_transactions (user_id, created_at DESC);
        CREATE INDEX IF NOT EXISTS xp_transactions_period_idx
            ON xp_transactions (created_at, user_id) WHERE amount > 0;

        CREATE TABLE IF NOT EXISTS achievements (
            id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
            code           text        UNIQUE,
            title          text        NOT NULL,
            description    text,
            icon           text        DEFAULT '🏆',
            category       text        DEFAULT 'general',
            criteria_type  text        NOT NULL,
            criteria_value integer     NOT NULL,
            xp_reward      integer     DEFAULT 0,
            tier           text,
            created_at     timestamptz NOT NULL DEFAULT now()
        );

        CREATE TABLE IF NOT EXISTS user_achievements (
            id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id        uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
            achievement_id uuid        NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
            awarded_at     timestamptz NOT NULL DEFAULT now(),
            UNIQUE (user_id, achievement_id)
        );
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP TABLE IF EXISTS user_achievements;
        DROP TABLE IF EXISTS achievements;
        DROP TABLE IF EXISTS xp_transactions;
        """
    )
```

- [ ] **Step 2: Append the three tables to the test baseline**

In `server/tests/integration/fixtures/baseline.sql`, immediately **after** the `CREATE TABLE user_rewards (...)` block (and before `CREATE TABLE memory (...)`), insert:

```sql
CREATE TABLE xp_transactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount integer NOT NULL,
    source_type text NOT NULL,
    source_id text,
    description text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX xp_transactions_dedup_idx
    ON xp_transactions (user_id, source_type, source_id) WHERE source_id IS NOT NULL;
CREATE INDEX xp_transactions_user_recent_idx ON xp_transactions (user_id, created_at DESC);
CREATE INDEX xp_transactions_period_idx ON xp_transactions (created_at, user_id) WHERE amount > 0;

CREATE TABLE achievements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text UNIQUE,
    title text NOT NULL,
    description text,
    icon text DEFAULT '🏆',
    category text DEFAULT 'general',
    criteria_type text NOT NULL,
    criteria_value integer NOT NULL,
    xp_reward integer DEFAULT 0,
    tier text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_achievements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    achievement_id uuid NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
    awarded_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, achievement_id)
);
```

- [ ] **Step 3: Extend the integration teardown**

In `server/tests/integration/conftest.py`, the `pool` fixture's teardown currently runs:

```python
DROP TABLE IF EXISTS session_entities, events, tasks,
    user_rewards, rewards, user_quests, quest_definitions,
    user_gamification, user_mistakes, memory, user_personas,
    entity_relations, entities, sessions CASCADE;
```

Change it to add the three new tables (place them right after `user_rewards, rewards,`):

```python
DROP TABLE IF EXISTS session_entities, events, tasks,
    user_rewards, rewards, user_achievements, achievements, xp_transactions,
    user_quests, quest_definitions,
    user_gamification, user_mistakes, memory, user_personas,
    entity_relations, entities, sessions CASCADE;
```

- [ ] **Step 4: Verify the migration imports and the gate is green**

Run (from `server/`):
```bash
uv run python -c "import alembic.versions.__init__" 2>/dev/null; uv run python - <<'PY'
import importlib.util, pathlib
p = pathlib.Path("alembic/versions/2026_05_12_0003_gamification_tables.py")
spec = importlib.util.spec_from_file_location("m0003", p)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.revision == "0003" and m.down_revision == "0002"
print("0003 ok")
PY
uv run ruff check . && uv run ruff format --check . && uv run mypy
```
Expected: prints `0003 ok`; ruff clean; `mypy` reports `Success`.

- [ ] **Step 5: Commit**

```bash
git add server/alembic/versions/2026_05_12_0003_gamification_tables.py server/tests/integration/fixtures/baseline.sql server/tests/integration/conftest.py
git commit -m "feat(db): migration 0003 — xp_transactions, achievements, user_achievements"
```

---

### Task 2: DB models

**Files:**
- Modify: `server/src/bubbles/db/models.py` (append after the `UserReward` dataclass, end of file)

- [ ] **Step 1: Add the dataclasses**

`models.py` already does `from datetime import date, datetime` and `from typing import Any` and `from uuid import UUID` at the top — confirm those imports exist (they do). Append at the end of `server/src/bubbles/db/models.py`:

```python
@dataclass(frozen=True, slots=True)
class XpTransaction:
    id: UUID
    user_id: UUID
    amount: int
    source_type: str
    source_id: str | None
    description: str | None
    created_at: datetime


@dataclass(frozen=True, slots=True)
class Achievement:
    id: UUID
    code: str | None
    title: str
    description: str | None
    icon: str
    category: str
    criteria_type: str
    criteria_value: int
    xp_reward: int
    tier: str | None
    created_at: datetime


@dataclass(frozen=True, slots=True)
class UserAchievement:
    id: UUID
    user_id: UUID
    achievement_id: UUID
    awarded_at: datetime


@dataclass(frozen=True, slots=True)
class UserBadge:
    """View model: an earned achievement plus when it was awarded."""

    achievement: Achievement
    awarded_at: datetime
```

- [ ] **Step 2: Verify**

Run (from `server/`):
```bash
uv run python -c "from bubbles.db.models import XpTransaction, Achievement, UserAchievement, UserBadge; print('models ok')"
uv run ruff check . && uv run mypy
```
Expected: `models ok`; ruff clean; mypy `Success`.

- [ ] **Step 3: Commit**

```bash
git add server/src/bubbles/db/models.py
git commit -m "feat(db): add XpTransaction, Achievement, UserAchievement, UserBadge models"
```

---

### Task 3: Pure level-math helpers + unit test

**Files:**
- Create: `server/src/bubbles/core/gamification.py`
- Test: `server/tests/test_core_gamification.py`

- [ ] **Step 1: Write the failing test**

Create `server/tests/test_core_gamification.py`:

```python
"""Unit tests for the pure level-math helpers."""

from __future__ import annotations

import math

import pytest

from bubbles.core.gamification import (
    LevelProgress,
    level_for_xp,
    level_progress,
    xp_for_level,
)


def test_xp_for_level_formula() -> None:
    # cumulative_xp(level) = 50 * level * (level - 1)
    assert xp_for_level(1) == 0
    assert xp_for_level(2) == 100
    assert xp_for_level(3) == 300
    assert xp_for_level(5) == 1000


def test_level_for_xp_basics() -> None:
    assert level_for_xp(0) == 1
    assert level_for_xp(-50) == 1          # negative clamps to 1
    assert level_for_xp(99) == 1
    assert level_for_xp(100) == 2          # exact boundary
    assert level_for_xp(299) == 2
    assert level_for_xp(300) == 3


def test_level_progress_at_zero() -> None:
    lp = level_progress(0)
    assert isinstance(lp, LevelProgress)
    assert lp.level == 1
    assert lp.xp_into_level == 0
    assert lp.xp_to_next_level == 100      # xp_for_level(2) - 0
    assert lp.progress_pct == 0.0


def test_level_progress_at_boundary() -> None:
    lp = level_progress(100)               # exactly level 2
    assert lp.level == 2
    assert lp.xp_into_level == 0
    assert lp.xp_to_next_level == 200      # xp_for_level(3)=300 minus 100
    assert lp.progress_pct == 0.0


def test_level_progress_midway() -> None:
    lp = level_progress(200)               # level 2 (100..299), 100 into a 200-wide band
    assert lp.level == 2
    assert lp.xp_into_level == 100
    assert lp.xp_to_next_level == 100
    assert math.isclose(lp.progress_pct, 0.5)


@pytest.mark.parametrize("xp", [0, 1, 50, 99, 100, 250, 999, 1000, 5000, 123456])
def test_progress_pct_invariant(xp: int) -> None:
    lp = level_progress(xp)
    assert 0.0 <= lp.progress_pct < 1.0
    assert lp.level >= 1
    assert lp.xp_into_level >= 0
    assert lp.xp_to_next_level >= 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_core_gamification.py -q`
Expected: collection error / `ModuleNotFoundError: No module named 'bubbles.core.gamification'`.

- [ ] **Step 3: Write the implementation**

Create `server/src/bubbles/core/gamification.py`:

```python
"""Pure XP/level math — no I/O. Formula ported from server_v2.

cumulative_xp(level) = 50 * level * (level - 1)
level_for_xp(xp)     = floor((1 + sqrt(1 + 4 * xp / 50)) / 2), clamped to >= 1
"""

from __future__ import annotations

import math
from dataclasses import dataclass


def xp_for_level(level: int) -> int:
    """Cumulative XP required to *reach* ``level``."""
    return 50 * level * (level - 1)


def level_for_xp(total_xp: int) -> int:
    """Current level for a given total XP amount (>= 1)."""
    if total_xp <= 0:
        return 1
    level = int((1 + math.sqrt(1 + 4 * total_xp / 50)) / 2)
    return max(1, level)


@dataclass(frozen=True, slots=True)
class LevelProgress:
    level: int
    xp_into_level: int       # total_xp - xp_for_level(level)
    xp_to_next_level: int    # xp_for_level(level + 1) - total_xp
    progress_pct: float      # xp_into_level / band_width, always in [0.0, 1.0)


def level_progress(total_xp: int) -> LevelProgress:
    xp = max(0, total_xp)
    level = level_for_xp(xp)
    floor_xp = xp_for_level(level)
    next_xp = xp_for_level(level + 1)
    band = next_xp - floor_xp  # 100 * level, always > 0 for level >= 1
    into = xp - floor_xp
    return LevelProgress(
        level=level,
        xp_into_level=into,
        xp_to_next_level=next_xp - xp,
        progress_pct=into / band,
    )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_core_gamification.py -q`
Expected: all tests pass.

- [ ] **Step 5: Lint/type check + commit**

```bash
uv run ruff check . && uv run ruff format --check . && uv run mypy
git add server/src/bubbles/core/gamification.py server/tests/test_core_gamification.py
git commit -m "feat(core): pure XP/level math helpers"
```

---

### Task 4: `xp` repo + integration test

**Files:**
- Create: `server/src/bubbles/db/repo/xp.py`
- Test: `server/tests/integration/test_repo_xp.py`

- [ ] **Step 1: Write the failing integration test**

Create `server/tests/integration/test_repo_xp.py`:

```python
"""xp_transactions repo integration tests."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import xp as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def test_record_inserts_and_returns_row(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        tx = await repo.record(
            uow.conn, user_id=user_id, amount=30, source_type="session_complete", source_id="s1"
        )
    assert tx is not None
    assert tx.amount == 30
    assert tx.source_type == "session_complete"
    assert tx.source_id == "s1"


async def test_record_is_idempotent_on_source_id(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        first = await repo.record(
            uow.conn, user_id=user_id, amount=30, source_type="session_complete", source_id="s1"
        )
        second = await repo.record(
            uow.conn, user_id=user_id, amount=30, source_type="session_complete", source_id="s1"
        )
    assert first is not None
    assert second is None  # deduped


async def test_record_without_source_id_always_inserts(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        a = await repo.record(uow.conn, user_id=user_id, amount=10, source_type="manual")
        b = await repo.record(uow.conn, user_id=user_id, amount=10, source_type="manual")
        rows = await uow.conn.fetch(
            "SELECT id FROM xp_transactions WHERE user_id=$1", user_id
        )
    assert a is not None and b is not None
    assert len(rows) == 2


async def test_record_rejects_negative_amount(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        with pytest.raises(ValueError, match="non-negative"):
            await repo.record(uow.conn, user_id=user_id, amount=-5, source_type="manual")


async def test_recent_orders_newest_first(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        await repo.record(uow.conn, user_id=user_id, amount=10, source_type="a", source_id="1")
        await repo.record(uow.conn, user_id=user_id, amount=20, source_type="b", source_id="2")
        await repo.record(uow.conn, user_id=user_id, amount=30, source_type="c", source_id="3")
        rows = await repo.recent(uow.conn, user_id=user_id, limit=2)
    assert [r.amount for r in rows] == [30, 20]


async def test_sum_since_counts_positive_only_within_window(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    now = datetime.now(timezone.utc)
    async with UnitOfWork(pool) as uow:
        # one inside the window, one negative inside, one positive but old
        await uow.conn.execute(
            "INSERT INTO xp_transactions (user_id, amount, source_type, created_at)"
            " VALUES ($1, 50, 'in', $2)",
            user_id, now - timedelta(hours=1),
        )
        await uow.conn.execute(
            "INSERT INTO xp_transactions (user_id, amount, source_type, created_at)"
            " VALUES ($1, -20, 'spend', $2)",
            user_id, now - timedelta(hours=1),
        )
        await uow.conn.execute(
            "INSERT INTO xp_transactions (user_id, amount, source_type, created_at)"
            " VALUES ($1, 999, 'old', $2)",
            user_id, now - timedelta(days=10),
        )
        total = await repo.sum_since(uow.conn, user_id=user_id, since=now - timedelta(days=1))
    assert total == 50
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/integration/test_repo_xp.py -q`
Expected: module collected then skipped locally (`integration tests disabled`) — that's fine, it would `ModuleNotFoundError` first if the import is bad, so a clean skip means the test file itself imports. In CI (`RUN_INTEGRATION=1`) it would fail with `ModuleNotFoundError: bubbles.db.repo.xp`. (Locally: a SKIPPED line is the expected pass-through for this step.)

- [ ] **Step 3: Write the implementation**

Create `server/src/bubbles/db/repo/xp.py`:

```python
"""xp_transactions repo: append-only XP ledger with source dedup."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

import asyncpg

from bubbles.db.models import XpTransaction

_COLS = "id, user_id, amount, source_type, source_id, description, created_at"


def _row(row: asyncpg.Record) -> XpTransaction:
    return XpTransaction(
        id=row["id"],
        user_id=row["user_id"],
        amount=row["amount"],
        source_type=row["source_type"],
        source_id=row["source_id"],
        description=row["description"],
        created_at=row["created_at"],
    )


async def record(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    amount: int,
    source_type: str,
    source_id: str | None = None,
    description: str | None = None,
) -> XpTransaction | None:
    """Append an XP-award row.

    Returns ``None`` when a row with the same ``(user_id, source_type, source_id)``
    already exists (idempotent re-award). The dedup unique index only covers
    rows where ``source_id IS NOT NULL``, so a ``None`` ``source_id`` always
    inserts. ``amount`` must be non-negative — XP *spend* is tracked separately
    via ``user_gamification.xp_spent``.
    """
    if amount < 0:
        raise ValueError("amount must be non-negative")
    row = await conn.fetchrow(
        f"""
        INSERT INTO xp_transactions (user_id, amount, source_type, source_id, description)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (user_id, source_type, source_id) DO NOTHING
        RETURNING {_COLS}
        """,
        user_id,
        amount,
        source_type,
        source_id,
        description,
    )
    return _row(row) if row is not None else None


async def recent(
    conn: asyncpg.Connection, *, user_id: UUID, limit: int = 20
) -> list[XpTransaction]:
    rows = await conn.fetch(
        f"SELECT {_COLS} FROM xp_transactions WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2",
        user_id,
        limit,
    )
    return [_row(r) for r in rows]


async def sum_since(conn: asyncpg.Connection, *, user_id: UUID, since: datetime) -> int:
    val: int | None = await conn.fetchval(
        """
        SELECT COALESCE(SUM(amount), 0)::int
        FROM xp_transactions
        WHERE user_id = $1 AND amount > 0 AND created_at >= $2
        """,
        user_id,
        since,
    )
    return val or 0
```

- [ ] **Step 4: Verify it imports + gate**

Run (from `server/`):
```bash
uv run python -c "from bubbles.db.repo import xp; print('xp repo ok')"
uv run pytest tests/integration/test_repo_xp.py -q   # SKIPPED locally — expected
uv run ruff check . && uv run ruff format --check . && uv run mypy
```
Expected: `xp repo ok`; the integration test SKIPS locally; ruff clean; mypy `Success`.

- [ ] **Step 5: Commit**

```bash
git add server/src/bubbles/db/repo/xp.py server/tests/integration/test_repo_xp.py
git commit -m "feat(db): xp_transactions repo (record/recent/sum_since)"
```

---

### Task 5: `achievements` repo + integration test

**Files:**
- Create: `server/src/bubbles/db/repo/achievements.py`
- Test: `server/tests/integration/test_repo_achievements.py`

- [ ] **Step 1: Write the failing integration test**

Create `server/tests/integration/test_repo_achievements.py`:

```python
"""achievements / user_achievements repo integration tests."""

from __future__ import annotations

from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import achievements as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def test_list_for_user_empty(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        badges = await repo.list_for_user(uow.conn, user_id=user_id)
    assert badges == []


async def test_list_for_user_returns_earned_badges_newest_first(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    async with UnitOfWork(pool) as uow:
        a1 = await uow.conn.fetchrow(
            "INSERT INTO achievements (code, title, criteria_type, criteria_value)"
            " VALUES ('streak_3', 'On a roll', 'streak_days', 3) RETURNING id"
        )
        a2 = await uow.conn.fetchrow(
            "INSERT INTO achievements (code, title, criteria_type, criteria_value)"
            " VALUES ('xp_1000', 'Grinder', 'total_xp', 1000) RETURNING id"
        )
        await uow.conn.execute(
            "INSERT INTO user_achievements (user_id, achievement_id, awarded_at)"
            " VALUES ($1, $2, now() - interval '2 days')",
            user_id, a1["id"],
        )
        await uow.conn.execute(
            "INSERT INTO user_achievements (user_id, achievement_id, awarded_at)"
            " VALUES ($1, $2, now())",
            user_id, a2["id"],
        )
        badges = await repo.list_for_user(uow.conn, user_id=user_id)
    assert [b.achievement.code for b in badges] == ["xp_1000", "streak_3"]
    assert badges[0].achievement.title == "Grinder"
    assert badges[0].awarded_at >= badges[1].awarded_at
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/integration/test_repo_achievements.py -q`
Expected: SKIPPED locally (file imports fine → clean skip); in CI it fails with `ModuleNotFoundError: bubbles.db.repo.achievements`.

- [ ] **Step 3: Write the implementation**

Create `server/src/bubbles/db/repo/achievements.py`:

```python
"""achievements / user_achievements repo (read-only for now)."""

from __future__ import annotations

from uuid import UUID

import asyncpg

from bubbles.db.models import Achievement, UserBadge

_A_COLS = """
    a.id, a.code, a.title, a.description, a.icon, a.category,
    a.criteria_type, a.criteria_value, a.xp_reward, a.tier, a.created_at
"""


def _achievement(row: asyncpg.Record) -> Achievement:
    return Achievement(
        id=row["id"],
        code=row["code"],
        title=row["title"],
        description=row["description"],
        icon=row["icon"] or "🏆",
        category=row["category"] or "general",
        criteria_type=row["criteria_type"],
        criteria_value=row["criteria_value"],
        xp_reward=row["xp_reward"] or 0,
        tier=row["tier"],
        created_at=row["created_at"],
    )


async def list_for_user(conn: asyncpg.Connection, *, user_id: UUID) -> list[UserBadge]:
    rows = await conn.fetch(
        f"""
        SELECT {_A_COLS}, ua.awarded_at
        FROM user_achievements ua
        JOIN achievements a ON a.id = ua.achievement_id
        WHERE ua.user_id = $1
        ORDER BY ua.awarded_at DESC
        """,
        user_id,
    )
    return [UserBadge(achievement=_achievement(r), awarded_at=r["awarded_at"]) for r in rows]
```

- [ ] **Step 4: Verify + gate**

Run (from `server/`):
```bash
uv run python -c "from bubbles.db.repo import achievements; print('achievements repo ok')"
uv run pytest tests/integration/test_repo_achievements.py -q   # SKIPPED locally
uv run ruff check . && uv run ruff format --check . && uv run mypy
```
Expected: `achievements repo ok`; SKIP locally; ruff clean; mypy `Success`.

- [ ] **Step 5: Commit**

```bash
git add server/src/bubbles/db/repo/achievements.py server/tests/integration/test_repo_achievements.py
git commit -m "feat(db): achievements repo (list_for_user)"
```

---

### Task 6: extend the `gamification` repo + extend its integration test

**Files:**
- Modify: `server/src/bubbles/db/repo/gamification.py`
- Modify: `server/tests/integration/test_repo_gamification.py` (add tests)

- [ ] **Step 1: Add the failing tests**

Append to `server/tests/integration/test_repo_gamification.py` (and update its imports — the file currently has `from datetime import date`; change to `from datetime import date, datetime, timedelta, timezone`):

```python
async def test_add_xp_with_source_id_is_idempotent(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        first = await repo.add_xp(
            uow.conn, user_id=user_id, amount=30, source_type="session_complete", source_id="sx"
        )
        again = await repo.add_xp(
            uow.conn, user_id=user_id, amount=30, source_type="session_complete", source_id="sx"
        )
        ledger = await uow.conn.fetch("SELECT amount FROM xp_transactions WHERE user_id=$1", user_id)
    assert first.total_xp == 30
    assert again.total_xp == 30          # no second bump
    assert len(ledger) == 1              # no second ledger row


async def test_get_or_assign_daily_quests_assigns_then_is_stable(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    async with UnitOfWork(pool) as uow:
        for i in range(5):
            await uow.conn.execute(
                "INSERT INTO quest_definitions (title, action_type, target, xp_reward)"
                " VALUES ($1, 'session_count', 1, 10)",
                f"q{i}",
            )
        await repo.get_or_init_gamification(uow.conn, user_id)
        today = date.today()
        first = await repo.get_or_assign_daily_quests(uow.conn, user_id=user_id, on_date=today)
        second = await repo.get_or_assign_daily_quests(uow.conn, user_id=user_id, on_date=today)
        later = await repo.get_or_assign_daily_quests(
            uow.conn, user_id=user_id, on_date=today + timedelta(days=1)
        )
    assert len(first) == 3
    assert {q.id for q in first} == {q.id for q in second}        # same rows
    assert {q.id for q in first}.isdisjoint({q.id for q in later})  # fresh assignment


async def test_get_or_assign_daily_quests_no_defs_returns_empty(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    async with UnitOfWork(pool) as uow:
        await repo.get_or_init_gamification(uow.conn, user_id)
        out = await repo.get_or_assign_daily_quests(uow.conn, user_id=user_id, on_date=date.today())
    assert out == []


async def test_owned_reward_ids(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        await repo.add_xp(uow.conn, user_id=user_id, amount=500)
        r = await uow.conn.fetchrow(
            "INSERT INTO rewards (title, cost_xp) VALUES ('badge', 100) RETURNING id"
        )
        await repo.redeem_reward(uow.conn, user_id=user_id, reward_id=r["id"])
        owned = await repo.owned_reward_ids(uow.conn, user_id=user_id)
    assert owned == {r["id"]}


async def test_leaderboard_and_ranks(pool: asyncpg.Pool, user_id: UUID) -> None:
    other = UUID(int=user_id.int ^ 1)  # deterministic distinct uuid
    async with UnitOfWork(pool) as uow:
        await uow.conn.execute("INSERT INTO auth.users (id) VALUES ($1)", other)
        # caller: 100 total, opted in; other: 300 total, opted in
        await repo.add_xp(uow.conn, user_id=user_id, amount=100)
        await repo.add_xp(uow.conn, user_id=other, amount=300)
        top = await repo.leaderboard_top(uow.conn, limit=10)
        my_all_rank = await repo.rank_all_time(uow.conn, user_id=user_id)
        # period: only the caller has a *recent* positive tx within 1 day (both add_xp wrote now())
        now = datetime.now(timezone.utc)
        per = await repo.leaderboard_period(uow.conn, since=now - timedelta(days=1), limit=10)
        my_per_rank = await repo.rank_period(uow.conn, user_id=user_id, since=now - timedelta(days=1))
    assert [r["user_id"] for r in top][:2] == [other, user_id]   # 300 before 100
    assert my_all_rank == 2
    assert {r["user_id"] for r in per} == {user_id, other}
    assert my_per_rank == 2
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/integration/test_repo_gamification.py -q`
Expected: SKIPPED locally (still imports OK). In CI: fails — `repo.add_xp()` got an unexpected keyword `source_type`, `AttributeError: ... 'get_or_assign_daily_quests'`, etc.

- [ ] **Step 3: Implement the repo changes**

Edit `server/src/bubbles/db/repo/gamification.py`:

(a) Add to the imports block (it currently imports from `bubbles.db.models`):
```python
from bubbles.db.repo import xp as xp_repo
```
(Place this import after the `from bubbles.db.models import (...)` block. No cycle: `xp.py` only imports `bubbles.db.models`.)

(b) Replace the existing `add_xp` function with:
```python
async def add_xp(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    amount: int,
    source_type: str = "manual",
    source_id: str | None = None,
    description: str | None = None,
) -> UserGamification:
    """Award XP. Writes an ``xp_transactions`` ledger row first; if that row was
    deduped (same ``source_id`` already awarded) the ``user_gamification`` total
    is left unchanged — making repeated awards with the same ``source_id`` a no-op.
    """
    if amount < 0:
        raise ValueError("amount must be non-negative")
    ledger_row = await xp_repo.record(
        conn,
        user_id=user_id,
        amount=amount,
        source_type=source_type,
        source_id=source_id,
        description=description,
    )
    if ledger_row is None:
        # Already awarded for this source_id — do not double-count.
        return await get_or_init_gamification(conn, user_id)
    row = await conn.fetchrow(
        f"""
        INSERT INTO user_gamification (user_id, total_xp, last_active_date, updated_at)
        VALUES ($1, $2, CURRENT_DATE, NOW())
        ON CONFLICT (user_id) DO UPDATE SET
            total_xp = user_gamification.total_xp + EXCLUDED.total_xp,
            last_active_date = CURRENT_DATE,
            updated_at = NOW()
        RETURNING {_GAMIF_COLS}
        """,
        user_id,
        amount,
    )
    assert row is not None
    return _gamif(row)
```

(c) Add a `date`/`datetime` import check at the top: the file already does `from datetime import date`. Add `datetime` too — change to `from datetime import date, datetime`.

(d) Append these new functions at the end of the file:
```python
async def owned_reward_ids(conn: asyncpg.Connection, *, user_id: UUID) -> set[UUID]:
    rows = await conn.fetch("SELECT reward_id FROM user_rewards WHERE user_id = $1", user_id)
    return {r["reward_id"] for r in rows}


async def get_or_assign_daily_quests(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    on_date: date,
    n: int = 3,
) -> list[UserQuest]:
    """Return the user's quests assigned for ``on_date``; if none are assigned
    yet, pick up to ``n`` random active definitions, assign each, and return
    them. Runs inside the caller's transaction (no commit here). Returns ``[]``
    if there are no active quest definitions.
    """
    existing = await list_user_quests(conn, user_id=user_id, on_date=on_date)
    if existing:
        return existing
    defs = await conn.fetch(
        f"SELECT {_QUEST_DEF_COLS} FROM quest_definitions WHERE is_active = true "
        "ORDER BY random() LIMIT $1",
        n,
    )
    assigned: list[UserQuest] = []
    for d in defs:
        qd = _quest_def(d)
        assigned.append(
            await assign_quest(
                conn,
                user_id=user_id,
                quest_id=qd.id,
                target=qd.target,
                assigned_date=on_date,
            )
        )
    return assigned


async def leaderboard_period(
    conn: asyncpg.Connection, *, since: datetime, limit: int = 25
) -> list[asyncpg.Record]:
    """Top opted-in users by XP earned since ``since`` (positive ledger rows)."""
    rows = await conn.fetch(
        """
        SELECT t.user_id, COALESCE(SUM(t.amount), 0)::int AS xp, g.level, g.current_streak
        FROM xp_transactions t
        JOIN user_gamification g ON g.user_id = t.user_id AND g.leaderboard_opt_in = true
        WHERE t.amount > 0 AND t.created_at >= $1
        GROUP BY t.user_id, g.level, g.current_streak
        ORDER BY xp DESC
        LIMIT $2
        """,
        since,
        limit,
    )
    return list(rows)


async def rank_all_time(conn: asyncpg.Connection, *, user_id: UUID) -> int | None:
    """1-based rank of ``user_id`` among opted-in users by ``total_xp``; ``None``
    if the user is not opted in."""
    val: int | None = await conn.fetchval(
        """
        SELECT rnk FROM (
            SELECT user_id, RANK() OVER (ORDER BY total_xp DESC) AS rnk
            FROM user_gamification WHERE leaderboard_opt_in = true
        ) s WHERE s.user_id = $1
        """,
        user_id,
    )
    return val


async def rank_period(
    conn: asyncpg.Connection, *, user_id: UUID, since: datetime
) -> int | None:
    """1-based rank of ``user_id`` among opted-in users by XP since ``since``;
    ``None`` if the user has no positive ledger rows in the window or isn't opted in."""
    val: int | None = await conn.fetchval(
        """
        SELECT rnk FROM (
            SELECT t.user_id, RANK() OVER (ORDER BY COALESCE(SUM(t.amount), 0) DESC) AS rnk
            FROM xp_transactions t
            JOIN user_gamification g ON g.user_id = t.user_id AND g.leaderboard_opt_in = true
            WHERE t.amount > 0 AND t.created_at >= $2
            GROUP BY t.user_id
        ) s WHERE s.user_id = $1
        """,
        user_id,
        since,
    )
    return val
```

- [ ] **Step 4: Run the gate**

Run (from `server/`):
```bash
uv run python -c "from bubbles.db.repo import gamification; print(hasattr(gamification, 'get_or_assign_daily_quests'))"
uv run pytest tests/integration/test_repo_gamification.py -q   # SKIPPED locally
uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest -q
```
Expected: prints `True`; integration suite SKIPs locally; ruff clean; mypy `Success`; full unit `pytest` green (the earlier `test_init_and_add_xp` etc. still pass — `add_xp` keeps its old call shape via defaults).

- [ ] **Step 5: Commit**

```bash
git add server/src/bubbles/db/repo/gamification.py server/tests/integration/test_repo_gamification.py
git commit -m "feat(db): gamification repo — ledger-aware add_xp, daily-quest assignment, leaderboard period/ranks"
```

---

### Task 7: wire-format schemas

**Files:**
- Modify: `server/src/bubbles/api/v1/_schemas.py`

- [ ] **Step 1: Add the schemas**

In `server/src/bubbles/api/v1/_schemas.py`: change the datetime import line `from datetime import datetime` to `from datetime import date, datetime`. Then append a new section at the end of the file:

```python
# --- gamification ----------------------------------------------------------


class AchievementOut(_Base):
    id: UUID
    code: str | None
    title: str
    description: str | None
    icon: str
    category: str
    tier: str | None
    awarded_at: datetime


class XpEntryOut(_Base):
    amount: int
    source_type: str
    description: str | None
    created_at: datetime


class GamificationProfile(_Base):
    user_id: UUID
    xp: int
    level: int
    xp_into_level: int
    xp_to_next_level: int
    xp_progress_pct: float
    current_streak: int
    longest_streak: int
    streak_freezes: int
    last_active_date: date | None
    badges: list[AchievementOut]
    recent_xp: list[XpEntryOut]


class UserQuestOut(_Base):
    id: UUID
    quest_id: UUID
    progress: int
    target: int
    is_completed: bool
    assigned_date: date
    completed_at: datetime | None


class DailyQuestsResponse(_Base):
    quests: list[UserQuestOut]
    daily_reset_at: datetime
    total_completed_today: int
    total_quests_today: int


class RewardOut(_Base):
    id: UUID
    title: str
    description: str | None
    icon: str
    category: str
    cost_xp: int
    sort_order: int
    affordable: bool
    owned: bool


class RewardCatalogResponse(_Base):
    balance_xp: int
    rewards: list[RewardOut]


class RewardRedeemRequest(_Base):
    reward_id: UUID


class RewardRedeemResponse(_Base):
    reward_id: UUID
    cost_xp: int
    unlocked_at: datetime
    balance_xp: int


class LeaderboardEntry(_Base):
    user_id: UUID
    xp: int
    level: int
    current_streak: int
    rank: int


class LeaderboardMe(_Base):
    rank: int | None
    xp: int


class LeaderboardResponse(_Base):
    period: Literal["all", "daily", "weekly", "monthly"]
    entries: list[LeaderboardEntry]
    me: LeaderboardMe


class OptInRequest(_Base):
    opt_in: bool


class OptInResponse(_Base):
    user_id: UUID
    leaderboard_opt_in: bool
```

- [ ] **Step 2: Verify**

Run (from `server/`):
```bash
uv run python -c "from bubbles.api.v1._schemas import GamificationProfile, DailyQuestsResponse, RewardCatalogResponse, RewardRedeemRequest, RewardRedeemResponse, LeaderboardResponse, OptInRequest, OptInResponse; print('schemas ok')"
uv run ruff check . && uv run ruff format --check . && uv run mypy
```
Expected: `schemas ok`; ruff clean; mypy `Success`.

- [ ] **Step 3: Commit**

```bash
git add server/src/bubbles/api/v1/_schemas.py
git commit -m "feat(api): gamification wire schemas"
```

---

### Task 8: route module + register + `GET /v1/gamification/{user_id}` + `GET /v1/quests/{user_id}` + tests

**Files:**
- Create: `server/src/bubbles/api/v1/gamification.py`
- Modify: `server/src/bubbles/api/router.py`
- Test: `server/tests/integration/test_routes_gamification.py`

- [ ] **Step 1: Write the failing integration test (profile + quests)**

Create `server/tests/integration/test_routes_gamification.py`:

```python
"""Gamification HTTP route integration tests."""

from __future__ import annotations

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
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )


async def _new_user(pool: asyncpg.Pool) -> UUID:
    uid = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", uid)
    return uid


async def test_get_profile_fresh_user(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/gamification/{user_id}")
    assert r.status_code == 200
    body = r.json()
    assert body["user_id"] == str(user_id)
    assert body["xp"] == 0
    assert body["level"] == 1
    assert body["xp_progress_pct"] == 0.0
    assert body["badges"] == []
    assert body["recent_xp"] == []


async def test_get_profile_reflects_xp_and_badge(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    from bubbles.db.repo import gamification as grepo
    from bubbles.db.uow import UnitOfWork

    async with UnitOfWork(pool) as uow:
        await grepo.add_xp(uow.conn, user_id=user_id, amount=150, source_type="m", source_id="x")
        a = await uow.conn.fetchrow(
            "INSERT INTO achievements (code, title, criteria_type, criteria_value)"
            " VALUES ('xp_100', 'Centurion', 'total_xp', 100) RETURNING id"
        )
        await uow.conn.execute(
            "INSERT INTO user_achievements (user_id, achievement_id) VALUES ($1, $2)",
            user_id, a["id"],
        )
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/gamification/{user_id}")
    body = r.json()
    assert body["xp"] == 150
    assert body["level"] == 2          # xp_for_level(2) == 100
    assert len(body["badges"]) == 1
    assert body["badges"][0]["code"] == "xp_100"
    assert len(body["recent_xp"]) == 1
    assert body["recent_xp"][0]["amount"] == 150


async def test_get_profile_other_user_403(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    other = await _new_user(pool)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/gamification/{other}")
    assert r.status_code == 403


async def _seed_quest_defs(pool: asyncpg.Pool, n: int = 4) -> None:
    async with pool.acquire() as con:
        for i in range(n):
            await con.execute(
                "INSERT INTO quest_definitions (title, action_type, target, xp_reward)"
                " VALUES ($1, 'session_count', 1, 10)",
                f"q{i}",
            )


async def test_get_quests_assigns_then_stable(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    await _seed_quest_defs(pool, 4)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r1 = await ac.get(f"/v1/quests/{user_id}")
        r2 = await ac.get(f"/v1/quests/{user_id}")
    assert r1.status_code == 200
    b1, b2 = r1.json(), r2.json()
    assert b1["total_quests_today"] == 3
    assert len(b1["quests"]) == 3
    assert {q["id"] for q in b1["quests"]} == {q["id"] for q in b2["quests"]}
    assert b1["daily_reset_at"].endswith("+00:00") or b1["daily_reset_at"].endswith("Z")
    assert b1["total_completed_today"] == 0


async def test_get_quests_other_user_403(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    other = await _new_user(pool)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/quests/{other}")
    assert r.status_code == 403
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/integration/test_routes_gamification.py -q`
Expected: SKIPPED locally (file imports cleanly). In CI: 404s on `/v1/gamification/{id}` — route not registered yet.

- [ ] **Step 3: Create the route module with the first two endpoints**

Create `server/src/bubbles/api/v1/gamification.py`:

```python
"""Gamification HTTP routes — XP profile, daily quests, rewards, leaderboard.

All ``{user_id}``-path routes verify the path id matches the authenticated
user via ``require_ownership`` (no peeking at other users' data). No upstream
(LLM/Redis) calls here, so no ``UpstreamUnavailable`` paths.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Query

from bubbles.api.v1._schemas import (
    AchievementOut,
    DailyQuestsResponse,
    GamificationProfile,
    LeaderboardEntry,
    LeaderboardMe,
    LeaderboardResponse,
    OptInRequest,
    OptInResponse,
    RewardCatalogResponse,
    RewardOut,
    RewardRedeemRequest,
    RewardRedeemResponse,
    UserQuestOut,
    XpEntryOut,
)
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import BadRequest
from bubbles.core.gamification import level_progress
from bubbles.db.repo import achievements as achievements_repo
from bubbles.db.repo import gamification as gamification_repo
from bubbles.db.repo import xp as xp_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep

router = APIRouter(tags=["gamification"])

_Period = Literal["all", "daily", "weekly", "monthly"]


@router.get("/gamification/{user_id}", response_model=GamificationProfile)
async def get_gamification(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> GamificationProfile:
    require_ownership(user, str(user_id))
    async with transaction(pool) as conn:
        g = await gamification_repo.get_or_init_gamification(conn, user_id)
        badges = await achievements_repo.list_for_user(conn, user_id=user_id)
        recent = await xp_repo.recent(conn, user_id=user_id, limit=20)
    lp = level_progress(g.total_xp)
    return GamificationProfile(
        user_id=user_id,
        xp=g.total_xp,
        level=lp.level,
        xp_into_level=lp.xp_into_level,
        xp_to_next_level=lp.xp_to_next_level,
        xp_progress_pct=lp.progress_pct,
        current_streak=g.current_streak,
        longest_streak=g.longest_streak,
        streak_freezes=g.streak_freezes,
        last_active_date=g.last_active_date,
        badges=[
            AchievementOut(
                id=b.achievement.id,
                code=b.achievement.code,
                title=b.achievement.title,
                description=b.achievement.description,
                icon=b.achievement.icon,
                category=b.achievement.category,
                tier=b.achievement.tier,
                awarded_at=b.awarded_at,
            )
            for b in badges
        ],
        recent_xp=[
            XpEntryOut(
                amount=t.amount,
                source_type=t.source_type,
                description=t.description,
                created_at=t.created_at,
            )
            for t in recent
        ],
    )


@router.get("/quests/{user_id}", response_model=DailyQuestsResponse)
async def get_quests(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> DailyQuestsResponse:
    require_ownership(user, str(user_id))
    today = datetime.now(timezone.utc).date()
    async with transaction(pool) as conn:
        await gamification_repo.get_or_init_gamification(conn, user_id)
        quests = await gamification_repo.get_or_assign_daily_quests(
            conn, user_id=user_id, on_date=today
        )
    reset_at = datetime(today.year, today.month, today.day, tzinfo=timezone.utc) + timedelta(days=1)
    completed = sum(1 for q in quests if q.is_completed)
    return DailyQuestsResponse(
        quests=[
            UserQuestOut(
                id=q.id,
                quest_id=q.quest_id,
                progress=q.progress,
                target=q.target,
                is_completed=q.is_completed,
                assigned_date=q.assigned_date,
                completed_at=q.completed_at,
            )
            for q in quests
        ],
        daily_reset_at=reset_at,
        total_completed_today=completed,
        total_quests_today=len(quests),
    )
```

(The unused imports — `Query`, `BadRequest`, `UnitOfWork`, the reward/leaderboard schemas, `_Period` — are added now and consumed in Tasks 9 & 10. If `ruff` flags them as unused at this step, that's expected; the next task removes the gap. To keep this task's gate green, you may instead add only the imports you use now and extend them in Tasks 9–10 — implementer's choice, but the *final* import block must match Task 10's.)

- [ ] **Step 4: Register the router**

In `server/src/bubbles/api/router.py`: add `from bubbles.api.v1.gamification import router as gamification_router` to the import block (alphabetical: after `entities` import, before `grammar`), and add `v1_router.include_router(gamification_router)` (after the `entities_router` line).

- [ ] **Step 5: Run the gate**

Run (from `server/`):
```bash
uv run python -c "from bubbles.app import create_app; app = create_app(); print(sorted({r.path for r in app.routes if '/v1/gamification' in r.path or '/v1/quests' in r.path}))"
uv run pytest tests/integration/test_routes_gamification.py -q   # SKIPPED locally
uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest -q
```
Expected: prints the two paths `['/v1/gamification/{user_id}', '/v1/quests/{user_id}']`; integration SKIPs locally; ruff clean (no unused-import errors — see the note in Step 3); mypy `Success`; unit pytest green.

- [ ] **Step 6: Commit**

```bash
git add server/src/bubbles/api/v1/gamification.py server/src/bubbles/api/router.py server/tests/integration/test_routes_gamification.py
git commit -m "feat(api): GET /v1/gamification/{user_id} + GET /v1/quests/{user_id}"
```

---

### Task 9: `GET /v1/rewards/{user_id}` + `POST /v1/rewards/{user_id}/redeem` + tests

**Files:**
- Modify: `server/src/bubbles/api/v1/gamification.py` (add two handlers)
- Modify: `server/tests/integration/test_routes_gamification.py` (add tests)

- [ ] **Step 1: Add the failing tests**

Append to `server/tests/integration/test_routes_gamification.py`:

```python
async def _seed_rewards(pool: asyncpg.Pool) -> tuple[UUID, UUID]:
    async with pool.acquire() as con:
        cheap = await con.fetchrow(
            "INSERT INTO rewards (title, cost_xp, sort_order) VALUES ('sticker', 50, 1) RETURNING id"
        )
        dear = await con.fetchrow(
            "INSERT INTO rewards (title, cost_xp, sort_order) VALUES ('trophy', 5000, 2) RETURNING id"
        )
    return cheap["id"], dear["id"]


async def test_rewards_catalog_shows_affordability_and_ownership(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    from bubbles.db.repo import gamification as grepo
    from bubbles.db.uow import UnitOfWork

    cheap_id, dear_id = await _seed_rewards(pool)
    async with UnitOfWork(pool) as uow:
        await grepo.add_xp(uow.conn, user_id=user_id, amount=200)
        await grepo.redeem_reward(uow.conn, user_id=user_id, reward_id=cheap_id)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get(f"/v1/rewards/{user_id}")
    assert r.status_code == 200
    body = r.json()
    assert body["balance_xp"] == 150          # 200 earned - 50 spent
    by_id = {x["id"]: x for x in body["rewards"]}
    assert by_id[str(cheap_id)]["owned"] is True
    assert by_id[str(cheap_id)]["affordable"] is True   # 150 >= 50
    assert by_id[str(dear_id)]["owned"] is False
    assert by_id[str(dear_id)]["affordable"] is False   # 150 < 5000


async def test_redeem_happy_path(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    from bubbles.db.repo import gamification as grepo
    from bubbles.db.uow import UnitOfWork

    cheap_id, _ = await _seed_rewards(pool)
    async with UnitOfWork(pool) as uow:
        await grepo.add_xp(uow.conn, user_id=user_id, amount=200)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(f"/v1/rewards/{user_id}/redeem", json={"reward_id": str(cheap_id)})
    assert r.status_code == 200
    body = r.json()
    assert body["reward_id"] == str(cheap_id)
    assert body["cost_xp"] == 50
    assert body["balance_xp"] == 150


async def test_redeem_insufficient_xp_400(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _, dear_id = await _seed_rewards(pool)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(f"/v1/rewards/{user_id}/redeem", json={"reward_id": str(dear_id)})
    assert r.status_code == 400
    assert "insufficient" in r.json()["error"]["message"].lower()


async def test_redeem_unknown_reward_400(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(f"/v1/rewards/{user_id}/redeem", json={"reward_id": str(uuid4())})
    assert r.status_code == 400


async def test_rewards_other_user_403(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    other = await _new_user(pool)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r1 = await ac.get(f"/v1/rewards/{other}")
        r2 = await ac.post(f"/v1/rewards/{other}/redeem", json={"reward_id": str(uuid4())})
    assert r1.status_code == 403
    assert r2.status_code == 403
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/integration/test_routes_gamification.py -q`
Expected: SKIPPED locally. In CI: 404 on `/v1/rewards/...`.

- [ ] **Step 3: Add the two handlers**

Append to `server/src/bubbles/api/v1/gamification.py` (after `get_quests`):

```python
@router.get("/rewards/{user_id}", response_model=RewardCatalogResponse)
async def list_rewards(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> RewardCatalogResponse:
    require_ownership(user, str(user_id))
    async with transaction(pool) as conn:
        g = await gamification_repo.get_or_init_gamification(conn, user_id)
        rewards = await gamification_repo.list_active_rewards(conn)
        owned = await gamification_repo.owned_reward_ids(conn, user_id=user_id)
    balance = g.total_xp - g.xp_spent
    return RewardCatalogResponse(
        balance_xp=balance,
        rewards=[
            RewardOut(
                id=r.id,
                title=r.title,
                description=r.description,
                icon=r.icon,
                category=r.category,
                cost_xp=r.cost_xp,
                sort_order=r.sort_order,
                affordable=balance >= r.cost_xp,
                owned=r.id in owned,
            )
            for r in rewards
        ],
    )


@router.post("/rewards/{user_id}/redeem", response_model=RewardRedeemResponse)
async def redeem_reward(
    user_id: UUID,
    body: RewardRedeemRequest,
    user: CurrentUserDep,
    pool: PoolDep,
) -> RewardRedeemResponse:
    require_ownership(user, str(user_id))
    async with UnitOfWork(pool) as uow:
        try:
            ur = await gamification_repo.redeem_reward(
                uow.conn, user_id=user_id, reward_id=body.reward_id
            )
        except ValueError as e:
            raise BadRequest(str(e)) from e
        g = await gamification_repo.get_or_init_gamification(uow.conn, user_id)
    return RewardRedeemResponse(
        reward_id=ur.reward_id,
        cost_xp=ur.cost_xp,
        unlocked_at=ur.unlocked_at,
        balance_xp=g.total_xp - g.xp_spent,
    )
```

- [ ] **Step 4: Run the gate**

Run (from `server/`):
```bash
uv run python -c "from bubbles.app import create_app; app = create_app(); print(sorted(r.path for r in app.routes if '/v1/rewards' in r.path))"
uv run pytest tests/integration/test_routes_gamification.py -q   # SKIPPED locally
uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest -q
```
Expected: prints `['/v1/rewards/{user_id}', '/v1/rewards/{user_id}/redeem']`; SKIP locally; ruff clean; mypy `Success`; unit pytest green.

- [ ] **Step 5: Commit**

```bash
git add server/src/bubbles/api/v1/gamification.py server/tests/integration/test_routes_gamification.py
git commit -m "feat(api): GET /v1/rewards/{user_id} + POST /v1/rewards/{user_id}/redeem"
```

---

### Task 10: `GET /v1/leaderboard` + `POST /v1/leaderboard/{user_id}/opt_in` + tests

**Files:**
- Modify: `server/src/bubbles/api/v1/gamification.py` (add two handlers; finalize the import block)
- Modify: `server/tests/integration/test_routes_gamification.py` (add tests)

- [ ] **Step 1: Add the failing tests**

Append to `server/tests/integration/test_routes_gamification.py`:

```python
async def test_leaderboard_all_period(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    from bubbles.db.repo import gamification as grepo
    from bubbles.db.uow import UnitOfWork

    other = await _new_user(pool)
    async with UnitOfWork(pool) as uow:
        await grepo.add_xp(uow.conn, user_id=user_id, amount=100)
        await grepo.add_xp(uow.conn, user_id=other, amount=300)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/leaderboard", params={"period": "all", "limit": 10})
    assert r.status_code == 200
    body = r.json()
    assert body["period"] == "all"
    assert [e["user_id"] for e in body["entries"]][:2] == [str(other), str(user_id)]
    assert [e["rank"] for e in body["entries"]][:2] == [1, 2]
    assert body["me"]["rank"] == 2
    assert body["me"]["xp"] == 100


async def test_leaderboard_weekly_period_window(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    # one positive tx now (counts), one positive tx 10 days ago (doesn't)
    async with pool.acquire() as con:
        await con.execute(
            "INSERT INTO user_gamification (user_id, leaderboard_opt_in) VALUES ($1, true)"
            " ON CONFLICT (user_id) DO UPDATE SET leaderboard_opt_in = true",
            user_id,
        )
        await con.execute(
            "INSERT INTO xp_transactions (user_id, amount, source_type) VALUES ($1, 40, 'recent')",
            user_id,
        )
        await con.execute(
            "INSERT INTO xp_transactions (user_id, amount, source_type, created_at)"
            " VALUES ($1, 999, 'old', now() - interval '10 days')",
            user_id,
        )
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/leaderboard", params={"period": "weekly"})
    body = r.json()
    assert body["period"] == "weekly"
    me_entry = [e for e in body["entries"] if e["user_id"] == str(user_id)]
    assert me_entry and me_entry[0]["xp"] == 40
    assert body["me"]["xp"] == 40


async def test_leaderboard_bad_period_422(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.get("/v1/leaderboard", params={"period": "yearly"})
    assert r.status_code == 422


async def test_opt_in_toggle(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        off = await ac.post(f"/v1/leaderboard/{user_id}/opt_in", json={"opt_in": False})
        on = await ac.post(f"/v1/leaderboard/{user_id}/opt_in", json={"opt_in": True})
    assert off.status_code == 200 and off.json()["leaderboard_opt_in"] is False
    assert on.status_code == 200 and on.json()["leaderboard_opt_in"] is True
    assert on.json()["user_id"] == str(user_id)


async def test_opt_in_other_user_403(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    other = await _new_user(pool)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(f"/v1/leaderboard/{other}/opt_in", json={"opt_in": True})
    assert r.status_code == 403
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/integration/test_routes_gamification.py -q`
Expected: SKIPPED locally. In CI: 404 on `/v1/leaderboard`.

- [ ] **Step 3: Add the two handlers**

Append to `server/src/bubbles/api/v1/gamification.py` (after `redeem_reward`):

```python
def _period_start(period: _Period, now: datetime) -> datetime | None:
    if period == "all":
        return None
    if period == "daily":
        return datetime(now.year, now.month, now.day, tzinfo=timezone.utc)
    if period == "weekly":
        return now - timedelta(days=7)
    return now - timedelta(days=30)  # monthly


@router.get("/leaderboard", response_model=LeaderboardResponse)
async def get_leaderboard(
    user: CurrentUserDep,
    pool: PoolDep,
    period: _Period = "all",
    limit: int = Query(25, ge=1, le=100),
) -> LeaderboardResponse:
    me_id = UUID(user.id)
    now = datetime.now(timezone.utc)
    since = _period_start(period, now)
    async with transaction(pool) as conn:
        if since is None:
            rows = await gamification_repo.leaderboard_top(conn, limit=limit)
            entries = [
                LeaderboardEntry(
                    user_id=r["user_id"],
                    xp=r["total_xp"],
                    level=r["level"],
                    current_streak=r["current_streak"],
                    rank=i + 1,
                )
                for i, r in enumerate(rows)
            ]
            my_rank = await gamification_repo.rank_all_time(conn, user_id=me_id)
            my_g = await gamification_repo.get_or_init_gamification(conn, me_id)
            my_xp = my_g.total_xp
        else:
            rows = await gamification_repo.leaderboard_period(conn, since=since, limit=limit)
            entries = [
                LeaderboardEntry(
                    user_id=r["user_id"],
                    xp=r["xp"],
                    level=r["level"],
                    current_streak=r["current_streak"],
                    rank=i + 1,
                )
                for i, r in enumerate(rows)
            ]
            my_rank = await gamification_repo.rank_period(conn, user_id=me_id, since=since)
            my_xp = await xp_repo.sum_since(conn, user_id=me_id, since=since)
    return LeaderboardResponse(period=period, entries=entries, me=LeaderboardMe(rank=my_rank, xp=my_xp))


@router.post("/leaderboard/{user_id}/opt_in", response_model=OptInResponse)
async def set_leaderboard_opt_in(
    user_id: UUID,
    body: OptInRequest,
    user: CurrentUserDep,
    pool: PoolDep,
) -> OptInResponse:
    require_ownership(user, str(user_id))
    async with UnitOfWork(pool) as uow:
        g = await gamification_repo.set_leaderboard_opt_in(
            uow.conn, user_id=user_id, opt_in=body.opt_in
        )
    return OptInResponse(user_id=user_id, leaderboard_opt_in=g.leaderboard_opt_in)
```

- [ ] **Step 4: Confirm the import block is complete**

The top of `server/src/bubbles/api/v1/gamification.py` must now have exactly these imports used (no unused, none missing):
```python
from datetime import datetime, timedelta, timezone
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Query

from bubbles.api.v1._schemas import (
    AchievementOut, DailyQuestsResponse, GamificationProfile, LeaderboardEntry,
    LeaderboardMe, LeaderboardResponse, OptInRequest, OptInResponse,
    RewardCatalogResponse, RewardOut, RewardRedeemRequest, RewardRedeemResponse,
    UserQuestOut, XpEntryOut,
)
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import BadRequest
from bubbles.core.gamification import level_progress
from bubbles.db.repo import achievements as achievements_repo
from bubbles.db.repo import gamification as gamification_repo
from bubbles.db.repo import xp as xp_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep
```
(`ruff` will format the multi-line `_schemas` import; let `ruff format` arrange it.)

- [ ] **Step 5: Run the full gate**

Run (from `server/`):
```bash
uv run python -c "from bubbles.app import create_app; app = create_app(); print(sorted(r.path for r in app.routes if 'leaderboard' in r.path or 'gamification' in r.path or '/v1/quests' in r.path or '/v1/rewards' in r.path))"
uv run pytest tests/integration/test_routes_gamification.py -q   # SKIPPED locally
uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest -q
```
Expected: prints all six paths; integration SKIPs locally; ruff clean; `ruff format --check` clean; mypy `Success` (no unused-import or missing-import errors); unit pytest fully green.

- [ ] **Step 6: Commit**

```bash
git add server/src/bubbles/api/v1/gamification.py server/tests/integration/test_routes_gamification.py
git commit -m "feat(api): GET /v1/leaderboard + POST /v1/leaderboard/{user_id}/opt_in"
```

---

### Task 11: update the comparison-review doc

**Files:**
- Modify: `Documentation/server-vs-server_v2-review.md` (§5)
- Modify: `README.md` (Backend API Summary — add the gamification routes)

> Note: `Documentation/` is gitignored but `server-vs-server_v2-review.md` is force-tracked; use `git add -f` if needed. There is exactly one copy at the repo root — do not create `server/Documentation/`.

- [ ] **Step 1: Update §5 of the review doc**

In `Documentation/server-vs-server_v2-review.md`, replace the `> **Batch 1 (entity routes) — done.** ...` callout's trailing sentence about remaining ports, and the "Gamification HTTP routes" bullet, to reflect Batch 2. Concretely:

- Add after the Batch 1 callout a new callout:
  > **Batch 2 (gamification HTTP) — done.** `GET /v1/gamification/{user_id}`, `GET /v1/quests/{user_id}` (auto-assigns 3 daily quests), `GET /v1/rewards/{user_id}` (catalog + balance + affordability/ownership), `POST /v1/rewards/{user_id}/redeem`, `GET /v1/leaderboard?period=all|daily|weekly|monthly&limit=`, `POST /v1/leaderboard/{user_id}/opt_in` are implemented in v5. New tables `xp_transactions` / `achievements` / `user_achievements` (Alembic `0003`); pure level-math in `bubbles/core/gamification.py`; `add_xp` is now ledger-aware and idempotent on `source_id`. See `docs/superpowers/specs/2026-05-12-v5-port-batch2-gamification-design.md`. Still pending per their own batches: quest mission types (`/quests/{uid}/{uqid}/answer` + `/attach_session`), analytics/performance reads, `performance_summary`, speaker `enroll`/`identify_speaker`, `process_transcript_wingman`.
- Replace the existing `- **Gamification HTTP routes** (...): repo logic exists ... TODO (later batch).` bullet with:
  > - **Gamification follow-ups**: the two quest *mission* endpoints (`POST /quests/{uid}/{uqid}/answer` for question_set missions, `POST /quests/{uid}/{uqid}/attach_session` for conversation missions) are not ported yet; `add_xp` does not yet apply v2's automated daily XP cap (500), streak-milestone bursts, or first-action-today bonus (the idempotency mechanism is in place); no worker populates `user_achievements` yet (badges stay empty until an achievement-detection job lands); profile omits v2's `stats{}` block.

- [ ] **Step 2: Update the README API summary**

In `README.md`, under "## Backend API Summary", add a new group after "Entities":
```markdown
- Gamification
  - `GET /v1/gamification/{user_id}`
  - `GET /v1/quests/{user_id}`
  - `GET /v1/rewards/{user_id}`
  - `POST /v1/rewards/{user_id}/redeem`
  - `GET /v1/leaderboard`
  - `POST /v1/leaderboard/{user_id}/opt_in`
```

- [ ] **Step 3: Verify nothing else changed + commit**

Run (from repo root): `git status --porcelain` — expect only `Documentation/server-vs-server_v2-review.md` and `README.md` modified.
```bash
git add -f Documentation/server-vs-server_v2-review.md
git add README.md
git commit -m "docs: record Batch 2 (gamification HTTP) completion"
```

---

## Self-review notes (for the executor — already reconciled, no action needed)

- **Spec coverage:** §2 tables → Task 1; §3 models (+`UserBadge`) → Task 2; §4 level helpers → Task 3; §5.1 `xp` repo → Task 4; §5.2 `achievements` repo → Task 5; §5.3 gamification repo extensions (`add_xp`, `get_or_assign_daily_quests`, `leaderboard_period`, `rank_all_time`, `rank_period`, `owned_reward_ids`) → Task 6; §7 schemas → Task 7; §6 routes 1–2 → Task 8, routes 3–4 → Task 9, routes 5–6 → Task 10; §9 follow-ups + review doc → Task 11. The integration `conftest.py` teardown + `baseline.sql` (§2) → Task 1. §10 testing distributed across Tasks 3–10.
- **Type consistency:** `add_xp(conn, *, user_id, amount, source_type="manual", source_id=None, description=None)` — same name everywhere; `xp_repo.record` returns `XpTransaction | None`; `achievements_repo.list_for_user` returns `list[UserBadge]` where `UserBadge(achievement: Achievement, awarded_at: datetime)`; route handler names: `get_gamification`, `get_quests`, `list_rewards`, `redeem_reward`, `get_leaderboard`, `set_leaderboard_opt_in`; schema names match `_schemas.py` additions in Task 7.
- **No placeholders:** every code step shows complete code; every command shows expected output.
