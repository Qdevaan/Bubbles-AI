# Personalized Roleplay Scenarios — graph-generated practice

**Date:** 2026-05-22 • **Owner:** backend • **Type:** new feature (Feature 1 of 4) • **Ref:** brainstorming 2026-05-22

## Problem

Roleplay already works server-side: `wingman_context.build(mode="roleplay", target_entity_id=...)` (`src/bubbles/ai/wingman_context.py:131`) makes the LLM embody a known entity, and a session carries `session_context = {scenario, role_mode, notes}`. But the *scenario* is free text supplied by hand — there is no scenario library, and the user's own knowledge graph (entities, relations, `events`, `tasks`, populated by the `extract_knowledge` worker) is never used to produce practice material.

Roleplay is therefore generic. A user who wants to rehearse a real upcoming conversation — "ask my manager Sarah about the raise" — must write the setup themselves. The graph already holds the people, open tasks and recent events that would make that practice personal.

## Decision

A dedicated `scenarios` subsystem. Not folded into the quest / conversation-mission machinery: that path is XP-gated, its briefs depend on the unported `task_dispatcher` (shortcoming #3), and a browsable feed does not fit a model where quests are *assigned*.

Hybrid delivery, one shared generator (`ai/scenarios.py`):

- **Feed** — the `generate_scenarios` worker tops the user's feed up to a target of 5 `suggested` scenarios after each session ends. Self-throttling: a no-op when the feed is already full.
- **On-demand** — `POST /v1/scenarios/generate` produces one scenario for a chosen person synchronously (~1–3 s, rate-limited). A dedicated endpoint, never the wingman turn path.

Scenarios are grounded in the user's open `tasks` + recent `events` tied to a person entity, falling back to person + relationship when the user has no tasks/events. The `tasks`/`events` tables carry no entity FK, so association is done by the generating LLM: candidates are passed with stable short ids and the LLM returns which ids each scenario used. Each scenario is a rich card: title, situation, goal, success criteria, difficulty, role mode, opening line.

When a scenario-linked roleplay session ends, the `score_scenario` worker grades it by reusing `evaluate_conversation_mission` (`src/bubbles/ai/extraction.py:140`) — pass/fail plus a feedback line — and emits a `complete_scenario` XP event.

**Speed:** feed generation and scoring run in ARQ workers; on-demand generation is a dedicated rate-limited endpoint. The 0.5 s wingman context budget and the per-turn loop are untouched.

## Scope

1. **Migration `2026_05_22_0006_scenarios`** — `scenarios` table (forward + working `downgrade`; `IF NOT EXISTS`-guarded to match `0002`–`0005` against the live Supabase schema):

   | column | type | notes |
   |---|---|---|
   | `id` | `uuid pk default gen_random_uuid()` | |
   | `user_id` | `uuid not null references auth.users(id) on delete cascade` | owner |
   | `target_entity_id` | `uuid references entities(id) on delete set null` | person to roleplay |
   | `title` | `text not null` | short label |
   | `situation` | `text not null` | setup shown to the user |
   | `goal` | `text not null` | what the user practices |
   | `success_criteria` | `text not null` | grading criteria |
   | `difficulty` | `text not null check (difficulty in ('easy','medium','hard'))` | |
   | `role_mode` | `text not null` | written to `session_context.role_mode` |
   | `opening_line` | `text not null` | the embodied entity's first line |
   | `source` | `jsonb not null default '{}'::jsonb` | `{entity_id, tasks:[uuid], events:[uuid]}` — dedup + traceability |
   | `status` | `text not null default 'suggested' check (status in ('suggested','started','completed','dismissed'))` | |
   | `session_id` | `uuid references sessions(id) on delete set null` | linked roleplay session |
   | `passed` | `boolean` | set by `score_scenario` |
   | `score_feedback` | `text` | set by `score_scenario` |
   | `created_at` | `timestamptz not null default now()` | |
   | `updated_at` | `timestamptz not null default now()` | |

   Indexes: `(user_id, status)`, `(user_id, target_entity_id)`. Add `scenarios` to `baseline.sql` and to the conftest teardown DROP list.

2. **`db/models.py`** — `Scenario` dataclass mirroring the table.

3. **`db/repo/scenarios.py`** — new repo (register in `db/repo/__init__.py`):
   - `create_many(conn, *, user_id, rows) -> list[Scenario]`
   - `list_for_user(conn, *, user_id, status='suggested', limit, offset) -> list[Scenario]`
   - `get(conn, scenario_id) -> Scenario | None`
   - `get_by_session(conn, *, session_id) -> Scenario | None`
   - `count_active(conn, *, user_id) -> int` — `status='suggested'`
   - `used_source_ids(conn, *, user_id) -> tuple[set[UUID], set[UUID]]` — task ids and event ids referenced by every non-`dismissed` scenario; dedup input for the generator
   - `mark_started(conn, *, scenario_id, session_id) -> Scenario`
   - `mark_dismissed(conn, *, scenario_id) -> Scenario`
   - `mark_completed(conn, *, scenario_id, passed, feedback) -> Scenario`
   - All writes bump `updated_at`.

4. **`db/repo/entities.py`** — add user-scoped, newest-N readers next to the existing `tasks`/`events` queries: `recent_tasks(conn, *, user_id, limit, exclude_ids)` and `recent_events(conn, *, user_id, limit, exclude_ids)`.

5. **`ai/scenarios.py`** — generator:
   - `GeneratedScenario` dataclass — pre-persist shape, including the resolved `source`.
   - `async def generate(conn, router, *, user_id, count, target_entity_id=None) -> list[GeneratedScenario]`:
     - Gather person entities + relations (`entities_repo.list_for_user`, `list_relations`), persona (`personas_repo.get`), and candidate `recent_tasks` / `recent_events` with already-used ids excluded.
     - When `target_entity_id` is set (on-demand), restrict entities to that one and use `tasks_mentioning` / `events_mentioning` on its name.
     - Render `scenarios/generate.jinja`; one JSON call via `router.complete("scenario.generate", …)`.
     - Parse; map the LLM's short candidate ids (`T1`, `E2`, …) back to real UUIDs and the target person name to an `entity_id`; drop any scenario grounded in an unknown id.
     - Returns `[]` on call/parse failure — never raises.

6. **`ai/prompts/scenarios/generate.jinja`** — prompt: given the user's real people (with relationships), open tasks and recent events (each candidate tagged with a short id), and persona tone, produce up to N practice roleplay scenarios as a JSON array. Each item carries `title, situation, goal, success_criteria, difficulty, role_mode, opening_line, target_person, source_refs[]`. Rules: ground every scenario in real data (no invented people/tasks/events), spread difficulty across the set, keep `opening_line` in the embodied person's voice.

7. **`ai/router.py` / `ai/wiring.py`** — register the `scenario.generate` task chain (JSON-capable; mirror the `wingman.json` provider order and fallback).

8. **Schemas** (`api/v1/_schemas.py`):
   - `ScenarioOut` — every user-facing column.
   - `GenerateScenarioRequest` — `target_entity_id: UUID`.
   - `StartScenarioResponse` — `session_id: UUID`, `scenario: ScenarioOut`.

9. **`api/v1/scenarios.py`** — new router; every route authenticated and ownership-checked against the JWT user:
   - `GET /v1/scenarios` — `status` query (default `suggested`), `limit`/`offset`; returns `list[ScenarioOut]`.
   - `POST /v1/scenarios/generate` — body `GenerateScenarioRequest`; verifies the entity belongs to the user; `ai.scenarios.generate(count=1, target_entity_id=…)`; persists and returns the `ScenarioOut`. `RateLimiter` ~10/min/user. An empty generator result returns `503` (transient — "try again").
   - `POST /v1/scenarios/{id}/start` — builds `session_context = {scenario: situation, role_mode, notes: goal, opening_line}`, creates a roleplay session via the existing session-create path with `target_entity_id`, calls `mark_started`, returns `StartScenarioResponse`. `409` when `status != 'suggested'`.
   - `POST /v1/scenarios/{id}/dismiss` — `mark_dismissed`; `409` when already `started`/`completed`.

10. **`api/router.py`** — register the scenarios router under `/v1`.

11. **`workers/jobs/generate_scenarios.py`** — `generate_scenarios(ctx, user_id)`: read `count_active`; `target = 5`; no-op when `>= target`, otherwise `generate(count=target-active)` then `create_many`. Idempotent `_job_id = f"generate_scenarios:{user_id}:{session_id}"`.

12. **`workers/jobs/score_scenario.py`** — `score_scenario(ctx, scenario_id)`: load the scenario and its linked session's transcript from `session_logs` (`assemble_transcript`); call `evaluate_conversation_mission(router, criteria=f"{goal}\n{success_criteria}", transcript=…, min_turns=4, user_turns=<count>)`; `mark_completed(passed, feedback)`; when `passed`, write XP via `db/repo/xp.py` with `source_type='scenario'`, `source_id=scenario_id` (idempotent on the existing partial unique index) and action type `complete_scenario`.

13. **`api/v1/sessions.py` `end_session`** — in the post-session fan-out: always enqueue `generate_scenarios` for the user; additionally, when `scenarios_repo.get_by_session(session_id)` returns a row, enqueue `score_scenario` for it. Idempotent job ids.

14. **`workers/jobs/__init__.py` + `workers/arq_settings.py`** — register `generate_scenarios` and `score_scenario` in the worker function list.

## Out of scope

- App-side UI — captured separately in `Documentation/feature-1-personalized-roleplay.md` (server changes + app requirements) at implementation time.
- A 0–100 numeric score — `score_scenario` reuses `evaluate_conversation_mission`, which yields pass/fail + a reason; that is what is stored. A graded numeric score is a possible Feature 3 follow-up.
- Cron-scheduled generation — the self-throttling worker on session end is sufficient; no daily cron.
- Editing or regenerating an existing scenario; multiplayer roleplay.
- The unrelated quest `action_type` bug (shortcoming #1) — `score_scenario` writes XP directly via `db/repo/xp.py` and does not touch quest-progress plumbing.

## Tests

- `tests/unit/test_scenarios_generator.py` — short-id → UUID remap; scenarios grounded in unknown ids are dropped; `generate` returns `[]` on a stubbed router failure and never raises.
- `tests/unit/test_routes_validation.py` (extend) — `generate` rejects a missing or third-party `target_entity_id`; `start`/`dismiss` reject bad status transitions.
- `tests/integration/test_repo_scenarios.py` — `create_many`; `list_for_user` status filter, ordering, pagination; `count_active`; `used_source_ids` aggregates across non-dismissed rows only; `mark_*` transitions bump `updated_at`; `target_entity_id` → `null` on entity hard-delete.
- `tests/integration/test_routes_scenarios.py` — feed list ownership-scoped (403 cross-user); on-demand `generate` (stubbed router) persists and returns; `start` creates a roleplay session, links `session_id`, flips status; `dismiss`; `409` on bad transitions; rate limit on `generate`.
- `tests/integration/test_workers_scenarios.py` — `generate_scenarios` no-ops on a full feed and fills the gap otherwise; `score_scenario` writes `passed`/`score_feedback`, sets `completed`, and the XP write is idempotent on re-run.
- `tests/integration/test_routes_sessions.py` (extend) — `end_session` enqueues `generate_scenarios`; a scenario-linked session also enqueues `score_scenario`.

## Done when

`ruff` clean, `mypy --strict` clean, the unit suite green (integration suite green under `RUN_INTEGRATION=1`); migration `0006` upgrades and downgrades cleanly against a fresh Postgres and is a safe no-op against the live Supabase schema; the scenarios router is registered and visible in the OpenAPI schema; every function is fully implemented — no placeholder bodies, stub returns, or "implement later" comments.
