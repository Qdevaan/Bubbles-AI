# `server` (Bubbles Brain API v5) vs `server_v2` — Comparison & Gap Review

**Date:** 2026-05-12 • **Reviewer:** backend • **Decision:** we are going with **`server/` (Bubbles Brain API v5)** as the sole backend. `server_v2/` is parked at `legacy/server_v2/` and will be **deleted once the v5 implementation is complete** (the work items in §6 land and nothing references it). Until then it stays on disk as the reference for the §2 API contract and the §4 behaviour deltas — it is not deployed, not in CI, not used by the Flutter client.

This document is honest about where v5 is *not yet* a drop-in replacement. Read §5 and §6 before assuming a feature works.

---

## 1. TL;DR — architecture comparison

| | `server_v2/` (legacy) | `server/` (v5 — chosen) |
|---|---|---|
| Framework | FastAPI, mixed sync/async handlers | FastAPI, **async-only** |
| Python SLOC | ~10,490 (incl. tests) | ~6,300 src + ~2,000 tests |
| DB access | `supabase-py` (sync) singleton called from async handlers | `asyncpg` pool via PgBouncer transaction mode; repository layer + Unit-of-Work |
| LLM calls | hand-rolled per-provider retry, no breaker | `LLMRouter` provider chain (gemini → cerebras → groq) per task, circuit breaker, `fallback_depth` metric |
| Streaming | none for consultant | SSE by default (`?stream=false` for legacy JSON) |
| Vector / embed | `sentence-transformers` MiniLM loaded at import (~400 MB RAM) | Gemini `text-embedding-004` + Redis content-hash cache; bge-small ONNX offline fallback |
| Graph | `networkx` per-user, in-memory (lost on restart, not shared) | Postgres `entities` + `entity_relations`, rebuilt into a per-request cache |
| STT | Deepgram (paid after trial) | Groq Whisper-large-v3-turbo (free) + faster-whisper local fallback |
| TTS | Deepgram REST | Edge-TTS (free, no key) |
| Speaker ID | SpeechBrain loaded on the request path (8–15 s cold start) | SpeechBrain in an ARQ worker, lazy-loaded once per worker |
| Background jobs | APScheduler in-process (dies with the worker, no locking) | ARQ over Redis, idempotent (`_job_id`), separate worker container, cron |
| Cache / rate-limit | Redis optional + in-memory fallback (hides prod bugs) | Redis required; two-tier cache (TTLCache L1 + Redis L2); atomic Lua token-bucket |
| Auth | `auth_guard` util, ownership checks repeated per route | one `CurrentUser` dependency + `require_ownership`; JWKS cached with cooldown; `DEBUG_SKIP_AUTH` aborts startup outside dev |
| Errors | mixed; some upstream strings leak to clients | typed exceptions → fixed HTTP codes → `{error:{code,message,request_id}}` envelope; never leaks upstream text |
| Observability | `print` + uvicorn access log | structlog JSON + Prometheus `/metrics` + Sentry + OpenTelemetry/OTLP + Logtail handler; Grafana dashboard + alerts in `ops/` |
| Config | pydantic-settings, `extra` allowed | pydantic-settings frozen, `extra` ignored, model-validator invariants (Sentry required in prod, etc.) |
| Deploy | `deploy.sh` + compose on a VM, no zero-downtime | multi-stage distroless Dockerfile (runtime + worker targets), Caddy auto-TLS/HTTP3/SSE-safe, GH Actions build→GHCR→SSH deploy with an Alembic migration gate, rolling restart |
| Tests | ~20 files, route + service level, no integration container | unit suite + 5 testcontainers integration suites; `ruff` clean; `mypy --strict` clean; coverage gate |
| Migrations | ad-hoc `*.sql` files run by hand | Alembic (versioned, reversible); baseline `0001` is a no-op against the existing Supabase schema |

The architecture is unambiguously better in v5. The gap is **feature coverage and wiring**, covered below.

---

## 2. API contract carried over

Same `/v1/*` paths and response shapes as `server_v2/`, so the Flutter client mostly needs a base-URL flip plus the §4 deltas. Currently **registered** in v5:

`GET /health/{live,ready,deep}` · `GET /metrics` · `start_session` · `save_session` · `end_session` · `sessions/{id}/context` · `suggest_reply` · `DELETE sessions/{id}` · `ask_consultant`(+`/batch`) · `ask` · `ask_entity` · `graph_export/{user_id}` · `entity_timeline/{entity_id}` · `DELETE entities/{id}` · `DELETE memories/{id}` · `check_user_turn` · `user_mistakes` · `me/persona` (GET/PUT) · `getToken` · `process_audio` · `tts` · `voice_command` · `WS /v1/stt/stream` · `save_feedback` · `session_analytics/{id}` · `coaching_report/{id}` · `digest/{user_id}` · `communication_trends/{user_id}` · `gamification/{user_id}` · `quests/{user_id}` · `rewards/{user_id}`(+`/redeem`) · `leaderboard`(+`/{user_id}/opt_in`).

Persona Jinja fragments (`casual`/`default`/`educator`/`learner`/`professional` + `_scenario_header`) and the analytics coaching system prompt are ported verbatim from the old `server_v2/app/prompts/`.

Also registered as of 2026-05-12 (H2/H3): `process_transcript_wingman`, `log_turn`, `session_replay/{session_id}`.

**Not yet registered** (still only in `server_v2/`): `enroll`, `identify_speaker`, `performance_summary/{user_id}`, the quest mission endpoints (`quests/{uid}/{uqid}/answer`, `.../attach_session`).

---

## 3. Why v5 (the wins that are real today)

1. **Nothing blocks the event loop.** No sync `supabase-py`, no ML model loads on the request path. CPU/blocking work (LanguageTool JVM, SpeechBrain, embeddings) is in ARQ workers.
2. **Stateless app processes.** All state in Postgres/Redis; graphs rebuilt from `entities`/`entity_relations`. Restart = no data loss; horizontal scale is trivial.
3. **Provider failover.** `LLMRouter` walks `[gemini → cerebras → groq]` per task, trips a breaker on sustained errors. A provider outage degrades to a slower answer, not a 500.
4. **One auth path.** Single `CurrentUser` dependency + `require_ownership`; missing JWKS fails closed (401), not 500. No copy-pasted ownership checks to forget.
5. **Fail-soft infra.** Missing DB/Redis → `503 + Retry-After` (typed `UpstreamUnavailable`), not a 500 leaking `RuntimeError("pool not initialised")`. Redis hiccups degrade to cache misses.
6. **Cost.** Drops Deepgram for Groq Whisper + Edge-TTS (both free); drops the MiniLM blob by defaulting embeddings to Gemini's free tier. Oracle Always-Free + Supabase free + Upstash free → ~$0/mo target.
7. **Operability.** `/metrics`, Sentry, OTLP traces, structured logs with request-id/user-id, Grafana dashboard + alert rules in `ops/`. `server_v2` has `print`.

---

## 4. Behaviour deltas the client must handle

