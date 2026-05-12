# v5 Port — Batch 1: Entity Routes

**Date:** 2026-05-11 • **Owner:** Backend • **Status:** Approved (brainstorm)

## Context

`server_v2/` has been retired to `legacy/server_v2/`; `server/` (Bubbles Brain API v5) is the
sole backend. v5 is a leaner async rewrite and did **not** carry over the full v2 HTTP surface.
The missing surface is being ported back in batches, easiest first, **improving the logic as we
go** (per the directive: don't 1:1-copy v2's hacks). This is Batch 1 of 6:

1. **Entity routes** ← this spec
2. Gamification HTTP routes
3. Analytics read endpoints + `save_feedback`
4. `performance_summary`
5. Speaker `enroll` / `identify_speaker` HTTP routes
6. `process_transcript_wingman`

Each batch gets its own spec → plan → implementation cycle. After all 6, update
`Documentation/server-vs-server_v2-review.md` §5 to reflect the real state.

## Goal

Bring v5 to parity (or better) with v2's entity-related HTTP endpoints:

| Method | Path | v2 status | v5 today |
|---|---|---|---|
| `GET`    | `/v1/graph_export/{user_id}`     | exists (raw SQL, no ownership check) | **missing** |
| `GET`    | `/v1/entity_timeline/{entity_id}` | exists (heuristic; `?user_id=` ownership) | stub repo method only, no route |
| `DELETE` | `/v1/sessions/{session_id}`       | exists (hard delete) | **missing** |
| `DELETE` | `/v1/memories/{memory_id}`        | exists (hard delete) | **missing** |
| `DELETE` | `/v1/entities/{entity_id}`        | exists | ✅ already in v5 (`soft_delete`) — no change |

## Improvements over v2 (the point of the rewrite)

1. **Ownership from the JWT, not from a path/query param.** v2's `graph_export/{user_id}` had no
   ownership check at all, and `entity_timeline` trusted a `?user_id=` query param. v5 uses
   `require_ownership(user, owner_id)` against the authenticated principal; the `{user_id}` path
   segment on `graph_export` is kept for URL compatibility but validated to equal the caller.
2. **Real session↔entity links** instead of v2's single `sessions.target_entity_id` column plus
   `events/tasks WHERE title ILIKE %name%`. New `session_entities` link table, populated by the
   `extract_knowledge` worker each time it extracts entities from a session transcript.
3. **Soft delete everywhere** (`sessions.deleted_at`, `memory.is_archived`, `entities.is_archived`)
   — recoverable, and consistent with v5's existing `delete_entity`. v2 hard-`DELETE`d rows.
4. **Pagination / caps.** `graph_export` accepts `?limit` (default 300, hard cap 1000), returns the
   top-N entities by `mention_count desc`, and drops relation links whose endpoints aren't in the
   returned node set. v2 returned the entire graph unbounded.
5. **Repo + Unit-of-Work + typed errors** instead of `asyncio.to_thread(lambda: db.table(...))` and
   bare `HTTPException` inside route handlers. Pydantic response models for every endpoint.
6. **Fuzzy matches are labelled.** `events`/`tasks` have no entity FK in the schema, so the
   timeline still name-matches them — but each such row carries `"match": "name"` so the client
   knows it's a heuristic, not a tracked link. Sessions carry `"match": "link"`.

## Schema change

`alembic/versions/2026_05_11_0002_session_entities.py` (revision `0002`, down-revision `0001`):

```sql
CREATE TABLE session_entities (
    session_id    uuid        NOT NULL REFERENCES sessions(id)  ON DELETE CASCADE,
    entity_id     uuid        NOT NULL REFERENCES entities(id)  ON DELETE CASCADE,
    user_id       uuid        NOT NULL,
    mention_count integer     NOT NULL DEFAULT 1,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (session_id, entity_id)
);
CREATE INDEX session_entities_entity_idx ON session_entities (entity_id, last_seen_at DESC);
CREATE INDEX session_entities_user_idx   ON session_entities (user_id, last_seen_at DESC);
```

`downgrade()` drops the indexes and the table. The table starts empty; old sessions are not
backfilled (follow-up: a one-off `backfill_session_entities` worker job — out of scope here).

