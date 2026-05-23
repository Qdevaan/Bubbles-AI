# Live Confidence Meter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single `POST /v1/sessions/{session_id}/confidence` endpoint that bulk-updates the pre-existing `session_logs.confidence` column from a per-turn array the app posts at session end. No new table, no worker, no LLM call.

**Architecture:** Thinnest possible server-side feature. Three new schemas, one new repo function (`update_confidence_bulk`) using `UPDATE ... FROM unnest(...)`, one new route appended to the existing `api/v1/sessions.py`. Heuristic + meter UX live entirely in the app; server only persists.

**Tech Stack:** FastAPI, asyncpg (raw SQL), Pydantic v2, pytest + testcontainers Postgres.

**Spec:** `docs/superpowers/specs/2026-05-23-live-confidence-meter-design.md`.

---

## File Structure

| Path | Type | Responsibility |
|---|---|---|
| `server/src/bubbles/api/v1/_schemas.py` | Modify | Append 3 schemas: `TurnConfidenceItem`, `SetTurnConfidenceRequest`, `SetTurnConfidenceResponse`. |
| `server/src/bubbles/db/repo/session_logs.py` | Modify | Append `update_confidence_bulk(conn, *, session_id, items) -> int`. Single SQL using `unnest`. |
| `server/src/bubbles/api/v1/sessions.py` | Modify | Append `POST /sessions/{session_id}/confidence` route handler. |
| `server/tests/unit/test_routes_validation.py` | Modify | Append validation tests for the new request body. |
| `server/tests/integration/test_repo_session_logs_confidence.py` | Create | Repo behaviour: bulk update matches by `(session_id, turn_index)`, silently ignores unknown turn_index, returns count. |
| `server/tests/integration/test_routes_sessions_confidence.py` | Create | Route behaviour: 200 happy path, 403 cross-user, 404 unknown session, 400 bad body, 429 rate-limit, schema validates. |

---

## Notes for the implementer

- **No placeholders.** Every step produces complete, working code.
- **No `Co-Authored-By` trailer** on commits.
- **Explicit pathspec** on every commit: `git commit -m "..." -- <file1> <file2>`. Run `git show --stat HEAD` after each commit and verify the file list.
- **TDD.** Failing test first, then implementation, then green.
- **Integration tests need Docker.** Docker absent → integration tests skip at collection time. That is acceptable; complete static checks (`ruff`, `mypy --strict`, smoke import) and mark `DONE_WITH_CONCERNS`.
- **Branch:** `feat/confidence-meter` (already created from `main` after the F3 merge).
- **Patterns:**
  - Schemas subclass `_Base` (already in `_schemas.py`; sets `extra="forbid"`, `str_strip_whitespace=True`).
  - Routes use `CurrentUserDep` for auth, `PoolDep` + `UnitOfWork(pool)` for writes, `RateLimiterDep` for rate limits.
  - Rate-limit shape: `rl = await limiter.check(key, capacity=…, refill_per_s=…); if not rl.allowed: raise RateLimited(rl.retry_after_s)`.
  - Ownership: `require_ownership(user, str(session.user_id))` raises `Forbidden` on mismatch.
  - Repos use `(conn: asyncpg.Connection, *, …)` kw-only signatures.

---

## Tasks

### Task 1: Schemas + validation tests

**Files:**
- Modify: `server/src/bubbles/api/v1/_schemas.py`
- Modify: `server/tests/unit/test_routes_validation.py`

- [ ] **Step 1: Sanity-check current state**

```powershell
uv run python -c "from bubbles.api.v1._schemas import SetTurnConfidenceRequest" 2>&1
```

Expected: `ImportError: cannot import name 'SetTurnConfidenceRequest' from 'bubbles.api.v1._schemas'`.

- [ ] **Step 2: Append the schemas**

Open `server/src/bubbles/api/v1/_schemas.py`. At the very end of the file (after the F3 dashboard section), append:

