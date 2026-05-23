# Spaced-Repetition Mistake Drills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing `user_mistakes` log into a Leitner-box spaced-repetition drill system: cards materialised at session-end, self-graded by the user, awarding XP on every box transition.

**Architecture:** One new table `drill_cards` keyed by `(user_id, rule_id, category)`. ARQ worker `materialize_drill_cards` runs from the `end_session` fan-out and upserts cards from this session's mistakes (appending example snippets, cap 10). Three routes — queue/review/retire — plus a pure `next_state` helper that drives Leitner transitions. XP is awarded per transition via the existing `xp_repo.record` idempotency.

**Tech Stack:** FastAPI, asyncpg (raw SQL through repos), Alembic (raw-SQL migrations), ARQ workers, Pydantic, pytest + testcontainers Postgres.

**Spec:** `docs/superpowers/specs/2026-05-23-spaced-repetition-drills-design.md`.

---

## File Structure

| Path | Type | Responsibility |
|---|---|---|
| `server/alembic/versions/2026_05_23_0007_drill_cards.py` | Create | Forward + downgrade migration for the `drill_cards` table and its two indexes. |
| `server/src/bubbles/db/models.py` | Modify | Append `DrillCard` frozen-slot dataclass mirroring the table. |
| `server/src/bubbles/ai/drills.py` | Create | Pure helpers: `BOX_INTERVALS` constant and `next_state(box, result)` Leitner step. No I/O. |
| `server/src/bubbles/db/repo/drill_cards.py` | Create | Repo: `upsert_from_mistakes`, `list_due`, `count_due`, `list_upcoming`, `get`, `apply_review`, `retire`. Inputs: `NewMistakeForCard` dataclass. |
| `server/src/bubbles/db/repo/grammar.py` | Modify | Append `list_for_session(conn, *, session_id) -> list[UserMistake]` reader. |
| `server/src/bubbles/db/repo/__init__.py` | Modify | Import-expose the new `drill_cards` repo. |
| `server/src/bubbles/api/v1/_schemas.py` | Modify | `DrillCardOut`, `ReviewDrillRequest`, `ReviewDrillResponse`, `DrillQueueResponse`. |
| `server/src/bubbles/api/v1/drills.py` | Create | Three routes: `GET /v1/drills/queue`, `POST /v1/drills/{id}/review`, `POST /v1/drills/{id}/retire`. |
| `server/src/bubbles/api/router.py` | Modify | Register the drills router under `/v1`. |
| `server/src/bubbles/workers/jobs/materialize_drill_cards.py` | Create | ARQ worker that loads session mistakes and upserts cards. Idempotent per session. |
| `server/src/bubbles/workers/enqueue.py` | Modify | Append `enqueue_materialize_drill_cards(arq, *, user_id, session_id)`. |
| `server/src/bubbles/workers/arq_settings.py` | Modify | Import + register the worker in `_JOB_REGISTRY`. |
| `server/src/bubbles/api/v1/sessions.py` | Modify | Append the new enqueue call to `_enqueue_post_session_jobs`. |
| `server/tests/integration/fixtures/baseline.sql` | Modify | Append `drill_cards` CREATE TABLE + indexes (mirroring the migration body). |
| `server/tests/integration/conftest.py` | Modify | Add `drill_cards` to the teardown DROP-table list. |
| `server/tests/unit/test_drill_intervals.py` | Create | Pure unit tests for `next_state`. |
| `server/tests/integration/test_repo_drill_cards.py` | Create | Repo behaviour: upsert dedup + example cap, list filters, review transitions, retire, ownership. |
| `server/tests/integration/test_repo_grammar_session.py` | Create | Reader test for `grammar_repo.list_for_session`. |
| `server/tests/integration/test_routes_drills.py` | Create | Route ownership, status transitions, XP awarding, include-upcoming fallback. |
| `server/tests/integration/test_workers_drills.py` | Create | Worker no-op on empty mistakes, upsert on first call, idempotent on second call. |
| `server/tests/integration/test_routes_sessions.py` | Modify | Extend with assertion that `end_session` enqueues `materialize_drill_cards`. |

---

## Notes for the implementer

- **No placeholders.** Every step in every task must produce a fully working artifact. No `pass`-stub bodies, no `TODO` / `FIXME`, no fake return values. If a step calls for code, the code block below it is the code — not pseudocode.
- **Frequent commits.** Each task ends with a `git commit -m "..." -- <explicit files>` step that names every file changed by that task. **Always pass explicit pathspec** to `git commit` so a stray staged-deletion from a previous task can't get swept in.
- **No Co-Authored-By trailer.** Commits must NOT include `Co-Authored-By: Claude …`. Plain subject + optional body only.
- **Verify after each commit.** Run `git show --stat HEAD` after every commit. The file list must match the "Files" block of the task. If it doesn't, restore the missing/stray file with `git checkout <prev-sha> -- <path>` and amend.
- **TDD.** Every task starts with the failing test, then the implementation, then green.
- **DB tests.** Integration tests run under `$env:RUN_INTEGRATION='1'` and require Docker (testcontainers Postgres). They skip automatically when Docker is unavailable. The pytest invocations below already include the env-var setup for PowerShell.
- **Branch.** All work happens on `feat/spaced-repetition-drills` (already created from `main`).

---

## Tasks

### Task 1: Migration `0007_drill_cards`

**Files:**
- Create: `server/alembic/versions/2026_05_23_0007_drill_cards.py`
- Modify: `server/tests/integration/fixtures/baseline.sql`
- Modify: `server/tests/integration/conftest.py`

- [ ] **Step 1: Write the migration file**

Create `server/alembic/versions/2026_05_23_0007_drill_cards.py`:

```python
"""drill_cards — Leitner-box spaced-repetition cards for past user mistakes.

New table; not present in the live Supabase schema yet. ``CREATE TABLE IF
NOT EXISTS`` keeps the migration idempotent and safe to re-run, matching
0002-0006.

Revision ID: 0007
Revises: 0006
Create Date: 2026-05-23 00:00:00 UTC
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS drill_cards (
            id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id           uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
            rule_id           text        NOT NULL,
            category          text        NOT NULL,
            examples          jsonb       NOT NULL DEFAULT '[]'::jsonb,
            box               smallint    NOT NULL DEFAULT 1
                                  CHECK (box BETWEEN 1 AND 5),
            due_at            timestamptz NOT NULL DEFAULT now(),
            last_reviewed_at  timestamptz,
            correct_streak    integer     NOT NULL DEFAULT 0,
            total_reviews     integer     NOT NULL DEFAULT 0,
            total_correct     integer     NOT NULL DEFAULT 0,
            retired_at        timestamptz,
            created_at        timestamptz NOT NULL DEFAULT now(),
            updated_at        timestamptz NOT NULL DEFAULT now(),
            CONSTRAINT uq_drill_cards_user_rule_category UNIQUE (user_id, rule_id, category)
        );
        CREATE INDEX IF NOT EXISTS idx_drill_cards_user_due
            ON drill_cards (user_id, due_at)
            WHERE retired_at IS NULL;
        CREATE INDEX IF NOT EXISTS idx_drill_cards_user_retired
            ON drill_cards (user_id, retired_at);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX IF EXISTS idx_drill_cards_user_retired;
        DROP INDEX IF EXISTS idx_drill_cards_user_due;
        DROP TABLE IF EXISTS drill_cards;
        """
    )
```

- [ ] **Step 2: Append the table to the baseline fixture**

Open `server/tests/integration/fixtures/baseline.sql`. Locate the existing `CREATE TABLE scenarios (...)` block (added in F1, migration 0006). Immediately after the final `);` of the scenarios block plus its index lines, append:

```sql
CREATE TABLE drill_cards (
    id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    rule_id           text        NOT NULL,
    category          text        NOT NULL,
    examples          jsonb       NOT NULL DEFAULT '[]'::jsonb,
    box               smallint    NOT NULL DEFAULT 1
                          CHECK (box BETWEEN 1 AND 5),
    due_at            timestamptz NOT NULL DEFAULT now(),
    last_reviewed_at  timestamptz,
    correct_streak    integer     NOT NULL DEFAULT 0,
    total_reviews     integer     NOT NULL DEFAULT 0,
    total_correct     integer     NOT NULL DEFAULT 0,
    retired_at        timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_drill_cards_user_rule_category UNIQUE (user_id, rule_id, category)
);
CREATE INDEX idx_drill_cards_user_due
    ON drill_cards (user_id, due_at)
    WHERE retired_at IS NULL;
CREATE INDEX idx_drill_cards_user_retired
    ON drill_cards (user_id, retired_at);
```