## Components

### `db/repo/entities.py` (extend)
- `link_session_entity(conn, *, session_id, entity_id, user_id) -> None` — `INSERT ... ON CONFLICT
  (session_id, entity_id) DO UPDATE SET mention_count = session_entities.mention_count + 1,
  last_seen_at = now()`.
- `timeline(conn, *, entity_id, user_id, since=None, limit=50) -> list[Record]` — **rewrite** the
  bogus `JOIN sessions ON s.user_id = e.user_id`. New body:
  `FROM session_entities se JOIN sessions s ON s.id = se.session_id AND s.deleted_at IS NULL
   WHERE se.entity_id = $1 AND se.user_id = $2 AND ($3::timestamptz IS NULL OR se.last_seen_at >= $3)
   ORDER BY se.last_seen_at DESC LIMIT $4`.
- `events_mentioning(conn, *, user_id, name, limit=10) -> list[Record]` — `SELECT id, title,
  due_text, description, created_at FROM events WHERE user_id = $1 AND title ILIKE '%'||$2||'%'
  ORDER BY created_at DESC LIMIT $3`.
- `tasks_mentioning(conn, *, user_id, name, limit=10) -> list[Record]` — `SELECT id, title, status,
  priority, created_at FROM tasks WHERE user_id = $1 AND title ILIKE '%'||$2||'%' ORDER BY
  created_at DESC LIMIT $3`.