- `POST /v1/ask_consultant` → **SSE by default**. `?stream=false` keeps the old single-JSON shape; otherwise consume `event: token` / `event: done` (carries `finish`, `prompt_tokens`, `completion_tokens`); heartbeats are `event: ping`.
- `POST /v1/end_session` returns the updated session **synchronously**, and now accepts an optional `transcript`. When the client supplies one, v5 enqueues `compute_session_analytics` (title/summary/highlights/coaching report/metrics row), `extract_knowledge` (`session_entities` links), and `compute_embeddings`. Title/summary/highlights are therefore produced **asynchronously** — poll `GET /v1/session_analytics/{id}` / `GET /v1/coaching_report/{id}` or refresh on next open. Omit `transcript` and no follow-up jobs run.
- `POST /v1/ask_entity` is **graph-aware**: extracts entities from the question, looks them up in the user's graph, prompts with that context. Returns `{answer, entities[], provider}`.
- `WS /v1/stt/stream` emits `{"type":"final","text":...}` / `{"type":"error","message":...}` (was Deepgram's native event shape); token-gated via `?token=<jwt>`.
- `POST /v1/check_user_turn` persists detected mistakes (`user_mistakes`, `source ∈ lt|llm`); surfaced by `GET /v1/user_mistakes` → `{items[], counts{}}`.
- `POST /v1/save_session` remains a **read-only no-op** (fetch + return). In `server_v2` it persisted a transcript blob; in v5 the per-turn store is written via `POST /v1/log_turn` (or the wingman loop) — one turn at a time — so `save_session` has nothing to do. Clients that were calling `save_session` to persist the conversation should call `log_turn` per turn instead.

No data migration: v5 writes to the same Supabase DB. New Alembic revisions beyond `0001` are forward-only and must ship a working `downgrade()`.

---

## 5. Shortcomings & holes (be honest)

Severity: **P0** = v5 is not functionally equivalent / a headline feature is dead · **P1** = a real feature is missing but has a clear workaround or is lower-traffic · **P2** = completeness / parity polish · **P3** = ops / hygiene.

### H1 (P0) — ~~No worker job is ever enqueued from the API~~ **DONE (2026-05-12)**

~~`bubbles/workers/enqueue.py` has helpers but nothing in `src/` imports it.~~

**Fixed.** Spec: `docs/superpowers/specs/2026-05-12-v5-port-h1-wire-enqueues-design.md`.
- New `bubbles/workers/client.py` (`make_arq_pool`); lifespan attaches `app.state.arq` (warn-only on failure — a queue outage doesn't block startup).
- `deps.py` exposes `ArqDep -> ArqRedis | None` (never raises: a degraded queue must not 503 an otherwise-good write).
- `EndSessionRequest` gained an optional `transcript` (client supplies the assembled transcript; the per-turn store is H2). `end_session` enqueues `compute_session_analytics` → `extract_knowledge` → `compute_embeddings` for the owner when a transcript is present; enqueue failures are logged and swallowed.
- `check_user_turn` enqueues `grammar_scan` (the LanguageTool pass that complements the synchronous LLM pass).
- Tests: `tests/unit/test_enqueue_helpers.py`, `tests/unit/test_routes_grammar_enqueue.py`, and `end_session` enqueue cases in `tests/integration/test_routes_sessions.py`.

Still cron-only on the *worker* side beyond these: `seed_quests`, `send_reminders`. The `backfill_session_entities` one-off (H8) is now actionable.

### H2 (P0) — ~~v5 stores no per-turn conversation content~~ **DONE (2026-05-12)** — chose option (a)

**Fixed.** Spec: `docs/superpowers/specs/2026-05-12-v5-port-h2-h3-turn-store-wingman-design.md`.
- Alembic `0004` adds `session_logs` (column set mirrors live Supabase; `CREATE TABLE IF NOT EXISTS`, so a no-op on prod, create-from-scratch on a fresh CI DB). `baseline.sql` + conftest teardown updated.
- `db/models.py` → `SessionLog`; new `db/repo/session_logs.py` (`append` with server-assigned monotonic `turn_index`; `list_for_session`; `turn_count`; `assemble_transcript` with role→label map and `last_n`).
- `POST /v1/log_turn` appends a turn (ownership-checked); `GET /v1/session_replay/{session_id}` returns turns ordered by `turn_index` (paginated).
- `end_session` now assembles the transcript from `session_logs` rows when present (a client-supplied `transcript` remains a fallback), then enqueues the post-session jobs.
- `compute_session_analytics` worker now still accepts a `transcript` arg — wiring it to *prefer* `session_logs` rows (so the per-turn columns `average_latency_ms` / `avg_advice_latency_ms` / `avg_sentiment_score` / `dominant_sentiment` and `sentiment_trend` can be populated from row metadata) is a small follow-up; the rows are written, the math just needs to read them.
- **Sub-hole still open:** turn-level sentiment scoring. `session_logs.sentiment_score` / `sentiment_label` ship nullable; a `sentiment_scan` worker (writing those + `sentiment_logs`) is a later item — track under H2.
- Tests: `tests/integration/test_repo_session_logs.py`, `tests/integration/test_routes_wingman.py`, `log_turn`/`session_replay`/`end_session`-from-rows cases in `tests/integration/test_routes_sessions.py`, validation cases in `tests/unit/test_routes_validation.py`.

### H3 (P0) — ~~`process_transcript_wingman` (live wingman advice) not ported~~ **DONE (2026-05-12)**

**Fixed.** `POST /v1/process_transcript_wingman` (`api/v1/wingman.py`):
- Auth + ownership on `session_id` when supplied; appends the incoming turn to `session_logs` synchronously and returns its `turn_index`.
- `speaker_role == "user"` → fast path: persist + enqueue an embeddings refresh + return `{"advice":"WAITING"}` (matches v2 — advice is only for the *other* side).
- `speaker_role == "others"` → builds a small context (recent memories via embeddings/`memory.similar`, falling back to recent rows; top entities), hard-capped at 0.5 s; calls `LLMRouter` task `wingman.advice` (new chain: cerebras → groq → gemini); returns the advice; then **in the background** (`app.state.bg` `FireAndForget`, or inline if absent) appends the advice as an `llm` turn (with `model_used`/`latency_ms`/`tokens_used`/`finish_reason`), and every 5th turn enqueues `extract_knowledge` for the rolling transcript + always enqueues `compute_embeddings`.
- New `wingman/advice.jinja` system prompt; `wingman.advice` chain registered in `DEFAULT_CHAINS`.
- **Not ported (deliberate):** v2's rolling-summary-every-20-turns (`_rolling_summarize`) and multiplayer turn handling — track as follow-ups if wanted.

### H4 (P1) — Speaker `enroll` / `identify_speaker` HTTP routes missing

The `speaker_enroll` ARQ job exists and `api/middleware.py` already lists `/v1/identify_speaker` as an audio path — but no route is registered. Dangling reference.

**Patch:** expose `POST /v1/enroll` and `POST /v1/identify_speaker` over the existing job (enroll = enqueue; identify = synchronous embedding compare against stored vectors). Remove the middleware entry if you decide not to.

### H5 (P1) — Coaching transcript truncated to the last 4 KB

`ai/extraction._truncate` keeps only the last 4000 characters before generating the coaching report, so the **opening of every conversation is dropped** from the analysis (talk-time %, topics, tone all skewed).

**Patch:** raise the limit to the model's real budget, or chunk-summarize long transcripts (map-reduce) instead of hard-truncating.

### H6 (P2) — Gamification parity gaps

- `add_xp` is idempotent on `source_id` but does **not** apply v2's automated daily XP cap (500), streak-milestone bursts, or first-action-today bonus.
- Streak counters (`current_streak`, `longest_streak`, `streak_freezes`) are read by the profile endpoint but **nothing increments them**.
- No achievement-detection worker → `user_achievements` stays empty → `badges[]` always `[]`.
- The profile omits v2's `stats{}` block.
- Quest **mission** endpoints (`POST /quests/{uid}/{uqid}/answer` for question-set missions, `POST /quests/{uid}/{uqid}/attach_session` for conversation missions) are not ported — daily quests are auto-assigned but most can't be completed.

**Patch:** one "XP-award worker + gamification completeness" batch covering all of the above.

### H7 (P2) — `performance_summary/{user_id}` not ported

v2's aggregate performance endpoint. Later batch.

### H8 (P2) — `backfill_session_entities` one-off job not written

`session_entities` (Alembic `0002`) is populated going forward by `extract_knowledge`; sessions created before that migration have no links. (Moot until H1 is fixed and `extract_knowledge` actually runs.) Write the one-off backfill job after H1.

### H9 (P3) — ElevenLabs premium-TTS fallback not wired

Blueprint asks for ElevenLabs behind the same interface as a premium-voice option; only Edge-TTS is wired today.

### H10 (P3) — No ARQ dead-letter queue

Jobs are idempotent and retried, but there's no explicit DLQ and no alert on repeated failure. Add a DLQ + a Prometheus alert on `arq_jobs_failed`.

### H11 (P3) — k6 nightly load test not in CI

`scripts/load_test.js` exists; wiring it into a scheduled GH Action needs a live staging URL.

### H12 (P3) — Integration suites are opt-in

The 5 testcontainers suites are gated behind `RUN_INTEGRATION=1` + the docker SDK; they auto-skip locally. Confirm CI actually sets `RUN_INTEGRATION=1` — if it doesn't, those suites never run anywhere.

### H13 (P3) — No schema-drift guard; Alembic baseline is a no-op

`0001` is a no-op against the live Supabase schema, so the migration chain has never been exercised against a from-scratch DB, and divergence between the code's row models and the prod schema is caught only by code review (the recent `entities.is_archived` vs `deleted_at` near-miss is the cautionary tale). Add a CI job: build the schema from Alembic head into a throwaway Postgres, diff it against `Documentation/db_schema_final_v2.sql`, fail on drift.

### H14 (P3) — Minor nits

- `SaveFeedbackRequest.idempotency_key` is `max_length=200`; other idempotency keys use `128` — pick one.
- `coaching_report.tone_scores` filter is `isinstance(v, int | float)`, which also accepts `bool` — tighten to exclude `bool`.
- `core/transcript._SPEAKER_RE` treats any `prefix: rest` line as a speaker turn, so a bare line containing `https://...` is mis-parsed as speaker `"https"`. Add a guard (e.g. reject prefixes containing `/` or whitespace runs, or require a known/short speaker token).

---

## 6. Recommended order of work to fully retire `server_v2`

1. ~~**H1 — wire the enqueues.**~~ **Done 2026-05-12.** `end_session` (with a client-supplied transcript) → `compute_session_analytics` + `extract_knowledge` + `compute_embeddings`; `check_user_turn` → `grammar_scan`. Spec: `docs/superpowers/specs/2026-05-12-v5-port-h1-wire-enqueues-design.md`.
2. ~~**H2 + H3 — per-turn store + `process_transcript_wingman`.**~~ **Done 2026-05-12.** `session_logs` (Alembic `0004`), `db/repo/session_logs.py`, `POST /v1/log_turn`, `GET /v1/session_replay/{id}`, `POST /v1/process_transcript_wingman`, `end_session` assembles from rows. Spec: `docs/superpowers/specs/2026-05-12-v5-port-h2-h3-turn-store-wingman-design.md`. Follow-ups: analytics worker to read `session_logs` for the per-turn columns; turn-level sentiment scan; rolling-summary; multiplayer turns.
3. **H4 — speaker `enroll` / `identify_speaker` routes** over the existing job.  ← next
4. **H5 — stop truncating the coaching transcript.**
5. **H6 — XP-award worker + gamification completeness** (caps, streaks, achievements, `stats{}`, quest mission endpoints).
6. **H7 — `performance_summary/{user_id}`**; **H8 — `backfill_session_entities` job** (after H1).
7. **H9–H14 — ops/hygiene:** ElevenLabs fallback, ARQ DLQ + alert, k6 nightly, confirm CI runs integration suites, schema-drift CI job, the H14 nits.
8. When the above land and nothing references `legacy/server_v2/`: `git rm -r legacy/server_v2/`.

Each item gets the usual spec → plan → subagent-driven execution cycle; specs live in `docs/superpowers/specs/`.

---

## 7. Status

`server_v2/` is at `legacy/server_v2/` — not deployed, not in CI, not referenced by active config or the Flutter client. `server/` (Bubbles Brain API v5) is the primary backend. The `legacy/` copy stays on disk **only** as the reference for §2 (contract) and §4 (deltas) until §6 is complete; then it is deleted.

The live-deployment cutover (stand up v5 on a subdomain, flip the Flutter `kUseApiV5` flag, 48 h soak, repoint DNS) is documented step-by-step in `Documentation/server-blueprint.md` §18 — that's the ops rollout. The repo-side retirement (move + de-reference) is already done; the *functional* retirement waits on §6 — **H1, H2, H3 landed 2026-05-12**, next is **H4** (speaker `enroll` / `identify_speaker` routes).

### Done so far (v5 port batches)

- **Batch 1 (entity routes).** `GET /v1/graph_export/{user_id}`, `GET /v1/entity_timeline/{entity_id}`, `DELETE /v1/sessions/{id}`, `DELETE /v1/memories/{id}` (entity `DELETE` already existed): JWT-derived ownership, soft deletes, pagination, real `session_entities` link table (Alembic `0002`) that `extract_knowledge` populates *when run* (see H1). Spec: `docs/superpowers/specs/2026-05-11-v5-port-batch1-entity-routes-design.md`.
- **Batch 2 (gamification HTTP).** `GET /v1/gamification/{user_id}`, `GET /v1/quests/{user_id}` (auto-assigns 3 daily quests), `GET /v1/rewards/{user_id}`, `POST /v1/rewards/{user_id}/redeem`, `GET /v1/leaderboard`, `POST /v1/leaderboard/{user_id}/opt_in`. New tables `xp_transactions`/`achievements`/`user_achievements` (Alembic `0003`); pure level math in `core/gamification.py`; `add_xp` ledger-aware + idempotent on `source_id` (gaps: H6). Spec: `docs/superpowers/specs/2026-05-12-v5-port-batch2-gamification-design.md`.
- **Batch 3 (analytics reads + feedback).** `POST /v1/save_feedback` (idempotent on `idempotency_key`), `GET /v1/session_analytics/{session_id}`, `GET /v1/coaching_report/{session_id}`, `GET /v1/digest/{user_id}?period=day|week`, `GET /v1/communication_trends/{user_id}?weeks=N`. `compute_session_analytics` worker enhanced to also write a `session_analytics` metrics row (turn/word counts from the transcript, duration, memory/event/highlight counts) and an LLM coaching report (`analytics.coaching` task chain) — both inert until H1. No migration (`session_analytics`/`coaching_reports`/`feedback` already in the live schema). Spec: `docs/superpowers/specs/2026-05-12-v5-port-batch3-analytics-design.md`.