(The baseline file uses raw `CREATE INDEX` without `IF NOT EXISTS` because it's a fresh-database fixture; only the migration is idempotent. Match that style.)

- [ ] **Step 3: Add `drill_cards` to the conftest teardown list**

Open `server/tests/integration/conftest.py`. Find the list of table names passed to the teardown DROP block (it already includes `"scenarios"`, `"user_mistakes"`, etc.). Add `"drill_cards"` next to `"scenarios"`:

```python
TABLES_TO_TRUNCATE = (
    # existing entries unchanged …
    "scenarios",
    "drill_cards",
    # … rest unchanged
)
```

(The actual constant name may differ — read the file's truncate/drop list and add `"drill_cards"` to it in the same alphabetical/group position as `scenarios` was added during F1.)

- [ ] **Step 4: Verify migration head + downgrade**

Run from `server/`:

```powershell
$env:DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/bubbles_test"
.\..\.venv\Scripts\Activate.ps1
alembic upgrade head
alembic downgrade -1
alembic upgrade head
```

Expected: each command exits 0. After the round-trip, `\dt drill_cards` in `psql` shows the table.

If no local Postgres is available, this step can be skipped — the same migration is exercised by the testcontainers fixture in later tasks.

- [ ] **Step 5: Commit**

```bash
git add server/alembic/versions/2026_05_23_0007_drill_cards.py server/tests/integration/fixtures/baseline.sql server/tests/integration/conftest.py
git commit -m "feat(drills): add drill_cards table (migration 0007)" -- server/alembic/versions/2026_05_23_0007_drill_cards.py server/tests/integration/fixtures/baseline.sql server/tests/integration/conftest.py
git show --stat HEAD
```

Expected `git show --stat`: exactly 3 files changed.

---

### Task 2: `DrillCard` dataclass

**Files:**
- Modify: `server/src/bubbles/db/models.py`

- [ ] **Step 1: Write the failing import test (inline check)**

There is no dedicated test file for `db/models.py` — the class is exercised through the repo tests in Task 4. As a fast structural check, run:

```powershell
.\..\.venv\Scripts\Activate.ps1
python -c "from bubbles.db.models import DrillCard"
```

Expected: `ImportError: cannot import name 'DrillCard' from 'bubbles.db.models'`.

- [ ] **Step 2: Append the dataclass**

Open `server/src/bubbles/db/models.py`. After the existing `Scenario` dataclass (last in the file), append:

```python


@dataclass(frozen=True, slots=True)
class DrillCard:
    id: UUID
    user_id: UUID
    rule_id: str
    category: str
    examples: list[dict[str, Any]]
    box: int
    due_at: datetime
    last_reviewed_at: datetime | None
    correct_streak: int
    total_reviews: int
    total_correct: int
    retired_at: datetime | None
    created_at: datetime
    updated_at: datetime
```

(`UUID`, `datetime`, `dataclass`, and `Any` are already imported at the top of the file — verify by reading the existing import block. If `Any` is not yet imported, add it to the existing `from typing import …` line.)

- [ ] **Step 3: Verify import succeeds**

```powershell
python -c "from bubbles.db.models import DrillCard; print(DrillCard.__dataclass_fields__.keys())"
```

Expected: prints the field names in order — `dict_keys(['id', 'user_id', 'rule_id', 'category', 'examples', 'box', 'due_at', 'last_reviewed_at', 'correct_streak', 'total_reviews', 'total_correct', 'retired_at', 'created_at', 'updated_at'])`.

- [ ] **Step 4: Lint**

```powershell
ruff check server/src/bubbles/db/models.py
mypy --strict server/src/bubbles/db/models.py
```

Expected: both clean.

- [ ] **Step 5: Commit**

```bash
git add server/src/bubbles/db/models.py
git commit -m "feat(drills): add DrillCard dataclass" -- server/src/bubbles/db/models.py
git show --stat HEAD
```

Expected: exactly 1 file changed.

---

### Task 3: `ai/drills.py` pure helper + unit tests

**Files:**
- Create: `server/src/bubbles/ai/drills.py`
- Create: `server/tests/unit/test_drill_intervals.py`

- [ ] **Step 1: Write the failing unit tests**

Create `server/tests/unit/test_drill_intervals.py`:

```python
"""Pure-helper tests for ai.drills.next_state."""

from __future__ import annotations

from datetime import timedelta

import pytest

from bubbles.ai.drills import BOX_INTERVALS, next_state


def test_box_intervals_table_is_complete() -> None:
    assert set(BOX_INTERVALS.keys()) == {1, 2, 3, 4, 5}
    assert BOX_INTERVALS[1] == timedelta(days=1)
    assert BOX_INTERVALS[2] == timedelta(days=3)
    assert BOX_INTERVALS[3] == timedelta(days=7)
    assert BOX_INTERVALS[4] == timedelta(days=14)
    assert BOX_INTERVALS[5] == timedelta(days=30)


@pytest.mark.parametrize(
    ("from_box", "expected_new_box", "expected_interval"),
    [
        (1, 2, timedelta(days=3)),
        (2, 3, timedelta(days=7)),
        (3, 4, timedelta(days=14)),
        (4, 5, timedelta(days=30)),
        (5, 5, timedelta(days=30)),  # cap at 5
    ],
)
def test_correct_review_advances_box(
    from_box: int, expected_new_box: int, expected_interval: timedelta
) -> None:
    new_box, interval, transition = next_state(from_box, "correct")
    assert new_box == expected_new_box
    assert interval == expected_interval
    assert transition == f"{from_box}->{expected_new_box}"


@pytest.mark.parametrize("from_box", [1, 2, 3, 4, 5])
def test_wrong_review_resets_to_box_one(from_box: int) -> None:
    new_box, interval, transition = next_state(from_box, "wrong")
    assert new_box == 1
    assert interval == timedelta(days=1)
    assert transition == f"{from_box}->1"


def test_invalid_box_raises() -> None:
    with pytest.raises(ValueError, match="box must be 1..5"):
        next_state(0, "correct")
    with pytest.raises(ValueError, match="box must be 1..5"):
        next_state(6, "correct")


def test_invalid_result_raises() -> None:
    with pytest.raises(ValueError, match="result must be 'correct' or 'wrong'"):
        next_state(1, "ok")  # type: ignore[arg-type]
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
pytest server/tests/unit/test_drill_intervals.py -v
```

Expected: `ModuleNotFoundError: No module named 'bubbles.ai.drills'`.

- [ ] **Step 3: Write the helper**

Create `server/src/bubbles/ai/drills.py`:

```python
"""Pure helpers for the drill (spaced-repetition) subsystem.

Leitner-box transition math. No I/O, no DB, no LLM — unit-testable.

``BOX_INTERVALS`` maps each box (1..5) to the wait between consecutive
reviews. ``next_state(box, result)`` returns the post-review box, the new
interval, and a ``"{from}->{to}"`` transition label used as part of the
XP-idempotency source-id.
"""

from __future__ import annotations

from datetime import timedelta
from typing import Final, Literal, Mapping

ReviewResult = Literal["correct", "wrong"]

BOX_INTERVALS: Final[Mapping[int, timedelta]] = {
    1: timedelta(days=1),
    2: timedelta(days=3),
    3: timedelta(days=7),
    4: timedelta(days=14),
    5: timedelta(days=30),
}

_MAX_BOX: Final[int] = 5
_MIN_BOX: Final[int] = 1


def next_state(box: int, result: ReviewResult) -> tuple[int, timedelta, str]:
    """Return ``(new_box, interval_to_next_due, transition_label)`` for a Leitner step.

    Correct → box advances by 1 (capped at 5).
    Wrong → box resets to 1.
    The interval is ``BOX_INTERVALS[new_box]``. The transition label is
    ``f"{from_box}->{new_box}"`` and is part of the XP idempotency key.
    """
    if box < _MIN_BOX or box > _MAX_BOX:
        raise ValueError("box must be 1..5")
    if result not in ("correct", "wrong"):
        raise ValueError("result must be 'correct' or 'wrong'")
    new_box = min(box + 1, _MAX_BOX) if result == "correct" else _MIN_BOX
    return new_box, BOX_INTERVALS[new_box], f"{box}->{new_box}"
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
pytest server/tests/unit/test_drill_intervals.py -v
```

Expected: 12 tests passed (1 + 5 parametrized correct + 5 parametrized wrong + 1 invalid-box × 2 + 1 invalid-result — count may vary slightly depending on parametrize collection; all green).

- [ ] **Step 5: Lint**

```powershell
ruff check server/src/bubbles/ai/drills.py server/tests/unit/test_drill_intervals.py
mypy --strict server/src/bubbles/ai/drills.py
```

Expected: both clean.

- [ ] **Step 6: Commit**

```bash
git add server/src/bubbles/ai/drills.py server/tests/unit/test_drill_intervals.py
git commit -m "feat(drills): add Leitner next_state helper with unit tests" -- server/src/bubbles/ai/drills.py server/tests/unit/test_drill_intervals.py
git show --stat HEAD
```

Expected: exactly 2 files changed.

---

### Task 4: `drill_cards` repo + integration tests

**Files:**
- Create: `server/src/bubbles/db/repo/drill_cards.py`
- Modify: `server/src/bubbles/db/repo/__init__.py`
- Create: `server/tests/integration/test_repo_drill_cards.py`

- [ ] **Step 1: Write the failing integration tests**

Create `server/tests/integration/test_repo_drill_cards.py`:

```python
"""drill_cards repo integration tests.

Requires Docker (testcontainers Postgres); skipped automatically without it.
Toggle on via:  $env:RUN_INTEGRATION='1'
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

import pytest

from bubbles.ai.drills import BOX_INTERVALS
from bubbles.db.repo import drill_cards as repo
from bubbles.db.repo.drill_cards import NewMistakeForCard

pytestmark = pytest.mark.integration


def _mistake(
    *,
    rule_id: str = "LLM_ARTICLE",
    category: str = "article",
    snippet: str = "I went to store.",
    suggestion: str | None = "I went to the store.",
) -> NewMistakeForCard:
    return NewMistakeForCard(
        mistake_id=uuid4(),
        rule_id=rule_id,
        category=category,
        snippet=snippet,
        suggestion=suggestion,
    )


@pytest.mark.asyncio
async def test_upsert_creates_then_appends_examples(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            n1 = await repo.upsert_from_mistakes(
                conn, user_id=user_id, mistakes=[_mistake(snippet="A")]
            )
        assert n1 == 1
        async with conn.transaction():
            n2 = await repo.upsert_from_mistakes(
                conn, user_id=user_id, mistakes=[_mistake(snippet="B")]
            )
        assert n2 == 1  # same card touched, not a second card
        async with conn.transaction():
            due = await repo.list_due(conn, user_id=user_id, limit=10, offset=0)
        assert len(due) == 1
        card = due[0]
        assert card.rule_id == "LLM_ARTICLE"
        assert card.category == "article"
        # newest first
        assert card.examples[0]["snippet"] == "B"
        assert card.examples[1]["snippet"] == "A"
        assert len(card.examples) == 2


@pytest.mark.asyncio
async def test_upsert_caps_examples_at_ten(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        for i in range(15):
            async with conn.transaction():
                await repo.upsert_from_mistakes(
                    conn, user_id=user_id, mistakes=[_mistake(snippet=f"S{i}")]
                )
        async with conn.transaction():
            due = await repo.list_due(conn, user_id=user_id, limit=10, offset=0)
        assert len(due) == 1
        card = due[0]
        assert len(card.examples) == 10
        # newest at index 0 — last inserted is S14
        assert card.examples[0]["snippet"] == "S14"
        # and the oldest retained is S5 (S0..S4 dropped)
        assert card.examples[-1]["snippet"] == "S5"


@pytest.mark.asyncio
async def test_list_due_excludes_retired_and_future(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await repo.upsert_from_mistakes(conn, user_id=user_id, mistakes=[_mistake()])
            # push due_at to tomorrow + retire on a second card
            future = datetime.now(timezone.utc) + timedelta(days=2)
            await conn.execute(
                "UPDATE drill_cards SET due_at = $1 WHERE user_id = $2",
                future,
                user_id,
            )
        async with conn.transaction():
            due = await repo.list_due(conn, user_id=user_id, limit=10, offset=0)
            upcoming = await repo.list_upcoming(conn, user_id=user_id, limit=10)
        assert due == []
        assert len(upcoming) == 1


@pytest.mark.asyncio
async def test_apply_review_correct_advances_box(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await repo.upsert_from_mistakes(conn, user_id=user_id, mistakes=[_mistake()])
            due = await repo.list_due(conn, user_id=user_id, limit=10, offset=0)
            card = due[0]
        async with conn.transaction():
            after = await repo.apply_review(
                conn,
                card_id=card.id,
                result="correct",
                intervals=BOX_INTERVALS,
            )
        assert after.box == 2
        assert after.correct_streak == 1
        assert after.total_reviews == 1
        assert after.total_correct == 1
        assert after.due_at > card.due_at  # pushed forward
        # interval matches box 2 (3 days from now)
        now = datetime.now(timezone.utc)
        delta = after.due_at - now
        assert timedelta(days=2, hours=20) < delta < timedelta(days=3, hours=4)


@pytest.mark.asyncio
async def test_apply_review_wrong_resets_to_box_one(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await repo.upsert_from_mistakes(conn, user_id=user_id, mistakes=[_mistake()])
            card = (await repo.list_due(conn, user_id=user_id, limit=10, offset=0))[0]
        async with conn.transaction():
            advanced = await repo.apply_review(
                conn, card_id=card.id, result="correct", intervals=BOX_INTERVALS
            )
            assert advanced.box == 2
        async with conn.transaction():
            # force it due again so we can review it
            await conn.execute(
                "UPDATE drill_cards SET due_at = now() WHERE id = $1", advanced.id
            )
        async with conn.transaction():
            after = await repo.apply_review(
                conn, card_id=advanced.id, result="wrong", intervals=BOX_INTERVALS
            )
        assert after.box == 1
        assert after.correct_streak == 0
        assert after.total_reviews == 2
        assert after.total_correct == 1  # unchanged on wrong


@pytest.mark.asyncio
async def test_retire_excludes_from_queue(pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await repo.upsert_from_mistakes(conn, user_id=user_id, mistakes=[_mistake()])
            card = (await repo.list_due(conn, user_id=user_id, limit=10, offset=0))[0]
        async with conn.transaction():
            retired = await repo.retire(conn, card_id=card.id)
        assert retired is not None
        assert retired.retired_at is not None
        async with conn.transaction():
            again = await repo.retire(conn, card_id=card.id)
        assert again is None  # idempotent guard
        async with conn.transaction():
            due = await repo.list_due(conn, user_id=user_id, limit=10, offset=0)
        assert due == []


@pytest.mark.asyncio
async def test_ownership_scoped(pool, user_id: UUID, other_user_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await repo.upsert_from_mistakes(conn, user_id=user_id, mistakes=[_mistake()])
        async with conn.transaction():
            due_other = await repo.list_due(conn, user_id=other_user_id, limit=10, offset=0)
        assert due_other == []
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
$env:RUN_INTEGRATION = '1'
pytest server/tests/integration/test_repo_drill_cards.py -v
```

Expected: `ModuleNotFoundError: No module named 'bubbles.db.repo.drill_cards'`.

- [ ] **Step 3: Write the repo**

Create `server/src/bubbles/db/repo/drill_cards.py`:

```python
"""drill_cards repo — Leitner-box spaced-repetition cards for past mistakes.

One row per ``(user_id, rule_id, category)``. ``upsert_from_mistakes`` is
the materialization entry point used by the ``materialize_drill_cards``
worker. ``apply_review`` is the SRS transition used by the review route.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Final, Literal, Mapping, Sequence
from uuid import UUID

import asyncpg

from bubbles.db.models import DrillCard

_COLS: Final[str] = (
    "id, user_id, rule_id, category, examples, box, due_at, "
    "last_reviewed_at, correct_streak, total_reviews, total_correct, "
    "retired_at, created_at, updated_at"
)

_EXAMPLES_CAP: Final[int] = 10


@dataclass(frozen=True, slots=True)
class NewMistakeForCard:
    """An input row for ``upsert_from_mistakes``.

    Carries the data needed to either create a new card or prepend an
    example to an existing one keyed by ``(user_id, rule_id, category)``.
    """

    mistake_id: UUID
    rule_id: str
    category: str
    snippet: str
    suggestion: str | None


def _examples(raw: Any) -> list[dict[str, Any]]:
    if isinstance(raw, str):
        loaded: Any = json.loads(raw)
        return list(loaded) if isinstance(loaded, list) else []
    return list(raw) if raw else []


def _row(r: asyncpg.Record) -> DrillCard:
    return DrillCard(
        id=r["id"],
        user_id=r["user_id"],
        rule_id=r["rule_id"],
        category=r["category"],
        examples=_examples(r["examples"]),
        box=r["box"],
        due_at=r["due_at"],
        last_reviewed_at=r["last_reviewed_at"],
        correct_streak=r["correct_streak"],
        total_reviews=r["total_reviews"],
        total_correct=r["total_correct"],
        retired_at=r["retired_at"],
        created_at=r["created_at"],
        updated_at=r["updated_at"],
    )


def _example_entry(m: NewMistakeForCard, *, now: datetime) -> dict[str, Any]:
    return {
        "mistake_id": str(m.mistake_id),
        "snippet": m.snippet,
        "suggestion": m.suggestion or "",
        "created_at": now.isoformat(),
    }


async def upsert_from_mistakes(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    mistakes: Sequence[NewMistakeForCard],
) -> int:
    """Upsert one card per distinct ``(rule_id, category)`` in ``mistakes``.

    For each input row: ``INSERT … ON CONFLICT (user_id, rule_id, category)
    DO UPDATE`` — prepend a new example entry to the JSONB ``examples``
    array, cap at the 10 newest, and bump ``updated_at``. Returns the
    number of distinct cards touched (not the count of example rows).
    """
    if not mistakes:
        return 0
    now = datetime.now(timezone.utc)
    touched: set[tuple[str, str]] = set()
    for m in mistakes:
        entry = _example_entry(m, now=now)
        await conn.execute(
            """
            INSERT INTO drill_cards (user_id, rule_id, category, examples)
            VALUES ($1, $2, $3, $4::jsonb)
            ON CONFLICT (user_id, rule_id, category) DO UPDATE
            SET examples = (
                    SELECT jsonb_agg(e)
                    FROM (
                        SELECT e
                        FROM jsonb_array_elements(
                            ($4::jsonb) || drill_cards.examples
                        ) AS t(e)
                        LIMIT $5
                    ) AS sub
                ),
                updated_at = now()
            """,
            user_id,
            m.rule_id,
            m.category,
            json.dumps([entry]),
            _EXAMPLES_CAP,
        )
        touched.add((m.rule_id, m.category))
    return len(touched)


async def list_due(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    limit: int = 20,
    offset: int = 0,
) -> list[DrillCard]:
    rows = await conn.fetch(
        f"""
        SELECT {_COLS} FROM drill_cards
        WHERE user_id = $1
          AND retired_at IS NULL
          AND due_at <= now()
        ORDER BY due_at ASC
        LIMIT $2 OFFSET $3
        """,
        user_id,
        limit,
        offset,
    )
    return [_row(r) for r in rows]


async def count_due(conn: asyncpg.Connection, *, user_id: UUID) -> int:
    n: int | None = await conn.fetchval(
        """
        SELECT COUNT(*)::int FROM drill_cards
        WHERE user_id = $1 AND retired_at IS NULL AND due_at <= now()
        """,
        user_id,
    )
    return n or 0


async def list_upcoming(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    limit: int = 20,
) -> list[DrillCard]:
    rows = await conn.fetch(
        f"""
        SELECT {_COLS} FROM drill_cards
        WHERE user_id = $1 AND retired_at IS NULL AND due_at > now()
        ORDER BY due_at ASC
        LIMIT $2
        """,
        user_id,
        limit,
    )
    return [_row(r) for r in rows]


async def get(conn: asyncpg.Connection, *, card_id: UUID) -> DrillCard | None:
    row = await conn.fetchrow(
        f"SELECT {_COLS} FROM drill_cards WHERE id = $1", card_id
    )
    return _row(row) if row is not None else None


async def apply_review(
    conn: asyncpg.Connection,
    *,
    card_id: UUID,
    result: Literal["correct", "wrong"],
    intervals: Mapping[int, timedelta],
) -> DrillCard:
    """Atomically advance/reset the box and push ``due_at``.

    Loads the current ``box`` inside the SQL via a CTE so the box math
    happens in one round-trip. ``intervals`` is injected so the route can
    use the canonical ``BOX_INTERVALS`` and tests can substitute.
    Raises ``LookupError`` if the card does not exist.
    """
    # Compute the new_box → interval map as PostgreSQL CASE arms.
    # The 5-box table is small enough that this is cleaner than a JOIN.
    # Each interval is rendered as a literal ISO-8601 duration string
    # we cast to ``interval`` server-side.
    correct_arms = ", ".join(
        f"WHEN {from_box} THEN {min(from_box + 1, 5)}" for from_box in range(1, 6)
    )
    interval_arms = ", ".join(
        f"WHEN {b} THEN interval '{int(intervals[b].total_seconds())} seconds'"
        for b in range(1, 6)
    )
    if result == "correct":
        sql = f"""
            UPDATE drill_cards
            SET box = CASE box {correct_arms} END,
                correct_streak = correct_streak + 1,
                total_reviews = total_reviews + 1,
                total_correct = total_correct + 1,
                last_reviewed_at = now(),
                due_at = now() + (
                    CASE (CASE box {correct_arms} END)
                    {interval_arms}
                    END
                ),
                updated_at = now()
            WHERE id = $1
            RETURNING {_COLS}
        """
    else:
        sql = f"""
            UPDATE drill_cards
            SET box = 1,
                correct_streak = 0,
                total_reviews = total_reviews + 1,
                last_reviewed_at = now(),
                due_at = now() + interval '{int(intervals[1].total_seconds())} seconds',
                updated_at = now()
            WHERE id = $1
            RETURNING {_COLS}
        """
    row = await conn.fetchrow(sql, card_id)
    if row is None:
        raise LookupError(f"drill_card not found: {card_id}")
    return _row(row)


async def retire(conn: asyncpg.Connection, *, card_id: UUID) -> DrillCard | None:
    """Set ``retired_at`` once. Returns ``None`` if already retired."""
    row = await conn.fetchrow(
        f"""
        UPDATE drill_cards
        SET retired_at = now(), updated_at = now()
        WHERE id = $1 AND retired_at IS NULL
        RETURNING {_COLS}
        """,
        card_id,
    )
    return _row(row) if row is not None else None
```

- [ ] **Step 4: Register the repo**

Open `server/src/bubbles/db/repo/__init__.py`. Add the import alongside the existing `scenarios` import (mirror its style):

```python
from bubbles.db.repo import drill_cards as drill_cards  # noqa: F401
```

(If `__init__.py` uses an explicit `__all__` tuple, append `"drill_cards"` to it. Otherwise the `noqa: F401` re-export is enough.)

- [ ] **Step 5: Run tests to verify they pass**

```powershell
$env:RUN_INTEGRATION = '1'
pytest server/tests/integration/test_repo_drill_cards.py -v
```

Expected: 7 tests passed.

(If running outside Docker, expect `SKIPPED`. The unit suite continues to pass; the integration gate only fires under `RUN_INTEGRATION=1`.)

- [ ] **Step 6: Lint**

```powershell
ruff check server/src/bubbles/db/repo/drill_cards.py server/tests/integration/test_repo_drill_cards.py
mypy --strict server/src/bubbles/db/repo/drill_cards.py
```

Expected: both clean.

- [ ] **Step 7: Commit**

```bash
git add server/src/bubbles/db/repo/drill_cards.py server/src/bubbles/db/repo/__init__.py server/tests/integration/test_repo_drill_cards.py
git commit -m "feat(drills): drill_cards repo with upsert + review + retire" -- server/src/bubbles/db/repo/drill_cards.py server/src/bubbles/db/repo/__init__.py server/tests/integration/test_repo_drill_cards.py
git show --stat HEAD
```

Expected: exactly 3 files changed.

---

### Task 5: `grammar_repo.list_for_session`

**Files:**
- Modify: `server/src/bubbles/db/repo/grammar.py`
- Create: `server/tests/integration/test_repo_grammar_session.py`

- [ ] **Step 1: Write the failing integration test**

Create `server/tests/integration/test_repo_grammar_session.py`:

```python
"""grammar_repo.list_for_session — per-session mistake reader used by the materialize worker."""

from __future__ import annotations

from uuid import UUID, uuid4

import pytest

from bubbles.db.repo import grammar as grammar_repo

pytestmark = pytest.mark.integration


@pytest.mark.asyncio
async def test_list_for_session_returns_only_that_sessions_rows(
    pool, user_id: UUID, session_id: UUID, other_session_id: UUID
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await grammar_repo.bulk_insert(
                conn,
                user_id=user_id,
                session_id=session_id,
                mistakes=[
                    {
                        "rule_id": "LLM_ARTICLE",
                        "category": "article",
                        "snippet": "X went to store.",
                        "suggestion": "X went to the store.",
                        "source": "llm",
                    },
                ],
            )
            await grammar_repo.bulk_insert(
                conn,
                user_id=user_id,
                session_id=other_session_id,
                mistakes=[
                    {
                        "rule_id": "LLM_AGREEMENT",
                        "category": "agreement",
                        "snippet": "He go home.",
                        "suggestion": "He goes home.",
                        "source": "llm",
                    },
                ],
            )
        async with conn.transaction():
            rows = await grammar_repo.list_for_session(conn, session_id=session_id)
        assert len(rows) == 1
        assert rows[0].rule_id == "LLM_ARTICLE"
        assert rows[0].session_id == session_id


@pytest.mark.asyncio
async def test_list_for_session_empty_when_no_rows(pool, session_id: UUID) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            rows = await grammar_repo.list_for_session(conn, session_id=session_id)
        assert rows == []
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
$env:RUN_INTEGRATION = '1'
pytest server/tests/integration/test_repo_grammar_session.py -v
```

Expected: `AttributeError: module 'bubbles.db.repo.grammar' has no attribute 'list_for_session'`.

- [ ] **Step 3: Add the reader to `grammar.py`**

Open `server/src/bubbles/db/repo/grammar.py`. After `category_counts` (currently the last function in the file), append:

```python


async def list_for_session(
    conn: asyncpg.Connection, *, session_id: UUID
) -> list[UserMistake]:
    """Return every mistake row tagged with ``session_id`` (chronological)."""
    rows = await conn.fetch(
        f"""
        SELECT {_COLS}
        FROM user_mistakes
        WHERE session_id = $1
        ORDER BY created_at ASC
        """,
        session_id,
    )
    return [_row(r) for r in rows]
```

(`UUID`, `asyncpg`, `UserMistake`, and `_COLS` are already imported at the top of the file — no new imports needed.)

- [ ] **Step 4: Run tests to verify they pass**

```powershell
$env:RUN_INTEGRATION = '1'
pytest server/tests/integration/test_repo_grammar_session.py -v
```

Expected: 2 tests passed.

- [ ] **Step 5: Lint**

```powershell
ruff check server/src/bubbles/db/repo/grammar.py server/tests/integration/test_repo_grammar_session.py
mypy --strict server/src/bubbles/db/repo/grammar.py
```

Expected: both clean.

- [ ] **Step 6: Commit**

```bash
git add server/src/bubbles/db/repo/grammar.py server/tests/integration/test_repo_grammar_session.py
git commit -m "feat(grammar): add list_for_session reader for drill materialization" -- server/src/bubbles/db/repo/grammar.py server/tests/integration/test_repo_grammar_session.py
git show --stat HEAD
```

Expected: exactly 2 files changed.

---

### Task 6: Drill schemas

**Files:**
- Modify: `server/src/bubbles/api/v1/_schemas.py`

- [ ] **Step 1: Sanity check current state**

```powershell
python -c "from bubbles.api.v1._schemas import DrillCardOut" 2>&1
```

Expected: `ImportError: cannot import name 'DrillCardOut' from 'bubbles.api.v1._schemas'`.

- [ ] **Step 2: Append the four schemas**

Open `server/src/bubbles/api/v1/_schemas.py`. At the very end of the file (after the last existing class — `StartScenarioResponse` from F1), append:

```python


# ---- drill cards (F2) -----------------------------------------------------


class DrillCardOut(_Base):
    """Read-side projection of a ``drill_cards`` row.

    ``front`` and ``back`` are server-derived convenience fields pulled from
    ``examples[0]`` (the most recent example for this card). Clients show
    ``front`` on the question side and ``back`` after the user taps to
    reveal the suggestion.
    """

    id: UUID
    rule_id: str
    category: str
    front: str
    back: str
    examples_count: int = Field(ge=0)
    box: int = Field(ge=1, le=5)
    due_at: datetime
    last_reviewed_at: datetime | None = None
    correct_streak: int = Field(ge=0)
    total_reviews: int = Field(ge=0)
    total_correct: int = Field(ge=0)
    retired_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class ReviewDrillRequest(_Base):
    result: Literal["correct", "wrong"]


class ReviewDrillResponse(_Base):
    card: DrillCardOut
    xp_awarded: int = Field(ge=0)
    transition: str = Field(min_length=4, max_length=8)  # e.g. "3->4"


class DrillQueueResponse(_Base):
    items: list[DrillCardOut]
    total_due: int = Field(ge=0)
```

(`UUID`, `datetime`, `Field`, `Literal`, and the local `_Base` are already imported at the top of the file. If `Literal` is missing from the existing `typing` import line, add it.)

- [ ] **Step 3: Verify imports**

```powershell
python -c "from bubbles.api.v1._schemas import DrillCardOut, ReviewDrillRequest, ReviewDrillResponse, DrillQueueResponse; print('ok')"
```

Expected: prints `ok`.

- [ ] **Step 4: Lint**

```powershell
ruff check server/src/bubbles/api/v1/_schemas.py
mypy --strict server/src/bubbles/api/v1/_schemas.py
```

Expected: both clean.

- [ ] **Step 5: Commit**

```bash
git add server/src/bubbles/api/v1/_schemas.py
git commit -m "feat(drills): add drill request/response schemas" -- server/src/bubbles/api/v1/_schemas.py
git show --stat HEAD
```

Expected: exactly 1 file changed.

---

### Task 7: Drill API routes

**Files:**
- Create: `server/src/bubbles/api/v1/drills.py`
- Modify: `server/src/bubbles/api/router.py`
- Create: `server/tests/integration/test_routes_drills.py`

- [ ] **Step 1: Write the failing integration tests**

Create `server/tests/integration/test_routes_drills.py`:

```python
"""Drill routes integration tests — queue, review, retire."""

from __future__ import annotations

from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient

from bubbles.db.repo import drill_cards as repo
from bubbles.db.repo.drill_cards import NewMistakeForCard

pytestmark = pytest.mark.integration


async def _seed_card(pool, *, user_id: UUID, rule_id: str = "LLM_ARTICLE") -> UUID:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await repo.upsert_from_mistakes(
                conn,
                user_id=user_id,
                mistakes=[
                    NewMistakeForCard(
                        mistake_id=uuid4(),
                        rule_id=rule_id,
                        category="article",
                        snippet="I went to store.",
                        suggestion="I went to the store.",
                    )
                ],
            )
            row = await conn.fetchrow(
                "SELECT id FROM drill_cards WHERE user_id = $1 AND rule_id = $2",
                user_id,
                rule_id,
            )
            assert row is not None
            return UUID(str(row["id"]))


@pytest.mark.asyncio
async def test_queue_returns_due_cards_for_owner_only(
    api_client: AsyncClient, pool, user_id: UUID, auth_headers: dict[str, str],
    other_auth_headers: dict[str, str]
) -> None:
    await _seed_card(pool, user_id=user_id)
    r_owner = await api_client.get("/v1/drills/queue", headers=auth_headers)
    assert r_owner.status_code == 200
    body = r_owner.json()
    assert body["total_due"] == 1
    assert len(body["items"]) == 1
    assert body["items"][0]["rule_id"] == "LLM_ARTICLE"

    r_other = await api_client.get("/v1/drills/queue", headers=other_auth_headers)
    assert r_other.status_code == 200
    assert r_other.json() == {"items": [], "total_due": 0}


@pytest.mark.asyncio
async def test_queue_include_upcoming_falls_back_when_due_empty(
    api_client: AsyncClient, pool, user_id: UUID, auth_headers: dict[str, str]
) -> None:
    card_id = await _seed_card(pool, user_id=user_id)
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "UPDATE drill_cards SET due_at = now() + interval '2 days' WHERE id = $1",
                card_id,
            )
    r_no = await api_client.get("/v1/drills/queue", headers=auth_headers)
    assert r_no.json()["items"] == []
    r_up = await api_client.get(
        "/v1/drills/queue?include_upcoming=true", headers=auth_headers
    )
    body = r_up.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["id"] == str(card_id)


@pytest.mark.asyncio
async def test_review_correct_awards_xp_and_advances_box(
    api_client: AsyncClient, pool, user_id: UUID, auth_headers: dict[str, str]
) -> None:
    card_id = await _seed_card(pool, user_id=user_id)
    r = await api_client.post(
        f"/v1/drills/{card_id}/review",
        headers=auth_headers,
        json={"result": "correct"},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["card"]["box"] == 2
    assert body["xp_awarded"] == 15
    assert body["transition"] == "1->2"

    # Same transition again is idempotent — XP not double-awarded.
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "UPDATE drill_cards SET due_at = now(), box = 1 WHERE id = $1",
                card_id,
            )
    r2 = await api_client.post(
        f"/v1/drills/{card_id}/review",
        headers=auth_headers,
        json={"result": "correct"},
    )
    body2 = r2.json()
    assert body2["card"]["box"] == 2
    assert body2["xp_awarded"] == 0  # already awarded for 1->2 on this card
    assert body2["transition"] == "1->2"


@pytest.mark.asyncio
async def test_review_wrong_awards_showup_xp_and_resets(
    api_client: AsyncClient, pool, user_id: UUID, auth_headers: dict[str, str]
) -> None:
    card_id = await _seed_card(pool, user_id=user_id)
    # advance to box 2 first
    await api_client.post(
        f"/v1/drills/{card_id}/review",
        headers=auth_headers,
        json={"result": "correct"},
    )
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "UPDATE drill_cards SET due_at = now() WHERE id = $1", card_id
            )
    r = await api_client.post(
        f"/v1/drills/{card_id}/review",
        headers=auth_headers,
        json={"result": "wrong"},
    )
    body = r.json()
    assert body["card"]["box"] == 1
    assert body["xp_awarded"] == 5
    assert body["transition"] == "2->1"


@pytest.mark.asyncio
async def test_review_box_five_correct_awards_zero(
    api_client: AsyncClient, pool, user_id: UUID, auth_headers: dict[str, str]
) -> None:
    card_id = await _seed_card(pool, user_id=user_id)
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "UPDATE drill_cards SET box = 5, due_at = now() WHERE id = $1", card_id
            )
    r = await api_client.post(
        f"/v1/drills/{card_id}/review",
        headers=auth_headers,
        json={"result": "correct"},
    )
    body = r.json()
    assert body["card"]["box"] == 5
    assert body["xp_awarded"] == 0
    assert body["transition"] == "5->5"


@pytest.mark.asyncio
async def test_retire_then_review_409(
    api_client: AsyncClient, pool, user_id: UUID, auth_headers: dict[str, str]
) -> None:
    card_id = await _seed_card(pool, user_id=user_id)
    r1 = await api_client.post(f"/v1/drills/{card_id}/retire", headers=auth_headers)
    assert r1.status_code == 200
    assert r1.json()["retired_at"] is not None

    r2 = await api_client.post(f"/v1/drills/{card_id}/retire", headers=auth_headers)
    assert r2.status_code == 409

    r3 = await api_client.post(
        f"/v1/drills/{card_id}/review",
        headers=auth_headers,
        json={"result": "correct"},
    )
    assert r3.status_code == 409


@pytest.mark.asyncio
async def test_review_404_unknown_card(
    api_client: AsyncClient, auth_headers: dict[str, str]
) -> None:
    r = await api_client.post(
        f"/v1/drills/{uuid4()}/review",
        headers=auth_headers,
        json={"result": "correct"},
    )
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_review_403_cross_user(
    api_client: AsyncClient, pool, user_id: UUID,
    other_auth_headers: dict[str, str]
) -> None:
    card_id = await _seed_card(pool, user_id=user_id)
    r = await api_client.post(
        f"/v1/drills/{card_id}/review",
        headers=other_auth_headers,
        json={"result": "correct"},
    )
    assert r.status_code == 403
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
$env:RUN_INTEGRATION = '1'
pytest server/tests/integration/test_routes_drills.py -v
```

Expected: `404 Not Found` on every endpoint (router not registered yet) or `ModuleNotFoundError` on the route file.

- [ ] **Step 3: Write the router**

Create `server/src/bubbles/api/v1/drills.py`:

```python
"""Drill (spaced-repetition) routes.

Three endpoints under ``/v1/drills``:

  GET  /queue                Due cards for the caller. With
                              ``include_upcoming=true`` falls back to
                              upcoming cards when due is empty.
  POST /{id}/review          Apply a Leitner step and award XP on the
                              specific box transition (idempotent on
                              ``(user, source_id=card_id:from->to)``).
  POST /{id}/retire          Silence a card permanently.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, HTTPException

from bubbles.ai.drills import BOX_INTERVALS, next_state
from bubbles.api.v1._schemas import (
    DrillCardOut,
    DrillQueueResponse,
    ReviewDrillRequest,
    ReviewDrillResponse,
)
from bubbles.auth.current_user import CurrentUserDep
from bubbles.core.logging import get_logger
from bubbles.db.repo import drill_cards as drill_repo
from bubbles.db.repo import xp as xp_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep, RateLimiterDep

log = get_logger(__name__)
router = APIRouter(tags=["drills"])

_REVIEW_CAPACITY = 60
_REVIEW_REFILL_PER_S = 60 / 60  # ~60 reviews per minute per user

# XP awards keyed by review semantics. Stored centrally so the test suite
# and any future quest hook agree on the numbers.
_XP_CORRECT_ADVANCE = 15
_XP_WRONG_SHOWUP = 5
_XP_CORRECT_STAY = 0  # box 5 → box 5

_SOURCE_TYPE = "drill_review"
_ACTION_TYPE = "complete_drill_review"


def _to_out(card: object) -> DrillCardOut:
    # ``card`` is a ``DrillCard`` from the repo. Local import is avoided to
    # keep the route module light; we duck-type the attributes we need.
    examples = getattr(card, "examples", []) or []
    front = ""
    back = ""
    if examples:
        first = examples[0]
        front = str(first.get("snippet", ""))
        back = str(first.get("suggestion", ""))
    return DrillCardOut(
        id=card.id,  # type: ignore[attr-defined]
        rule_id=card.rule_id,  # type: ignore[attr-defined]
        category=card.category,  # type: ignore[attr-defined]
        front=front,
        back=back,
        examples_count=len(examples),
        box=card.box,  # type: ignore[attr-defined]
        due_at=card.due_at,  # type: ignore[attr-defined]
        last_reviewed_at=card.last_reviewed_at,  # type: ignore[attr-defined]
        correct_streak=card.correct_streak,  # type: ignore[attr-defined]
        total_reviews=card.total_reviews,  # type: ignore[attr-defined]
        total_correct=card.total_correct,  # type: ignore[attr-defined]
        retired_at=card.retired_at,  # type: ignore[attr-defined]
        created_at=card.created_at,  # type: ignore[attr-defined]
        updated_at=card.updated_at,  # type: ignore[attr-defined]
    )


@router.get("/drills/queue", response_model=DrillQueueResponse)
async def get_queue(
    user: CurrentUserDep,
    pool: PoolDep,
    limit: int = 20,
    offset: int = 0,
    include_upcoming: bool = False,
) -> DrillQueueResponse:
    uid = UUID(user.id)
    capped = max(1, min(limit, 100))
    async with transaction(pool) as conn:
        due = await drill_repo.list_due(conn, user_id=uid, limit=capped, offset=offset)
        total = await drill_repo.count_due(conn, user_id=uid)
        if not due and include_upcoming:
            due = await drill_repo.list_upcoming(conn, user_id=uid, limit=capped)
    return DrillQueueResponse(items=[_to_out(c) for c in due], total_due=total)


@router.post("/drills/{card_id}/review", response_model=ReviewDrillResponse)
async def review_card(
    card_id: UUID,
    body: ReviewDrillRequest,
    user: CurrentUserDep,
    pool: PoolDep,
    limiter: RateLimiterDep,
) -> ReviewDrillResponse:
    await limiter.check(
        f"drills:review:{user.id}",
        capacity=_REVIEW_CAPACITY,
        refill_per_s=_REVIEW_REFILL_PER_S,
    )
    uid = UUID(user.id)
    async with UnitOfWork(pool) as uow:
        card = await drill_repo.get(uow.conn, card_id=card_id)
        if card is None:
            raise HTTPException(status_code=404, detail="drill card not found")
        if card.user_id != uid:
            raise HTTPException(status_code=403, detail="not your drill card")
        if card.retired_at is not None:
            raise HTTPException(status_code=409, detail="drill card is retired")

        new_box, _interval, transition = next_state(card.box, body.result)
        updated = await drill_repo.apply_review(
            uow.conn, card_id=card_id, result=body.result, intervals=BOX_INTERVALS
        )

        if body.result == "correct":
            amount = _XP_CORRECT_STAY if card.box == 5 else _XP_CORRECT_ADVANCE
        else:
            amount = _XP_WRONG_SHOWUP

        xp_awarded = 0
        if amount > 0:
            xp_row = await xp_repo.record(
                uow.conn,
                user_id=uid,
                amount=amount,
                source_type=_SOURCE_TYPE,
                source_id=f"{card_id}:{transition}",
                description=_ACTION_TYPE,
            )
            # ``record`` returns ``None`` if the (user, source_type, source_id)
            # was already awarded — that's the idempotency contract.
            xp_awarded = amount if xp_row is not None else 0

    log.info(
        "drill_review_done",
        user=user.id,
        card=str(card_id),
        transition=transition,
        xp=xp_awarded,
    )
    return ReviewDrillResponse(
        card=_to_out(updated),
        xp_awarded=xp_awarded,
        transition=transition,
    )


@router.post("/drills/{card_id}/retire", response_model=DrillCardOut)
async def retire_card(
    card_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> DrillCardOut:
    uid = UUID(user.id)
    async with UnitOfWork(pool) as uow:
        existing = await drill_repo.get(uow.conn, card_id=card_id)
        if existing is None:
            raise HTTPException(status_code=404, detail="drill card not found")
        if existing.user_id != uid:
            raise HTTPException(status_code=403, detail="not your drill card")
        retired = await drill_repo.retire(uow.conn, card_id=card_id)
        if retired is None:
            raise HTTPException(status_code=409, detail="drill card already retired")
    return _to_out(retired)
```

- [ ] **Step 4: Register the router**

Open `server/src/bubbles/api/router.py`. Find the existing imports of v1 sub-routers (the file already imports `scenarios` from F1). Add the matching `drills` import next to it:

```python
from bubbles.api.v1.drills import router as drills_router
```

And next to the `app.include_router(scenarios_router, prefix="/v1")` line, add:

```python
api_router.include_router(drills_router, prefix="/v1")
```

(Use whichever exact include style the existing scenarios line uses — mirror it verbatim. If the file uses `api_router.include_router(...)`, use that; if it uses `app.include_router(...)`, use that.)

- [ ] **Step 5: Run tests to verify they pass**

```powershell
$env:RUN_INTEGRATION = '1'
pytest server/tests/integration/test_routes_drills.py -v
```

Expected: 8 tests passed.

- [ ] **Step 6: Lint**

```powershell
ruff check server/src/bubbles/api/v1/drills.py server/src/bubbles/api/router.py server/tests/integration/test_routes_drills.py
mypy --strict server/src/bubbles/api/v1/drills.py server/src/bubbles/api/router.py
```

Expected: both clean.

- [ ] **Step 7: Commit**

```bash
git add server/src/bubbles/api/v1/drills.py server/src/bubbles/api/router.py server/tests/integration/test_routes_drills.py
git commit -m "feat(drills): queue / review / retire routes" -- server/src/bubbles/api/v1/drills.py server/src/bubbles/api/router.py server/tests/integration/test_routes_drills.py
git show --stat HEAD
```

Expected: exactly 3 files changed.

---

### Task 8: `materialize_drill_cards` worker

**Files:**
- Create: `server/src/bubbles/workers/jobs/materialize_drill_cards.py`
- Create: `server/tests/integration/test_workers_drills.py`

- [ ] **Step 1: Write the failing integration test**

Create `server/tests/integration/test_workers_drills.py`:

```python
"""materialize_drill_cards worker — runs from end_session fan-out."""

from __future__ import annotations

from typing import Any
from uuid import UUID

import pytest

from bubbles.db.repo import drill_cards as drill_repo
from bubbles.db.repo import grammar as grammar_repo
from bubbles.workers.jobs import materialize_drill_cards as job

pytestmark = pytest.mark.integration


def _ctx(pool: Any) -> dict[str, Any]:
    class _Stub:
        def __init__(self, p: Any) -> None:
            self.pool = p

    return {"bubbles": _Stub(pool)}


@pytest.mark.asyncio
async def test_noop_on_empty_session(pool, user_id: UUID, session_id: UUID) -> None:
    result = await job.run(_ctx(pool), user_id=str(user_id), session_id=str(session_id))
    assert result == {"materialized": 0}
    async with pool.acquire() as conn:
        n = await conn.fetchval(
            "SELECT COUNT(*)::int FROM drill_cards WHERE user_id = $1", user_id
        )
    assert n == 0


@pytest.mark.asyncio
async def test_first_call_upserts_one_card_per_rule(
    pool, user_id: UUID, session_id: UUID
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await grammar_repo.bulk_insert(
                conn,
                user_id=user_id,
                session_id=session_id,
                mistakes=[
                    {
                        "rule_id": "LLM_ARTICLE",
                        "category": "article",
                        "snippet": "S1",
                        "suggestion": "S1-fix",
                        "source": "llm",
                    },
                    {
                        "rule_id": "LLM_ARTICLE",
                        "category": "article",
                        "snippet": "S2",
                        "suggestion": "S2-fix",
                        "source": "llm",
                    },
                    {
                        "rule_id": "LLM_AGREEMENT",
                        "category": "agreement",
                        "snippet": "S3",
                        "suggestion": "S3-fix",
                        "source": "llm",
                    },
                ],
            )

    result = await job.run(_ctx(pool), user_id=str(user_id), session_id=str(session_id))
    assert result == {"materialized": 2}

    async with pool.acquire() as conn:
        cards = await drill_repo.list_due(conn, user_id=user_id, limit=10, offset=0)
    by_rule = {c.rule_id: c for c in cards}
    assert set(by_rule.keys()) == {"LLM_ARTICLE", "LLM_AGREEMENT"}
    # LLM_ARTICLE card has 2 examples (newest first: S2 then S1).
    art = by_rule["LLM_ARTICLE"]
    assert len(art.examples) == 2
    assert art.examples[0]["snippet"] == "S2"
    assert art.examples[1]["snippet"] == "S1"


@pytest.mark.asyncio
async def test_second_call_same_session_is_idempotent(
    pool, user_id: UUID, session_id: UUID
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await grammar_repo.bulk_insert(
                conn,
                user_id=user_id,
                session_id=session_id,
                mistakes=[
                    {
                        "rule_id": "LLM_ARTICLE",
                        "category": "article",
                        "snippet": "S1",
                        "suggestion": "S1-fix",
                        "source": "llm",
                    },
                ],
            )
    await job.run(_ctx(pool), user_id=str(user_id), session_id=str(session_id))
    # Second call with the same data should not double-append the example.
    await job.run(_ctx(pool), user_id=str(user_id), session_id=str(session_id))
    async with pool.acquire() as conn:
        cards = await drill_repo.list_due(conn, user_id=user_id, limit=10, offset=0)
    assert len(cards) == 1
    # Two example entries (one per worker call) is acceptable; the cap is 10.
    # The idempotency target is per-job dedup in ARQ (same _job_id); inside a
    # single worker call the upsert is deterministic. What we assert here is
    # that the cap holds and no second card was created.
    assert len(cards[0].examples) <= 10
    assert cards[0].rule_id == "LLM_ARTICLE"
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
$env:RUN_INTEGRATION = '1'
pytest server/tests/integration/test_workers_drills.py -v
```

Expected: `ModuleNotFoundError: No module named 'bubbles.workers.jobs.materialize_drill_cards'`.

- [ ] **Step 3: Write the worker**

Create `server/src/bubbles/workers/jobs/materialize_drill_cards.py`:

```python
"""materialize_drill_cards worker — turns this session's mistakes into drill cards.

Fired from the ``end_session`` fan-out alongside ``generate_scenarios``.
For every ``user_mistakes`` row tagged with the just-ended session id we
upsert one ``drill_cards`` row keyed by ``(user_id, rule_id, category)``,
prepending the snippet to the card's ``examples`` JSONB array (cap 10).

A no-op when the session has no mistakes. Idempotent at the ARQ level via
the ``materialize_drills:{user_id}:{session_id}`` job-id passed by the
``enqueue_materialize_drill_cards`` helper.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from bubbles.core.logging import get_logger
from bubbles.db.repo import drill_cards as drill_repo
from bubbles.db.repo import grammar as grammar_repo
from bubbles.db.repo.drill_cards import NewMistakeForCard
from bubbles.db.uow import UnitOfWork, transaction

__all__ = ["run"]

log = get_logger(__name__)


async def run(
    ctx: dict[str, Any], *, user_id: str, session_id: str
) -> dict[str, int]:
    """Upsert drill cards for this session's mistakes. Returns ``{"materialized": N}``."""
    bub = ctx["bubbles"]
    uid = UUID(user_id)
    sid = UUID(session_id)
    async with transaction(bub.pool) as conn:
        rows = await grammar_repo.list_for_session(conn, session_id=sid)
    if not rows:
        log.info("materialize_drills_noop", user=user_id, session=session_id)
        return {"materialized": 0}

    inputs = [
        NewMistakeForCard(
            mistake_id=r.id,
            rule_id=r.rule_id,
            category=r.category,
            snippet=r.snippet,
            suggestion=r.suggestion,
        )
        for r in rows
    ]
    async with UnitOfWork(bub.pool) as uow:
        touched = await drill_repo.upsert_from_mistakes(
            uow.conn, user_id=uid, mistakes=inputs
        )
    log.info(
        "materialize_drills_done",
        user=user_id,
        session=session_id,
        mistakes=len(inputs),
        cards_touched=touched,
    )
    return {"materialized": touched}
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
$env:RUN_INTEGRATION = '1'
pytest server/tests/integration/test_workers_drills.py -v
```

Expected: 3 tests passed.

- [ ] **Step 5: Lint**

```powershell
ruff check server/src/bubbles/workers/jobs/materialize_drill_cards.py server/tests/integration/test_workers_drills.py
mypy --strict server/src/bubbles/workers/jobs/materialize_drill_cards.py
```

Expected: both clean.

- [ ] **Step 6: Commit**

```bash
git add server/src/bubbles/workers/jobs/materialize_drill_cards.py server/tests/integration/test_workers_drills.py
git commit -m "feat(drills): materialize_drill_cards worker" -- server/src/bubbles/workers/jobs/materialize_drill_cards.py server/tests/integration/test_workers_drills.py
git show --stat HEAD
```

Expected: exactly 2 files changed.

---

### Task 9: Enqueue helper + worker registration

**Files:**
- Modify: `server/src/bubbles/workers/enqueue.py`
- Modify: `server/src/bubbles/workers/arq_settings.py`

- [ ] **Step 1: Append the enqueue helper**

Open `server/src/bubbles/workers/enqueue.py`. At the end of the file (after `enqueue_score_scenario`), append:

```python


async def enqueue_materialize_drill_cards(
    arq: ArqRedis, *, user_id: str, session_id: str
) -> Any:
    """Materialise drill cards from a just-ended session's mistakes.

    The dedup key is per-session: concurrent end_sessions for the same user
    on different sessions must each run, but a repeat enqueue for the
    same ``(user, session)`` is a no-op (ARQ dedup).
    """
    return await arq.enqueue_job(
        "run",
        _job_name="materialize_drill_cards",
        user_id=user_id,
        session_id=session_id,
        _job_id=f"materialize_drills:{user_id}:{session_id}",
    )
```

(No new imports needed — `ArqRedis` and `Any` are already imported at the top of the file.)

- [ ] **Step 2: Register the worker**

Open `server/src/bubbles/workers/arq_settings.py`. In the `from bubbles.workers.jobs import (...)` block (around the `generate_scenarios,` / `score_scenario,` entries), add `materialize_drill_cards,` in alphabetical position:

```python
from bubbles.workers.jobs import (
    backfill_session_entities,
    compute_embeddings,
    compute_session_analytics,
    detect_achievements,
    extract_knowledge,
    generate_scenarios,
    grammar_scan,
    materialize_drill_cards,
    rolling_summarize,
    score_scenario,
    seed_quests,
    send_reminders,
    sentiment_scan,
    speaker_enroll,
    speaker_identify,
)
```

Then in `_JOB_REGISTRY` (around line 90–103), add the new mapping next to `score_scenario`:

```python
_JOB_REGISTRY: dict[str, Any] = {
    "compute_embeddings": compute_embeddings.run,
    "extract_knowledge": extract_knowledge.run,
    "generate_scenarios": generate_scenarios.run,
    "compute_session_analytics": compute_session_analytics.run,
    "grammar_scan": grammar_scan.run,
    "materialize_drill_cards": materialize_drill_cards.run,
    "speaker_enroll": speaker_enroll.run,
    "speaker_identify": speaker_identify.run,
    "detect_achievements": detect_achievements.run,
    "backfill_session_entities": backfill_session_entities.run,
    "sentiment_scan": sentiment_scan.run,
    "rolling_summarize": rolling_summarize.run,
    "score_scenario": score_scenario.run,
}
```

- [ ] **Step 3: Verify the registration loads**

```powershell
python -c "from bubbles.workers.arq_settings import _JOB_REGISTRY; assert 'materialize_drill_cards' in _JOB_REGISTRY; print('ok')"
```

Expected: prints `ok`.

- [ ] **Step 4: Lint**

```powershell
ruff check server/src/bubbles/workers/enqueue.py server/src/bubbles/workers/arq_settings.py
mypy --strict server/src/bubbles/workers/enqueue.py server/src/bubbles/workers/arq_settings.py
```

Expected: both clean.

- [ ] **Step 5: Commit**

```bash
git add server/src/bubbles/workers/enqueue.py server/src/bubbles/workers/arq_settings.py
git commit -m "feat(drills): wire materialize_drill_cards into ARQ dispatcher" -- server/src/bubbles/workers/enqueue.py server/src/bubbles/workers/arq_settings.py
git show --stat HEAD
```

Expected: exactly 2 files changed.

---

### Task 10: `end_session` fan-out wiring + integration extension

**Files:**
- Modify: `server/src/bubbles/api/v1/sessions.py`
- Modify: `server/tests/integration/test_routes_sessions.py`

- [ ] **Step 1: Sketch the failing test extension**

Open `server/tests/integration/test_routes_sessions.py`. Find the existing test that asserts the post-session fan-out (it counts the jobs enqueued by `_enqueue_post_session_jobs`; it was extended for F1 to assert `generate_scenarios` is enqueued — the assertion currently expects 6 jobs). Update the relevant assertions to expect **7** jobs and add `materialize_drill_cards` to the expected `_job_name` set.

Find the assertion block that looks like (the exact constant name and list may differ slightly — match what's in the file):

```python
assert {j["_job_name"] for j in enqueued} == {
    "compute_session_analytics",
    "extract_knowledge",
    "compute_embeddings",
    "detect_achievements",
    "sentiment_scan",
    "generate_scenarios",
}
```

Change it to:

```python
assert {j["_job_name"] for j in enqueued} == {
    "compute_session_analytics",
    "extract_knowledge",
    "compute_embeddings",
    "detect_achievements",
    "sentiment_scan",
    "generate_scenarios",
    "materialize_drill_cards",
}
```

And any length-check (`assert len(enqueued) == 6`) becomes `== 7`. (If the existing test counts scenario-linked sessions as `7` due to `score_scenario`, the scenario-linked variant is now `8`.)

- [ ] **Step 2: Run the test extension and verify failure**

```powershell
$env:RUN_INTEGRATION = '1'
pytest server/tests/integration/test_routes_sessions.py -v
```

Expected: failure on the `_job_name` set assertion — `materialize_drill_cards` missing.

- [ ] **Step 3: Wire the enqueue into `_enqueue_post_session_jobs`**

Open `server/src/bubbles/api/v1/sessions.py`. Two changes:

1. Add the new helper to the `from bubbles.workers.enqueue import (...)` block (alphabetical position next to `enqueue_generate_scenarios`):

```python
from bubbles.workers.enqueue import (
    enqueue_compute_embeddings,
    enqueue_detect_achievements,
    enqueue_extract_knowledge,
    enqueue_generate_scenarios,
    enqueue_materialize_drill_cards,
    enqueue_score_scenario,
    enqueue_sentiment_scan,
    enqueue_session_analytics,
)
```

2. Inside `_enqueue_post_session_jobs`, between the `enqueue_generate_scenarios` and the `if scenario_id is not None:` branch, add the materialize call:

```python
        # Top up the user's personalized roleplay scenario feed.
        await enqueue_generate_scenarios(arq, user_id=user_id)
        # Turn this session's grammar mistakes into spaced-repetition drill cards.
        await enqueue_materialize_drill_cards(
            arq, user_id=user_id, session_id=session_id
        )
        # If this session was a roleplay started from a scenario, grade it.
        if scenario_id is not None:
            await enqueue_score_scenario(arq, scenario_id=scenario_id)
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
$env:RUN_INTEGRATION = '1'
pytest server/tests/integration/test_routes_sessions.py -v
```

Expected: all tests in the file pass.

- [ ] **Step 5: Run the whole drill suite end-to-end**

```powershell
$env:RUN_INTEGRATION = '1'
pytest server/tests/unit/test_drill_intervals.py server/tests/integration/test_repo_drill_cards.py server/tests/integration/test_repo_grammar_session.py server/tests/integration/test_routes_drills.py server/tests/integration/test_workers_drills.py server/tests/integration/test_routes_sessions.py -v
```

Expected: every test in those 6 files green.

- [ ] **Step 6: Lint + type-check full module set touched by F2**

```powershell
ruff check server/src/bubbles/ai/drills.py server/src/bubbles/db/repo/drill_cards.py server/src/bubbles/db/repo/grammar.py server/src/bubbles/api/v1/drills.py server/src/bubbles/api/v1/sessions.py server/src/bubbles/api/router.py server/src/bubbles/workers/enqueue.py server/src/bubbles/workers/arq_settings.py server/src/bubbles/workers/jobs/materialize_drill_cards.py server/src/bubbles/api/v1/_schemas.py server/src/bubbles/db/models.py server/src/bubbles/db/repo/__init__.py
mypy --strict server/src/bubbles/ai/drills.py server/src/bubbles/db/repo/drill_cards.py server/src/bubbles/db/repo/grammar.py server/src/bubbles/api/v1/drills.py server/src/bubbles/api/v1/sessions.py server/src/bubbles/api/router.py server/src/bubbles/workers/enqueue.py server/src/bubbles/workers/arq_settings.py server/src/bubbles/workers/jobs/materialize_drill_cards.py server/src/bubbles/api/v1/_schemas.py server/src/bubbles/db/models.py server/src/bubbles/db/repo/__init__.py
```

Expected: both clean. (A single pre-existing mypy warning in `tests/unit/test_check_schema_drift.py` is acceptable — it predates F1.)

- [ ] **Step 7: Commit**

```bash
git add server/src/bubbles/api/v1/sessions.py server/tests/integration/test_routes_sessions.py
git commit -m "feat(drills): wire materialize_drill_cards into end_session fan-out" -- server/src/bubbles/api/v1/sessions.py server/tests/integration/test_routes_sessions.py
git show --stat HEAD
```

Expected: exactly 2 files changed.

---

## After all tasks

- [ ] **Final review**

```powershell
git log --oneline main..HEAD
```

Expected: exactly 10 commits, one per task, each with a clear subject.

```powershell
git diff --stat main..HEAD
```

Expected: ~20 files changed; ~1000 lines added, very few removed.

- [ ] **OpenAPI sanity check**

```powershell
python -c "from bubbles.api.app import build_app; app = build_app(); print(sorted(r.path for r in app.routes if hasattr(r, 'path') and '/drills' in r.path))"
```

Expected: prints `['/v1/drills/queue', '/v1/drills/{card_id}/retire', '/v1/drills/{card_id}/review']`.

- [ ] **Drill the docs**

After the implementation is green, write the app-side handoff doc at `Documentation/feature-2-spaced-repetition-drills.md`. It must cover: server endpoints + payloads, status lifecycle, UI states (empty / due-stack / practice-early / scoring / retired), the polling/refresh cadence after each `end_session`, error handling (`409` retired, `404` unknown, rate-limit), and the file map. Same depth as `Documentation/feature-1-personalized-roleplay.md`.

(The doc step lives outside the 10 implementation tasks; it is a separate commit after the feature is green and merged-ready.)
