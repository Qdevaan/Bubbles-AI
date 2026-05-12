# `server` (Bubbles Brain API v5) vs `server_v2` — Comparison Review

**Date:** 2026-05-11 (retirement applied same day) • **Reviewer:** backend • **Verdict:** `server/` (Bubbles Brain API v5) is the primary backend. `server_v2/` is retired — moved to `legacy/server_v2/` for reference only, no longer deployed or maintained.

---

## 1. TL;DR

| | `server_v2/` (current prod) | `server/` (v5, new) |
|---|---|---|
| Framework | FastAPI, mixed sync/async handlers | FastAPI, **async-only** |
| Python SLOC | ~10,490 (incl. tests) | ~6,214 src + ~1,823 tests = ~8,037 |
| DB access | `supabase-py` (sync) singleton, called from async handlers | `asyncpg` pool via PgBouncer transaction mode, repo layer + UoW |
| LLM calls | hand-rolled per-provider retry, no breaker | provider chain w/ circuit breaker + per-task fallback + budgets |
| Streaming | none for consultant | SSE default (`?stream=false` for legacy JSON) |
| Vector / embed | `sentence-transformers` MiniLM loaded at import (~400 MB RAM) | Gemini `text-embedding-004` + Redis content-hash cache; bge-small ONNX as offline fallback |
| Graph | `networkx` per-user in-memory (lost on restart, not shared) | Postgres `entities` + `entity_relations`, rebuilt on demand |
| STT | Deepgram (free trial only) | Groq Whisper-large-v3-turbo (free) + faster-whisper local fallback |
| TTS | Deepgram REST | Edge-TTS (free, no key) |
| Speaker ID | SpeechBrain loaded on request path (8–15 s cold start) | SpeechBrain in ARQ worker, lazy-loaded once per worker |
| Background jobs | APScheduler in-process (dies with worker, no locking) | ARQ over Redis, idempotent (SETNX), separate worker container, cron |
| Cache / RL | Redis optional + in-memory fallback (hides prod bugs) | Redis required; two-tier cache (TTLCache L1 + Redis L2); atomic Lua token-bucket |
| Auth | `auth_guard` util, ownership checks repeated per route | single `CurrentUser` dependency + `require_ownership`; JWKS cached w/ cooldown; `DEBUG_SKIP_AUTH` aborts startup outside dev |
| Errors | mixed; some upstream strings leak to clients | typed exceptions → fixed HTTP codes → stable `{error:{code,message,request_id}}` envelope; never leaks upstream text |
| Observability | `print` + uvicorn access log | structlog JSON + Prometheus `/metrics` + Sentry + OpenTelemetry/OTLP + Logtail handler |
| Config | pydantic-settings, `extra` allowed | pydantic-settings frozen, `extra` ignored, model-validator invariants (e.g. Sentry required in prod) |
| Deploy | `deploy.sh` + compose on a VM, no zero-downtime | multi-stage distroless Dockerfile (runtime + worker targets), Caddy auto-TLS/HTTP3/SSE-safe, GH Actions build→GHCR→SSH deploy w/ Alembic migration gate, rolling restart |
| Tests | ~20 files, route + service level, no integration container | 85 unit tests + 5 testcontainers integration suites; `ruff` clean; `mypy --strict` clean; coverage gate |
| Migrations | ad-hoc `*.sql` files run by hand | Alembic (versioned, reversible); baseline `0001` is a no-op against existing Supabase schema |

---

## 2. What carried over unchanged (API contract)

Same `/v1/*` paths and response shapes as `server_v2/`, so the Flutter client only needs a base-URL flip plus the handful of behaviour deltas in §4:

`/health/*`, `start_session`, `save_session`, `end_session`, `sessions/{id}/context`, `suggest_reply`, `ask_consultant`(+`/batch`), `ask`, `ask_entity`, `graph_export/{user_id}`, `entity_timeline/{entity_id}`, `DELETE entities|sessions|memories`, `check_user_turn`, `user_mistakes`, `me/persona` (GET/PUT), `getToken`, `process_audio`, `voice_command`, `tts`, `WS /v1/stt/stream`.

Persona Jinja fragments (`casual`/`default`/`educator`/`learner`/`professional` + `_scenario_header`) ported verbatim from the old `server_v2/app/prompts/personas/` (now `legacy/server_v2/app/prompts/personas/`).

---

## 3. Architectural improvements (why v5)