```python


# ---- live confidence meter (F4) ------------------------------------------


class TurnConfidenceItem(_Base):
    """Per-turn confidence score posted by the app at session end."""

    turn_index: int = Field(ge=0)
    score: float = Field(ge=0.0, le=1.0)


class SetTurnConfidenceRequest(_Base):
    """Bulk array of per-turn confidence scores for one session."""

    confidence_by_turn: list[TurnConfidenceItem] = Field(min_length=1, max_length=500)


class SetTurnConfidenceResponse(_Base):
    """Reports how many session_logs rows were actually updated."""

    updated: int = Field(ge=0)
```

(`Field` and `_Base` are already imported at the top of the file. No new imports needed.)

- [ ] **Step 3: Append the validation tests**

Open `server/tests/unit/test_routes_validation.py`. At the end of the file, append:

```python


# ---- F4: confidence-meter request validation -----------------------------


async def _confidence_endpoint_returns(
    app: FastAPI, body: dict[str, object], expected_status: int
) -> int:
    """POST the confidence body to a dummy session id; return status code.

    The route requires auth + ownership. For pure body-shape validation the
    only thing under test is the 422 path returned by FastAPI's Pydantic
    layer BEFORE the auth dep runs. We don't override deps here — a 422 is
    what we expect for a malformed body regardless of auth.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/sessions/00000000-0000-0000-0000-000000000000/confidence",
            json=body,
        )
    return r.status_code


@pytest.mark.asyncio
async def test_set_turn_confidence_rejects_empty_list(app: FastAPI) -> None:
    code = await _confidence_endpoint_returns(
        app, {"confidence_by_turn": []}, expected_status=422
    )
    assert code == 422


@pytest.mark.asyncio
async def test_set_turn_confidence_rejects_score_above_one(app: FastAPI) -> None:
    code = await _confidence_endpoint_returns(
        app, {"confidence_by_turn": [{"turn_index": 0, "score": 1.5}]}, expected_status=422
    )
    assert code == 422


@pytest.mark.asyncio
async def test_set_turn_confidence_rejects_negative_score(app: FastAPI) -> None:
    code = await _confidence_endpoint_returns(
        app, {"confidence_by_turn": [{"turn_index": 0, "score": -0.1}]}, expected_status=422
    )
    assert code == 422


@pytest.mark.asyncio
async def test_set_turn_confidence_rejects_negative_turn_index(app: FastAPI) -> None:
    code = await _confidence_endpoint_returns(
        app, {"confidence_by_turn": [{"turn_index": -1, "score": 0.5}]}, expected_status=422
    )
    assert code == 422


@pytest.mark.asyncio
async def test_set_turn_confidence_rejects_unknown_field(app: FastAPI) -> None:
    code = await _confidence_endpoint_returns(
        app,
        {"confidence_by_turn": [{"turn_index": 0, "score": 0.5, "extra": 1}]},
        expected_status=422,
    )
    assert code == 422
```