- `list_all_relations(conn, *, user_id, limit=2000) -> list[EntityRelation]` — all relations for a
  user, `ORDER BY strength DESC LIMIT $2` (used to build the graph's links).
- (`list_for_user`, `get_entity`, `soft_delete` already exist and are reused.)

### `db/repo/memories.py` (extend)
- `get(conn, memory_id) -> Memory | None` — `SELECT {_COLS} FROM memory WHERE id = $1` (no
  `is_archived` filter — we need to detect already-archived to return 404). `soft_delete` exists.

### `db/repo/sessions.py`
- No change — `soft_delete(conn, *, session_id, user_id) -> bool` already exists.

### `workers/jobs/extract_knowledge.py` (extend)
- Inside the existing `UnitOfWork` loop, after `upsert_entity` returns `entity`, call
  `await entities_repo.link_session_entity(uow.conn, session_id=UUID(session_id),
  entity_id=entity.id, user_id=user_uuid)`. Add the link count to the returned dict and log line.

### `api/v1/_schemas.py` (extend)
```python
class GraphNode(BaseModel):
    id: UUID; label: str; type: str
    description: str | None = None; mention_count: int = 0
    last_seen_at: datetime | None = None

class GraphLink(BaseModel):
    source: UUID; target: UUID; relation: str; strength: float

class GraphExportResponse(BaseModel):
    user_id: UUID; nodes: list[GraphNode]; links: list[GraphLink]

class TimelineSession(BaseModel):
    session_id: UUID; title: str | None; created_at: datetime
    match: Literal["link"] = "link"

class TimelineEvent(BaseModel):
    id: UUID; title: str; due_text: str | None = None
    description: str | None = None; created_at: datetime
    match: Literal["name"] = "name"

class TimelineTask(BaseModel):
    id: UUID; title: str; status: str | None = None
    priority: str | None = None; created_at: datetime
    match: Literal["name"] = "name"

class EntityTimelineResponse(BaseModel):
    entity_id: UUID; entity_name: str
    sessions: list[TimelineSession]
    events: list[TimelineEvent]
    tasks: list[TimelineTask]
```

### `api/v1/entities.py` (extend)
- `GET /graph_export/{user_id}` — `require_ownership(user, str(user_id))`; query params
  `limit: int = Query(300, ge=1, le=1000)`, `entity_type: str | None = None`,
  `include_archived: bool = False`. Loads entities (filtered) + `list_all_relations`, builds the
  node id set, filters links to that set, returns `GraphExportResponse`. (`list_for_user` already
  excludes archived; if `include_archived` is true, use a small variant query — add
  `list_for_user(..., include_archived: bool = False)` param rather than a second method.)
- `GET /entity_timeline/{entity_id}` — `entity = entities_repo.get_entity(...)`; `if None: raise
  NotFound`; `require_ownership(user, str(entity.user_id))`; query `limit: int = Query(50, ge=1,
  le=200)`, `since: datetime | None = None`. Fans out: `timeline(...)`, `events_mentioning(...,
  name=entity.display_name or entity.canonical_name)`, `tasks_mentioning(...)`. Returns
  `EntityTimelineResponse`.

### `api/v1/sessions.py` (extend)
- `DELETE /sessions/{session_id}` — `sess = sessions_repo.get(...)`; `if None: raise NotFound`;
  `require_ownership(user, str(sess.user_id))`; `ok = sessions_repo.soft_delete(...)`; `if not ok:
  raise NotFound`; `return Response(status_code=204)`. (Mirrors the existing `delete_entity`
  shape exactly.)

### `api/v1/memories.py` (new, ~35 lines)
- `router = APIRouter(tags=["memories"])`; `DELETE /memories/{memory_id}` — same pattern:
  `memories_repo.get` → `NotFound` → `require_ownership` → `memories_repo.soft_delete` → `NotFound`
  if `is_archived` already → 204.

### `api/v1/__init__.py`
- `v1_router.include_router(memories_router)` alongside the others.

## Behaviour / error contract

- Not found (no such id, or already soft-deleted) → `NotFound` → HTTP 404, body
  `{"error":{"code":"not_found","message":...,"request_id":...}}` (v5's standard envelope).
- Authenticated principal ≠ resource owner → `Forbidden` → HTTP 403.
- Successful DELETE → 204, empty body.
- `graph_export` for a user with no entities → 200, `{nodes: [], links: []}`.
- `entity_timeline` for an entity with no linked sessions and no name matches → 200, all three
  arrays empty, `entity_name` populated.
- DB down → existing `UpstreamUnavailable` → 503 + `Retry-After` (inherited from `PoolDep`).

## Testing

- **Repo unit tests** (`tests/unit/db/` or wherever v5 keeps them):
  - `link_session_entity` inserts then bumps `mention_count` / `last_seen_at` on conflict.
  - `timeline` returns only sessions linked via `session_entities`, newest first, honours `since`
    and `limit`, excludes `deleted_at IS NOT NULL` sessions.
  - `events_mentioning` / `tasks_mentioning` ILIKE behaviour (matches substring, case-insensitive).
  - `memories_repo.get` returns the row including when `is_archived = true`; `None` for unknown id.
  - `list_all_relations` ordering + limit.
- **Route tests** (against the v5 test harness / testcontainers PG):
  - `graph_export`: happy path with N entities + relations; dangling link dropped; `?limit` caps
    nodes; `?entity_type=` filters; `?include_archived=true` includes archived; 403 for another
    user's id; 200 empty for a fresh user.
  - `entity_timeline`: happy path with linked sessions + name-matched events/tasks; `match` tags
    correct; 404 for unknown entity; 403 for another user's entity; `?since` / `?limit` honoured.
  - `DELETE /sessions/{id}`: 204, then GET that session 404; second DELETE 404; 403 for other
    user's session; 404 for unknown id.
  - `DELETE /memories/{id}`: 204; second DELETE 404; 403 for other user's memory.
- **Worker test**: `extract_knowledge.run` creates `session_entities` rows for the extracted
  entities (extend the existing extract_knowledge test if there is one; otherwise add a focused one).
- `make test` (= `ruff` + `mypy --strict` + `pytest`) green. New migration applies and rolls back
  cleanly (`make migrate` then `alembic downgrade -1`).

## Out of scope

- Backfilling `session_entities` for sessions created before this change (separate worker job).
- A real entity↔event / entity↔task link (those tables have no entity FK; would need its own
  extraction change). Heuristic name-match retained and labelled.
- Touching `ask_entity` (already graph-aware in v5).
- Batches 2–6.

## Done when

All 4 endpoints respond with the shapes above; ownership enforced; migration in; `extract_knowledge`
writes links; full v5 quality gate green; `Documentation/server-vs-server_v2-review.md` §5 updated
to move the entity routes out of "gaps".