1. **No blocking on the event loop.** `server_v2` calls sync `supabase-py` and loads ML models inside async handlers — those stalls block every other request on the worker. `server/` is async top to bottom; CPU/blocking work (LanguageTool JVM, SpeechBrain, embeddings backfill) runs in ARQ workers, never on the request path.
2. **Stateless app processes.** `server_v2`'s per-user `networkx` graph and in-memory session store vanish on restart and aren't shared across workers. `server/` keeps all state in Postgres/Redis; graphs are rebuilt from `entities`/`entity_relations` into a per-request cache. Restart = no data loss, scale = trivial.
3. **Provider failover with a circuit breaker.** `server_v2` retries a single provider and 500s when it's down. `server/`'s `LLMRouter` walks `[gemini → cerebras → groq]` (per task), trips a breaker on sustained errors, and reports `fallback_depth` as a metric. A provider outage degrades to a slightly slower answer, not an error.
4. **One auth path.** Ownership checks were copy-pasted across `server_v2` routes (easy to miss → IDOR risk). `server/` has a single `CurrentUser` dependency and `require_ownership(user, owner_id)`; missing JWKS fails closed (401), not 500.
5. **Fail-soft infra.** Missing DB/Redis in `server/` → `503 + Retry-After` (typed `UpstreamUnavailable`), not a 500 that leaks `RuntimeError("pool not initialised")`. Cache reads degrade to misses on Redis hiccups instead of throwing.
6. **Cost.** Drops Deepgram (paid after trial) for Groq Whisper + Edge-TTS (both free); drops the 400 MB MiniLM blob from the image by defaulting embeddings to Gemini's free tier. Whole stack runs on Oracle Always-Free + Supabase free + Upstash free → $0/mo target (blueprint §3).
7. **Operability.** `/metrics` (Prometheus), Sentry, OTLP traces, structured JSON logs with request-id/user-id, Grafana dashboard JSON + alert rules checked into `ops/`. `server_v2` has `print` and the uvicorn access log.

---

## 4. Behaviour deltas the client must handle

