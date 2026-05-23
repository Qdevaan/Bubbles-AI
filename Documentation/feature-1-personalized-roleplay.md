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
repeat itself. Never raises — failure yields an empty list. A pure
`parse_scenarios` helper (unit-tested) validates and remaps the LLM JSON
into `NewScenario` rows.

**Endpoints** (all under `/v1`, JWT-authenticated, ownership-checked):

| Method | Path | Purpose |
|---|---|---|
| GET  | `/v1/scenarios?status=suggested&limit=&offset=` | The feed. `status` ∈ suggested/started/completed/dismissed. |
| POST | `/v1/scenarios/generate` | Body `{target_entity_id}`. Generates one scenario synchronously (~1-3 s). Rate-limited ~10/min/user. `201` with the scenario; `403` if the entity is not the caller's; `404` unknown entity; `503` if generation failed (retry). |
| POST | `/v1/scenarios/{id}/start` | Creates a roleplay session from the scenario, links it, returns `{session_id, scenario}`. `409` if the scenario is not `suggested`. |
| POST | `/v1/scenarios/{id}/dismiss` | Drops the scenario from the feed. `409` if already started/completed. |

**Workers:**
- `generate_scenarios` — tops the feed up to 5 `suggested` scenarios per
  user. Enqueued from the `end_session` fan-out; self-throttling (no-op
  when full). ARQ dedup key is per-user (`genscenarios:{user_id}`), so
  rapid successive `end_session` calls coalesce into a single feed refresh.
- `score_scenario` — when a scenario-linked session ends, grades the
  transcript against the scenario's `goal` + `success_criteria`
  (reuses `evaluate_conversation_mission`), writes `passed` +
  `score_feedback`, and awards **40 XP** on a pass
  (`source_type='scenario'`, idempotent on the partial unique index).
  If the LLM upstream fails (`passed is None`), the scenario stays in
  `started` so ARQ retries (up to `MAX_TRIES=5`) can re-attempt scoring.

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
   `score_feedback` on a results screen. Poll briefly (e.g., 2-5 s after
   `end_session`) or show "scoring…" until `status='completed'`.

6. **No app-side generation logic** — scenarios are entirely server-built;
   the app only lists, generates-on-demand, starts, and dismisses.

## Status field semantics

| `status` | meaning | next allowed transition |
|---|---|---|
| `suggested` | in the feed, not yet started | `started` (via `/start`) or `dismissed` (via `/dismiss`) |
| `started`   | a roleplay session is in progress; `session_id` is set | `completed` (set by the `score_scenario` worker when the session ends) |
| `completed` | session ended and was scored; `passed` + `score_feedback` are set | terminal |
| `dismissed` | user explicitly removed it from the feed | terminal |

## File map (server)

- `server/alembic/versions/2026_05_22_0006_scenarios.py` — migration.
- `server/src/bubbles/db/models.py` — `Scenario` dataclass.
- `server/src/bubbles/db/repo/scenarios.py` — repo + `NewScenario`.
- `server/src/bubbles/db/repo/entities.py` — `recent_tasks`, `recent_events` readers.
- `server/src/bubbles/ai/scenarios.py` — generator (`generate`, `parse_scenarios`).
- `server/src/bubbles/ai/prompts/scenarios/generate.jinja` — prompt.
- `server/src/bubbles/ai/router.py` — `scenario.generate` task chain.
- `server/src/bubbles/api/v1/scenarios.py` — four `/v1/scenarios` routes.
- `server/src/bubbles/api/router.py` — router registered.
- `server/src/bubbles/api/v1/_schemas.py` — `ScenarioOut`, `GenerateScenarioRequest`, `StartScenarioResponse`.
- `server/src/bubbles/workers/jobs/generate_scenarios.py` — feed worker.
- `server/src/bubbles/workers/jobs/score_scenario.py` — scoring worker.
- `server/src/bubbles/workers/enqueue.py` — `enqueue_generate_scenarios`, `enqueue_score_scenario`.
- `server/src/bubbles/workers/arq_settings.py` — worker registrations.
- `server/src/bubbles/api/v1/sessions.py` — `end_session` fan-out wired.

## Tests

- `server/tests/unit/test_scenarios_generator.py` — pure-parser unit tests (6 cases).
- `server/tests/integration/test_repo_scenarios.py` — repo CRUD + status guards + dedup (7 cases).
- `server/tests/integration/test_repo_entities_recent.py` — graph-reader exclusion behavior (2 cases).
- `server/tests/integration/test_routes_scenarios.py` — 4 routes, ownership, status transitions (5 cases).
- `server/tests/integration/test_workers_scenarios.py` — feed throttle + scoring + retry path (7 cases).
- `server/tests/integration/test_routes_sessions.py` — extended for the new fan-out + scenario-linked scoring.

Integration tests run with `$env:RUN_INTEGRATION='1'` and require Docker
(testcontainers Postgres). They skip automatically when Docker is
unavailable.