(These tests will fail at first run because the route is not registered yet — FastAPI returns `404` instead of `422`. That's the expected red state for TDD. Step 4 of Task 3 will flip them to green once the route lands.)

- [ ] **Step 4: Verify schemas import**

```powershell
uv run python -c "from bubbles.api.v1._schemas import SetTurnConfidenceRequest, SetTurnConfidenceResponse, TurnConfidenceItem; print('ok')"
```

Expected: prints `ok`.

- [ ] **Step 5: Lint + type-check**

From `e:\FYP\FYP_V2\Bubbles-AI\server`:

```powershell
uv run ruff check src/bubbles/api/v1/_schemas.py tests/unit/test_routes_validation.py
uv run mypy --strict src/bubbles/api/v1/_schemas.py
```

Expected: both clean.

- [ ] **Step 6: Commit**

```bash
git add server/src/bubbles/api/v1/_schemas.py server/tests/unit/test_routes_validation.py
git commit -m "feat(confidence): add confidence-set schemas + validation tests" -- server/src/bubbles/api/v1/_schemas.py server/tests/unit/test_routes_validation.py
git show --stat HEAD
```

Expected: exactly 2 files changed.

---

### Task 2: Repo `update_confidence_bulk` + integration tests

**Files:**
- Modify: `server/src/bubbles/db/repo/session_logs.py`
- Create: `server/tests/integration/test_repo_session_logs_confidence.py`

- [ ] **Step 1: Write the failing integration test**

Create `server/tests/integration/test_repo_session_logs_confidence.py`:

```python
"""session_logs_repo.update_confidence_bulk integration tests."""

from __future__ import annotations

from uuid import UUID, uuid4

import pytest

from bubbles.db.repo import session_logs as session_logs_repo

pytestmark = pytest.mark.integration


async def _seed_log(conn, *, session_id: UUID, turn_index: int, role: str = "user") -> None:
    await conn.execute(
        """
        INSERT INTO session_logs (session_id, turn_index, role, content)
        VALUES ($1, $2, $3, 'x')
        """,
        session_id,
        turn_index,
        role,
    )


@pytest.mark.asyncio
async def test_update_confidence_bulk_updates_matching_turns(
    pool, session_id: UUID
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await _seed_log(conn, session_id=session_id, turn_index=0)
            await _seed_log(conn, session_id=session_id, turn_index=1)
            await _seed_log(conn, session_id=session_id, turn_index=2)
        async with conn.transaction():
            n = await session_logs_repo.update_confidence_bulk(
                conn,
                session_id=session_id,
                items=[(0, 0.9), (1, 0.5), (2, 0.1)],
            )
        rows = await conn.fetch(
            "SELECT turn_index, confidence FROM session_logs WHERE session_id = $1 "
            "ORDER BY turn_index",
            session_id,
        )
    assert n == 3
    assert [(r["turn_index"], float(r["confidence"])) for r in rows] == [
        (0, 0.9),
        (1, 0.5),
        (2, 0.1),
    ]


@pytest.mark.asyncio
async def test_update_confidence_bulk_silently_ignores_unknown_turn_index(
    pool, session_id: UUID
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await _seed_log(conn, session_id=session_id, turn_index=0)
        async with conn.transaction():
            n = await session_logs_repo.update_confidence_bulk(
                conn,
                session_id=session_id,
                items=[(0, 0.7), (99, 0.4)],  # turn 99 doesn't exist
            )
    # Only 1 row matched; the unknown turn_index is silently skipped.
    assert n == 1


@pytest.mark.asyncio
async def test_update_confidence_bulk_does_not_touch_other_sessions(
    pool, session_id: UUID, other_session_id: UUID
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await _seed_log(conn, session_id=session_id, turn_index=0)
            await _seed_log(conn, session_id=other_session_id, turn_index=0)
        async with conn.transaction():
            await session_logs_repo.update_confidence_bulk(
                conn,
                session_id=session_id,
                items=[(0, 0.95)],
            )
        own = await conn.fetchval(
            "SELECT confidence FROM session_logs WHERE session_id = $1 AND turn_index = 0",
            session_id,
        )
        other = await conn.fetchval(
            "SELECT confidence FROM session_logs WHERE session_id = $1 AND turn_index = 0",
            other_session_id,
        )
    assert float(own) == 0.95
    assert other is None


@pytest.mark.asyncio
async def test_update_confidence_bulk_empty_items_is_noop(
    pool, session_id: UUID
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await _seed_log(conn, session_id=session_id, turn_index=0)
        async with conn.transaction():
            n = await session_logs_repo.update_confidence_bulk(
                conn, session_id=session_id, items=[]
            )
    assert n == 0
```

- [ ] **Step 2: Run tests to verify they fail**

From `server/`:

```powershell
$env:RUN_INTEGRATION = '1'
uv run pytest tests/integration/test_repo_session_logs_confidence.py -v --no-cov
```

Expected: `AttributeError: module 'bubbles.db.repo.session_logs' has no attribute 'update_confidence_bulk'`. (Or skip on Docker absence.)

- [ ] **Step 3: Write the repo function**

Open `server/src/bubbles/db/repo/session_logs.py`. At the very end of the file (after the last existing function), append:

```python


async def update_confidence_bulk(
    conn: asyncpg.Connection,
    *,
    session_id: UUID,
    items: list[tuple[int, float]],
) -> int:
    """Bulk-update ``session_logs.confidence`` keyed by ``(session_id, turn_index)``.

    Rows whose ``turn_index`` does not match an existing log entry for
    this session are silently ignored. Returns the count of rows
    actually updated.
    """
    if not items:
        return 0
    turn_indexes = [t for t, _ in items]
    scores = [s for _, s in items]
    rows = await conn.fetch(
        """
        UPDATE session_logs sl
        SET confidence = data.score
        FROM unnest($1::int[], $2::numeric[]) AS data(turn_index, score)
        WHERE sl.session_id = $3
          AND sl.turn_index = data.turn_index
        RETURNING 1
        """,
        turn_indexes,
        scores,
        session_id,
    )
    return len(rows)
```

(`asyncpg` and `UUID` are already imported at the top of the file. No new imports.)

- [ ] **Step 4: Run tests to verify they pass**

```powershell
$env:RUN_INTEGRATION = '1'
uv run pytest tests/integration/test_repo_session_logs_confidence.py -v --no-cov
```

Expected: 4 tests passed (or skip on Docker absence).

- [ ] **Step 5: Lint + type-check**

```powershell
uv run ruff check src/bubbles/db/repo/session_logs.py tests/integration/test_repo_session_logs_confidence.py
uv run mypy --strict src/bubbles/db/repo/session_logs.py
```

Expected: both clean.

- [ ] **Step 6: Commit**

```bash
git add server/src/bubbles/db/repo/session_logs.py server/tests/integration/test_repo_session_logs_confidence.py
git commit -m "feat(confidence): add update_confidence_bulk repo function" -- server/src/bubbles/db/repo/session_logs.py server/tests/integration/test_repo_session_logs_confidence.py
git show --stat HEAD
```

Expected: exactly 2 files changed.

---

### Task 3: Confidence route + integration tests

**Files:**
- Modify: `server/src/bubbles/api/v1/sessions.py`
- Create: `server/tests/integration/test_routes_sessions_confidence.py`

- [ ] **Step 1: Write the failing integration tests**

Create `server/tests/integration/test_routes_sessions_confidence.py`:

```python
"""POST /v1/sessions/{id}/confidence integration tests."""

from __future__ import annotations

from uuid import UUID, uuid4

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import current_user
from bubbles.db.repo import sessions as sessions_repo
from bubbles.db.uow import UnitOfWork
from bubbles.deps import RateLimiterDep, get_pool
from bubbles.models.user import CurrentUser

pytestmark = pytest.mark.integration


class _FakeLimiter:
    async def check(self, key: str, *, capacity: int, refill_per_s: float) -> object:
        class _RL:
            allowed = True
            retry_after_s = 0.0

        return _RL()


class _BlockingLimiter:
    async def check(self, key: str, *, capacity: int, refill_per_s: float) -> object:
        class _RL:
            allowed = False
            retry_after_s = 5.0

        return _RL()


def _override(
    app: FastAPI, pool, uid: UUID, *, limiter: object | None = None
) -> None:
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email="t@t", roles=[]
    )
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[RateLimiterDep] = lambda: limiter or _FakeLimiter()


async def _seed_session(pool, *, user_id: UUID) -> UUID:
    async with UnitOfWork(pool) as uow:
        session = await sessions_repo.start(
            uow.conn, user_id=user_id, title="t", mode="live_wingman"
        )
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO session_logs (session_id, turn_index, role, content) VALUES ($1, 0, 'user', 'x')",
            session.id,
        )
        await conn.execute(
            "INSERT INTO session_logs (session_id, turn_index, role, content) VALUES ($1, 1, 'user', 'y')",
            session.id,
        )
    return session.id


@pytest.mark.asyncio
async def test_set_confidence_happy_path(
    app: FastAPI, pool, user_id: UUID
) -> None:
    sid = await _seed_session(pool, user_id=user_id)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/sessions/{sid}/confidence",
            json={
                "confidence_by_turn": [
                    {"turn_index": 0, "score": 0.8},
                    {"turn_index": 1, "score": 0.4},
                ]
            },
        )
    assert r.status_code == 200
    assert r.json() == {"updated": 2}

    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT turn_index, confidence FROM session_logs WHERE session_id = $1 "
            "ORDER BY turn_index",
            sid,
        )
    assert [(r["turn_index"], float(r["confidence"])) for r in rows] == [(0, 0.8), (1, 0.4)]


@pytest.mark.asyncio
async def test_set_confidence_404_unknown_session(
    app: FastAPI, pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/sessions/{uuid4()}/confidence",
            json={"confidence_by_turn": [{"turn_index": 0, "score": 0.5}]},
        )
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_set_confidence_403_cross_user(
    app: FastAPI, pool, user_id: UUID, other_user_id: UUID
) -> None:
    sid = await _seed_session(pool, user_id=other_user_id)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/sessions/{sid}/confidence",
            json={"confidence_by_turn": [{"turn_index": 0, "score": 0.5}]},
        )
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_set_confidence_429_rate_limited(
    app: FastAPI, pool, user_id: UUID
) -> None:
    sid = await _seed_session(pool, user_id=user_id)
    _override(app, pool, user_id, limiter=_BlockingLimiter())
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/sessions/{sid}/confidence",
            json={"confidence_by_turn": [{"turn_index": 0, "score": 0.5}]},
        )
    assert r.status_code == 429


@pytest.mark.asyncio
async def test_set_confidence_ignores_unknown_turn_index_still_200(
    app: FastAPI, pool, user_id: UUID
) -> None:
    sid = await _seed_session(pool, user_id=user_id)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            f"/v1/sessions/{sid}/confidence",
            json={
                "confidence_by_turn": [
                    {"turn_index": 0, "score": 0.7},
                    {"turn_index": 99, "score": 0.3},  # unknown turn
                ]
            },
        )
    assert r.status_code == 200
    assert r.json() == {"updated": 1}
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
$env:RUN_INTEGRATION = '1'
uv run pytest tests/integration/test_routes_sessions_confidence.py -v --no-cov
```

Expected: 404 on every test (route not yet registered) or skip on Docker absence.

- [ ] **Step 3: Wire the route**

Open `server/src/bubbles/api/v1/sessions.py`.

3a. Update the existing `from bubbles.api.v1._schemas import (...)` block to include the three new symbols. Find the existing imports block and add `SetTurnConfidenceRequest`, `SetTurnConfidenceResponse`, `TurnConfidenceItem` in alphabetical position:

```python
from bubbles.api.v1._schemas import (
    # … existing imports unchanged …
    SetTurnConfidenceRequest,
    SetTurnConfidenceResponse,
    # … existing imports unchanged …
)
```

(`TurnConfidenceItem` doesn't need to be imported at the route level — it's used only by Pydantic when validating the request body, accessed via `body.confidence_by_turn[i].turn_index` etc.)

3b. Update the `from bubbles.core.errors import …` block to include `RateLimited`. The block currently imports `NotFound`; append `, RateLimited`:

```python
from bubbles.core.errors import NotFound, RateLimited
```

3c. Update the `from bubbles.deps import …` block to include `RateLimiterDep`. The block likely imports `ArqDep, PoolDep` already; add `, RateLimiterDep`:

```python
from bubbles.deps import ArqDep, PoolDep, RateLimiterDep
```

(Read the existing line and add `RateLimiterDep` in alphabetical position relative to the other names on that line.)

3d. At the very END of the file (after `end_session`), append the new route handler:

```python


_CONFIDENCE_CAPACITY = 10
_CONFIDENCE_REFILL_PER_S = 10 / 60  # ~10 calls per minute per user


@router.post(
    "/sessions/{session_id}/confidence",
    response_model=SetTurnConfidenceResponse,
)
async def set_turn_confidence(
    session_id: UUID,
    body: SetTurnConfidenceRequest,
    user: CurrentUserDep,
    pool: PoolDep,
    limiter: RateLimiterDep,
) -> SetTurnConfidenceResponse:
    rl = await limiter.check(
        f"confidence:{user.id}",
        capacity=_CONFIDENCE_CAPACITY,
        refill_per_s=_CONFIDENCE_REFILL_PER_S,
    )
    if not rl.allowed:
        raise RateLimited(rl.retry_after_s)

    async with transaction(pool) as conn:
        existing = await sessions_repo.get(conn, session_id)
    if existing is None:
        raise NotFound("session not found")
    require_ownership(user, str(existing.user_id))

    items = [(item.turn_index, item.score) for item in body.confidence_by_turn]
    async with UnitOfWork(pool) as uow:
        updated = await session_logs_repo.update_confidence_bulk(
            uow.conn, session_id=session_id, items=items
        )

    log.info(
        "set_turn_confidence_done",
        user=user.id,
        session=str(session_id),
        sent=len(items),
        updated=updated,
    )
    return SetTurnConfidenceResponse(updated=updated)
```

(`UUID`, `transaction`, `UnitOfWork`, `session_logs_repo`, `sessions_repo`, `CurrentUserDep`, `require_ownership`, `log` are already imported at the top of `sessions.py`. Verify by reading the existing imports before saving.)

- [ ] **Step 4: Run tests to verify they pass**

```powershell
$env:RUN_INTEGRATION = '1'
uv run pytest tests/integration/test_routes_sessions_confidence.py -v --no-cov
```

Expected: 5 tests passed (or skip on Docker absence).

- [ ] **Step 5: Run the Task 1 validation tests too (they were red because the route didn't exist; now they must turn green)**

```powershell
uv run pytest tests/unit/test_routes_validation.py -v --no-cov -k confidence
```

Expected: 5 confidence validation tests pass (422 on every malformed body).

- [ ] **Step 6: OpenAPI smoke check**

```powershell
uv run python -c "from bubbles.api.app import build_app; app = build_app(); paths = sorted({getattr(r, 'path', '') for r in app.routes}); print([p for p in paths if 'confidence' in p])"
```

Expected: prints `['/v1/sessions/{session_id}/confidence']`.

- [ ] **Step 7: Lint + type-check**

```powershell
uv run ruff check src/bubbles/api/v1/sessions.py tests/integration/test_routes_sessions_confidence.py
uv run mypy --strict src/bubbles/api/v1/sessions.py
```

Expected: both clean.

- [ ] **Step 8: Commit**

```bash
git add server/src/bubbles/api/v1/sessions.py server/tests/integration/test_routes_sessions_confidence.py
git commit -m "feat(confidence): POST /v1/sessions/{id}/confidence route" -- server/src/bubbles/api/v1/sessions.py server/tests/integration/test_routes_sessions_confidence.py
git show --stat HEAD
```

Expected: exactly 2 files changed.

---

## After all tasks

- [ ] **Final review**

```powershell
git log --oneline main..HEAD
```

Expected: 4 commits — 1 spec + 3 implementation tasks.

```powershell
git diff --stat main..HEAD
```

Expected: ~7 files changed, ~600 lines added.

- [ ] **App-side doc**

After the implementation is green, write the app-side handoff doc at `Documentation/feature-4-live-confidence-meter.md`. Cover: the heuristic formula (fillers, hedges, weights, window, threshold colors), the single endpoint and its payload shape, when to call it (after `end_session` succeeds), error handling, UI states (meter colors, pause behavior, what happens on auth failure for the confidence POST), and the file map.

(The doc step lives outside the 3 implementation tasks; it is a separate commit after the feature is green and merge-ready.)