- `POST /v1/ask_consultant` → **SSE by default**. Pass `?stream=false` to keep the old single-JSON shape, or consume `event: token` / `event: done` (carries `finish`, `prompt_tokens`, `completion_tokens`); heartbeats arrive as `event: ping`.
- `POST /v1/end_session` returns the updated session **synchronously**; title/summary/highlights now land **asynchronously** via the `compute_session_analytics` worker job — poll `GET /v1/session_analytics/{id}` or refresh on next open.
- `POST /v1/ask_entity` is **graph-aware**: it extracts entities from the question first, looks them up in the user's graph, then prompts with that context. Returns `{answer, entities[], provider}` — render the cited entities (closes todos #12).
- `WS /v1/stt/stream` emits `{"type":"final","text":...}` and `{"type":"error","message":...}` (was Deepgram's native event shape); token-gated via `?token=<jwt>`.
- `POST /v1/check_user_turn` persists detected mistakes via the `user_mistakes` table (`source` ∈ `lt|llm`), surfaced by `GET /v1/user_mistakes` (now returns `{items[], counts{}}`).

No data migration: `server/` writes to the same Supabase DB as `server_v2/`. The only forward-only change is any *new* Alembic revision beyond `0001`; each must ship a working `downgrade()`.

---

## 5. Known gaps / follow-ups (not blockers)

> **Batch 1 (entity routes) — done.** `GET /v1/graph_export/{user_id}`, `GET /v1/entity_timeline/{entity_id}`, `DELETE /v1/sessions/{id}`, `DELETE /v1/memories/{id}` are implemented in v5 (the entity `DELETE` already existed), with JWT-derived ownership, soft deletes, pagination, and a real `session_entities` link table (Alembic `0002`) that the `extract_knowledge` worker now populates. See `docs/superpowers/specs/2026-05-11-v5-port-batch1-entity-routes-design.md`.

> **Batch 2 (gamification HTTP) — done.** `GET /v1/gamification/{user_id}`, `GET /v1/quests/{user_id}` (auto-assigns 3 daily quests), `GET /v1/rewards/{user_id}` (catalog + balance + per-reward affordability/ownership), `POST /v1/rewards/{user_id}/redeem`, `GET /v1/leaderboard?period=all|daily|weekly|monthly&limit=`, `POST /v1/leaderboard/{user_id}/opt_in` are implemented in v5. New tables `xp_transactions` / `achievements` / `user_achievements` (Alembic `0003`, DDL mirrors the live Supabase schema); pure level-math in `bubbles/core/gamification.py`; `add_xp` is now ledger-aware and idempotent on `source_id`. See `docs/superpowers/specs/2026-05-12-v5-port-batch2-gamification-design.md`. Still pending, each per its own batch: quest mission types (`/quests/{uid}/{uqid}/answer` + `/attach_session`), analytics/performance reads, `performance_summary`, speaker `enroll`/`identify_speaker`, `process_transcript_wingman`.

> **Batch 3 (analytics reads + feedback) — done.** `POST /v1/save_feedback` (idempotent on `idempotency_key`), `GET /v1/session_analytics/{session_id}`, `GET /v1/coaching_report/{session_id}`, `GET /v1/digest/{user_id}?period=day|week`, `GET /v1/communication_trends/{user_id}?weeks=N` are implemented in v5. The `compute_session_analytics` worker now also writes a `session_analytics` metrics row (turn/word counts parsed from the transcript; duration; memory/event/highlight counts) and an LLM-generated `coaching_reports` row (`analytics.coaching` task chain). No migration — `session_analytics` / `coaching_reports` / `feedback` already exist in the live Supabase schema. See `docs/superpowers/specs/2026-05-12-v5-port-batch3-analytics-design.md`.

- **Backfill `session_entities`**: the link table (migration `0002`) is populated going forward by the `extract_knowledge` worker; sessions created before this change have no links yet — a one-off `backfill_session_entities` worker job is pending.
- **Analytics follow-ups**: `GET /v1/session_replay/{session_id}` is not ported — it needs a per-turn store (`session_logs`), which v5 does not keep yet; bundle it with that work. The per-turn-derived `session_analytics` columns (`average_latency_ms`, `avg_advice_latency_ms`, `avg_sentiment_score`, `dominant_sentiment`) stay NULL and the `sentiment_trend` array stays empty until v5 captures per-turn latency/sentiment (a `sentiment_logs` writer). Nothing yet calls `enqueue_session_analytics` (end_session → enqueue) — wiring that trigger is a separate change.
- **`performance_summary/{user_id}` endpoint**: not yet ported (later batch).
- **Gamification follow-ups**: the two quest *mission* endpoints (`POST /quests/{uid}/{uqid}/answer` for question_set missions, `POST /quests/{uid}/{uqid}/attach_session` for conversation missions) are not ported yet; `add_xp` does not yet apply v2's automated daily XP cap (500), streak-milestone bursts, or first-action-today bonus (the idempotency mechanism is in place); no worker populates `user_achievements` yet, so `badges[]` stays empty until an achievement-detection job lands; the profile omits v2's `stats{}` block; streak counters (`current_streak`/`longest_streak`/`streak_freezes`) are read but nothing increments them yet — all of that is the future XP-award-worker batch.
- **Speaker `enroll` / `identify_speaker` HTTP routes**: SpeechBrain runs in the ARQ worker (`speaker_enroll` job); the v2 HTTP endpoints (`POST /v1/enroll`, `POST /v1/identify_speaker`) are not yet exposed in v5 (later batch).
- **`process_transcript_wingman` route**: v2's real-time wingman-advice endpoint is not yet ported (later batch).
- **ElevenLabs TTS fallback**: blueprint calls for it behind the same interface as a premium-voice option; Edge-TTS only is wired today.
- **ARQ dead-letter queue**: jobs are idempotent and retried; an explicit DLQ + alert on repeated failure is still pending.
- **k6 nightly in CI**: `scripts/load_test.js` exists; wiring it into a scheduled GH Action against staging is pending a live staging URL.

---

## 6. Status — retired

`server_v2/` has been **moved to `legacy/server_v2/`** and is no longer deployed, maintained, or referenced by any active config, CI, or the Flutter client. `server/` (Bubbles Brain API v5) is the sole backend. The `legacy/` copy is kept on disk only as a reference for the §2 contract and the §4 behaviour deltas; once the §5 follow-ups land and nothing points at it, `git rm -r legacy/server_v2/` for good.

The live-deployment cutover (stand up v5 on a subdomain, flip the Flutter `kUseApiV5` flag, 48 h soak, repoint DNS) is still documented step-by-step in `Documentation/server-blueprint.md` §18 — that's the ops rollout; the repo-side retirement is done.
