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

Also registered as of 2026-05-12 (H2/H3/H4): `process_transcript_wingman`, `log_turn`, `session_replay/{session_id}`, `enroll`, `identify_speaker`.

Also registered 2026-05-12 (H7): `performance_summary/{user_id}`.

Also registered 2026-05-12 (H6b): `quests/{user_id}/{user_quest_id}/answer`, `quests/{user_id}/{user_quest_id}/attach_session`.

**Not yet registered:** none — the v2 `/v1/*` surface is fully ported.

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

### H4 (P1) — ~~Speaker `enroll` / `identify_speaker` HTTP routes missing~~ **DONE (2026-05-12)**

**Fixed.** `api/v1/speaker.py`:
- `POST /v1/enroll` (multipart audio) → enqueues `speaker_enroll` (one in-flight per user via `_job_id=enroll:<uid>`), `202 {status:"queued", job_id}`. Queue down → 503.
- `POST /v1/identify_speaker` (multipart audio) → enqueues a new `speaker_identify` job and `await job.result(timeout=15s)`; returns `{enrolled, is_user, similarity}`. The heavy ECAPA encode runs in the worker, never on the request path; timeout/worker error → 503 (no internals leaked).
- New `speaker_identify` worker job (ECAPA encode + pgvector cosine distance vs the user's enrolment; match threshold ≈ cos-sim 0.70). `speaker_enroll` refactored to a `db/repo/voice.py` (`upsert_embedding` / `cosine_distance_to_user`) — fixes the old `ON CONFLICT (id)` bug that inserted a fresh row every enrol.
- Alembic `0005` adds `voice_enrollments` (no-op on prod where the table + `vector` extension already exist; the migration does *not* create the extension). `baseline.sql` now `CREATE EXTENSION IF NOT EXISTS vector` + the table; conftest teardown updated.
- **Also fixed (latent P0 it depended on):** the worker's function registration. Every job module exports `run`; ARQ keys functions by name, so the previous `functions = [compute_embeddings.run, extract_knowledge.run, …]` registered eight colliding `run`s and `enqueue.py`'s `enqueue_job("run", _job_name=…)` passed `_job_name` to a `run()` that didn't accept it — i.e. **no enqueued job could ever execute**. Replaced with a single `run(ctx, *, _job_name, **kwargs)` dispatcher over a `_JOB_REGISTRY`. This is what actually makes H1's wiring (and H3's, and H4's) work end-to-end.
- Middleware `_AUDIO_PATHS` already listed both routes — kept.
- Tests: `tests/unit/test_routes_speaker.py`, `tests/unit/test_worker_dispatch.py`.

### H5 (P1) — ~~Coaching transcript truncated to the last 4 KB~~ **DONE (2026-05-12)**

**Fixed.** `ai/extraction._truncate` (last-4 KB hard slice) is gone. New `prepare_transcript(router, transcript)`: passes through anything ≤ 32 KB verbatim; longer transcripts are split on line boundaries (~16 KB chunks), each chunk condensed by the LLM (`wingman/condense_segment.jinja` → `[Segment N] …`), the join re-condensed up to 3 passes if still over budget, and only hard-clipped as a last resort (single un-splittable segment / pass cap). A failed segment falls back to its clipped raw text. The `compute_session_analytics` and `extract_knowledge` workers call `prepare_transcript` **once** and feed the result to all the extraction prompts; turn/word-count metrics still use the **raw** transcript. Tests: `prepare_transcript` / `_split_on_line_boundaries` cases in `tests/unit/test_extraction.py`.

### H6 (P2) — Gamification parity gaps — **mostly DONE (2026-05-12)**

Done:
- **Daily XP cap (500)** — `add_xp` now clamps an award so the user's combined automated XP for the current UTC day stays ≤ `DAILY_AUTOMATED_XP_CAP`. Exempt sources (`quest`, `achievement`, `streak_milestone`) pass `capped=False` and are never limited; `xp_repo.sum_since` gained an `exclude_source_types` arg so the cap budget ignores them. (First-action-today bonus is now just a convention: award with a `source_id=first_today_<uid>_<date>` — `add_xp`'s ledger dedup makes it once-per-day. Not given a dedicated helper.)
- **Streak increments + milestone bonuses** — `gamification_repo.update_streak(conn, *, user_id, today=None)`: consecutive day → +1; one-day gap with a freeze → +1 and consume a freeze; otherwise reset to 1; bumps `longest_streak`; on hitting {7,14,30,60,100,365} days awards a one-off `streak_milestone` bonus (cap-exempt, idempotent per milestone). Wired into `start_session` (separate transaction, best-effort) — call it before any XP since `add_xp` stamps `last_active_date`.
- **Achievement-detection worker** — `workers/jobs/detect_achievements.py`: computes the user's stats (xp, level, streaks, sessions/memories/entities/quests-completed/mistakes counts), evaluates each un-earned `achievements` row's `criteria_type`/`criteria_value`, inserts `user_achievements` (unique-constrained) and awards `xp_reward` (cap-exempt, deduped on the achievement id). Registered in the worker; `enqueue_detect_achievements` helper; enqueued from `end_session`. `achievements_repo` gained `list_unearned` / `award`.
- Tests: `tests/integration/test_gamification_h6.py` (cap clamping, streak rules incl. freeze + milestone, achievement worker idempotency).

**H6b — DONE (2026-05-12):**
- Profile **`stats{}` block** — `GET /v1/gamification/{user_id}` now returns `stats: {sessions_total, sessions_completed, memories_total, entities_total, mistakes_total, quests_completed, achievements_earned}` via `gamification_repo.user_activity_stats` (one round-trip).
- Quest **mission** endpoints — `POST /v1/quests/{user_id}/{user_quest_id}/answer` (question_set: records one answer keyed by `question_id` in `user_quests.brief_state`; progress = #distinct questions answered; completes + awards `xp_reward` at `target`; rejects unknown ids when `brief.questions[].id` is set) and `POST /v1/quests/{user_id}/{user_quest_id}/attach_session` (conversation: completes + awards XP iff the attached session has ≥ `brief.min_turns` user turns; records the attempt in `brief_state` either way). New repo: `get_user_quest`, `get_quest_def`, `record_question_answer`, `complete_conversation_quest`, `award_quest_xp_once`, `bump_quest_progress_by_action`. Schemas `QuestAnswerRequest` / `QuestAttachSessionRequest` / `QuestMissionResult`. *(Not ported: v2's LLM transcript-evaluator for conversation missions — completion is gated on `min_turns` only; a brief-criteria LLM check is a follow-up.)*
- Live-loop XP wiring — `process_transcript_wingman`'s background path now awards a small per-turn XP (`wingman_turn`, daily-capped, idempotent per turn) and calls `bump_quest_progress_by_action(user_id, "use_wingman_turns")`. (`ask_consultant` / memory-save quest hooks still TODO — low priority.)
- Tests: `tests/integration/test_routes_quest_missions.py`.

### H7 (P2) — ~~`performance_summary/{user_id}` not ported~~ **DONE (2026-05-12)**

**Fixed.** `GET /v1/performance_summary/{user_id}` (in `api/v1/analytics.py`). Pure composite math lives in `core/performance.py` (`compute_performance(PerformanceInputs) -> PerformanceSummary`) — re-derived from the metrics v5 actually persists (v2's `mutual_engagement_score` doesn't exist here; engagement is proxied by talk-time balance from `coaching_reports.user_talk_pct`). Six weighted components (engagement 0.30 / sentiment 0.15 / session-freq 0.20 / quest-completion 0.15 / streak 0.10 / filler-control 0.10), tier (`struggling`/`steady`/`improving`/`excelling`) → recommended difficulty + a coaching tip + `focus_areas`. The route reads the trailing 7-day window and the 7–14-day window and returns `score_delta` between the two composites. New repo helpers: `analytics_repo.performance_window`, `gamification_repo.quest_completion_between`. Tests: `tests/unit/test_performance.py`, `tests/integration/test_performance_h7_h8.py`.

### H8 (P2) — ~~`backfill_session_entities` one-off job not written~~ **DONE (2026-05-12)**

**Fixed.** `workers/jobs/backfill_session_entities.py` — finds sessions that have `session_logs` rows but no `session_entities` rows, assembles each transcript, and runs `extract_knowledge` inline for it (bounded by a `limit`, default 200). Sessions with no stored transcript (pre-H2, no `session_logs`) are skipped — there's nothing to extract from. Registered in the worker; `enqueue_backfill_session_entities` helper (`_job_id` fixed so only one runs at a time) — an operator enqueues it and re-runs until `sessions_processed` is 0. Test: `test_backfill_session_entities` in `tests/integration/test_performance_h7_h8.py`.

### H9 (P3) — ~~ElevenLabs premium-TTS fallback not wired~~ **DONE (2026-05-12)**

**Fixed.** `voice/tts.py` now has `synthesize_mp3(text, *, voice, settings)`: voice presets carrying an `elevenlabs_voice_id` (the `premium` / `premium-male` presets) are synthesised via the ElevenLabs API when `ELEVENLABS_API_KEY` is set; **any** failure (no key, bad voice, quota, network) transparently falls back to free Edge-TTS — same `AsyncIterator[bytes]` interface, callers don't know which engine ran. New settings: `elevenlabs_api_key`, `elevenlabs_model`. The `/v1/tts` route now calls `synthesize_mp3`. (`stream_mp3` kept as the Edge-only primitive.) Tests: `tests/unit/test_tts.py`.

### H10 (P3) — ~~No ARQ dead-letter queue~~ **DONE (2026-05-12)**

**Fixed.** The job dispatcher (`arq_settings.run`) now catches handler exceptions; on the **final** retry (`job_try >= MAX_TRIES`, `MAX_TRIES=5`, set on `WorkerSettings`) it logs `job_dead_lettered` and pushes a JSON record `{job_name, kwargs, error, failed_at}` to the Redis list `arq:dead_letter` (capped at 1000), then re-raises so arq still records the failure. The API's `/metrics` exposes `bubbles_arq_dead_letter_queue_size` (LLEN probe on scrape), and `ops/alerts.yml` has a `BubblesARQDeadLetterGrowing` alert (`> 0` for 5m). Inspect with `redis-cli LRANGE arq:dead_letter 0 -1`; clear once handled. Tests: dead-letter cases in `tests/unit/test_worker_dispatch.py`.

### H11 (P3) — ~~k6 nightly load test not in CI~~ **DONE (2026-05-12)**

**Fixed.** `.github/workflows/load-test.yml` — nightly (03:00 UTC) + `workflow_dispatch`; runs the Locust scenario in `server/scripts/load_test.py` (`uv run --with locust locust … --headless -u 20 -r 5 -t 2m`) against `secrets.STAGING_URL` (and `secrets.STAGING_BUBBLES_TOKEN` for authed routes). **Skips cleanly** if `STAGING_URL` isn't configured. *(Note: the load scenario is Locust, not k6 as the original blueprint wording said — `scripts/load_test.py`, not a `.js` file.)*

### H12 (P3) — ~~Integration suites are opt-in / not in CI~~ **DONE (2026-05-12)**

The testcontainers suites are gated behind `RUN_INTEGRATION=1` + Docker; they auto-skip locally. Fixed earlier: the `conftest` import no longer crashes under `filterwarnings = ["error"]` (targeted ignore for testcontainers' `@wait_container_is_ready` DeprecationWarning). **Now also fixed:** `.github/workflows/ci.yml` has an `integration` job that runs `RUN_INTEGRATION=1 uv run pytest tests/integration` on `ubuntu-latest` (which ships Docker → testcontainers works), so the suites actually run on every push/PR.

### H13 (P3) — ~~Schema-drift guard / Alembic baseline is a no-op~~ **DONE (2026-05-12)**

`0001` is a no-op against the live Supabase schema, so the chain can't run against a *truly* empty DB (it references `auth.users`, `sessions`, `entities`, … that `0001` doesn't create). **What landed:** `ci.yml`'s `migrations` job installs `pgcrypto`/`vector`, applies the test baseline (`tests/integration/fixtures/baseline.sql` — the Supabase-equivalent base schema), then `alembic upgrade head` (verifies `0002…0005` apply on top), then runs `scripts/check_schema_drift.py` (tolerant column-inventory comparator: parses `Documentation/db_schema.sql` into `{table: {columns}}`, introspects the migrated `public` schema, and **fails if the migrated DB has any table/column not in the dump** — that's the dangerous direction; prod-has-more is just info since `baseline.sql` mirrors a subset; `alembic_version`/`session_entities`/`user_personas` are allow-listed as legitimately v5-new), then `alembic downgrade base` → `alembic upgrade head` again (verifies every migration's `downgrade()` works). Tests for the comparator's pure parts: `tests/unit/test_check_schema_drift.py`.

### H14 (P3) — ~~Minor nits~~ **DONE (2026-05-12)**

- `SaveFeedbackRequest.idempotency_key` is now `max_length=128` (aligned with the other idempotency keys).
- `coaching_report.tone_scores` now excludes `bool` (`isinstance(v, int | float) and not isinstance(v, bool)`).
- `core/transcript` now skips URL/scheme lines (`^\s*[A-Za-z][A-Za-z0-9+.\-]*://`) before the speaker-prefix regex, so `https://example.com` is no longer parsed as speaker `"https"`. Test: `test_url_lines_are_not_parsed_as_speakers`.

---

## 6. Recommended order of work to fully retire `server_v2`

1. ~~**H1 — wire the enqueues.**~~ **Done 2026-05-12.** `end_session` (with a client-supplied transcript) → `compute_session_analytics` + `extract_knowledge` + `compute_embeddings`; `check_user_turn` → `grammar_scan`. Spec: `docs/superpowers/specs/2026-05-12-v5-port-h1-wire-enqueues-design.md`.
2. ~~**H2 + H3 — per-turn store + `process_transcript_wingman`.**~~ **Done 2026-05-12.** `session_logs` (Alembic `0004`), `db/repo/session_logs.py`, `POST /v1/log_turn`, `GET /v1/session_replay/{id}`, `POST /v1/process_transcript_wingman`, `end_session` assembles from rows. Spec: `docs/superpowers/specs/2026-05-12-v5-port-h2-h3-turn-store-wingman-design.md`. Follow-ups: analytics worker to read `session_logs` for the per-turn columns; turn-level sentiment scan; rolling-summary; multiplayer turns.
3. ~~**H4 — speaker `enroll` / `identify_speaker` routes**~~ **Done 2026-05-12.** Also fixed the worker dispatch (colliding `run` registrations → single `_job_name` dispatcher) — the prerequisite for any enqueued job actually running.
4. ~~**H5 — stop truncating the coaching transcript.**~~ **Done 2026-05-12.** `prepare_transcript` (map-reduce condense for long transcripts) replaces the 4 KB tail-slice.
5. ~~**H6 — XP-award worker + gamification completeness.**~~ **Done 2026-05-12** — daily XP cap, streaks + milestone bonuses (wired into `start_session`), achievement worker (enqueued from `end_session`); + H6b: profile `stats{}`, quest-mission endpoints (`answer` / `attach_session`), per-turn XP + quest progress in `process_transcript_wingman`.
6. ~~**H7 — `performance_summary/{user_id}`**; **H8 — `backfill_session_entities` job**.~~ **Done 2026-05-12.**
7. ~~**H9–H14 — ops/hygiene**~~ **Done 2026-05-12.** H9 ElevenLabs fallback; H14 nits; H10 ARQ dead-letter queue + `bubbles_arq_dead_letter_queue_size` metric + alert; H11 nightly Locust workflow (secret-gated); H12 testcontainers fix + `ci.yml` integration job; H13 — `ci.yml` `migrations` job applies + round-trips the chain on the baseline schema **and runs `scripts/check_schema_drift.py`** against `Documentation/db_schema.sql`. New: `.github/workflows/ci.yml`, `.github/workflows/load-test.yml`, `server/scripts/check_schema_drift.py`.
8. **All findings closed.** Left: `git rm -r legacy/server_v2/` once nothing references it (and the minor doc-noted follow-ups: analytics worker reading `session_logs` for per-turn columns; turn-level sentiment scan; rolling-summary; LLM evaluator for conversation missions; `ask_consultant`/memory-save quest hooks).

Each item gets the usual spec → plan → subagent-driven execution cycle; specs live in `docs/superpowers/specs/`.

---

## 7. Status

`server_v2/` is at `legacy/server_v2/` — not deployed, not in CI, not referenced by active config or the Flutter client. `server/` (Bubbles Brain API v5) is the primary backend. The `legacy/` copy stays on disk **only** as the reference for §2 (contract) and §4 (deltas) until §6 is complete; then it is deleted.

The live-deployment cutover (stand up v5 on a subdomain, flip the Flutter `kUseApiV5` flag, 48 h soak, repoint DNS) is documented step-by-step in `Documentation/server-blueprint.md` §18 — that's the ops rollout. The repo-side retirement (move + de-reference) is already done; the retirement is **done — all of §5's H1–H14 (and the H6b sub-items) landed 2026-05-12**, plus the worker-dispatch fix and the new `ci.yml` / `load-test.yml` / `check_schema_drift.py`. The whole v2 `/v1/*` surface is ported. The only thing left is `git rm -r legacy/server_v2/` once you're satisfied nothing references it (and the small doc-noted follow-ups in §5).

### Done so far (v5 port batches)

- **Batch 1 (entity routes).** `GET /v1/graph_export/{user_id}`, `GET /v1/entity_timeline/{entity_id}`, `DELETE /v1/sessions/{id}`, `DELETE /v1/memories/{id}` (entity `DELETE` already existed): JWT-derived ownership, soft deletes, pagination, real `session_entities` link table (Alembic `0002`) that `extract_knowledge` populates *when run* (see H1). Spec: `docs/superpowers/specs/2026-05-11-v5-port-batch1-entity-routes-design.md`.
- **Batch 2 (gamification HTTP).** `GET /v1/gamification/{user_id}`, `GET /v1/quests/{user_id}` (auto-assigns 3 daily quests), `GET /v1/rewards/{user_id}`, `POST /v1/rewards/{user_id}/redeem`, `GET /v1/leaderboard`, `POST /v1/leaderboard/{user_id}/opt_in`. New tables `xp_transactions`/`achievements`/`user_achievements` (Alembic `0003`); pure level math in `core/gamification.py`; `add_xp` ledger-aware + idempotent on `source_id` (gaps: H6). Spec: `docs/superpowers/specs/2026-05-12-v5-port-batch2-gamification-design.md`.
- **Batch 3 (analytics reads + feedback).** `POST /v1/save_feedback` (idempotent on `idempotency_key`), `GET /v1/session_analytics/{session_id}`, `GET /v1/coaching_report/{session_id}`, `GET /v1/digest/{user_id}?period=day|week`, `GET /v1/communication_trends/{user_id}?weeks=N`. `compute_session_analytics` worker enhanced to also write a `session_analytics` metrics row (turn/word counts from the transcript, duration, memory/event/highlight counts) and an LLM coaching report (`analytics.coaching` task chain) — both inert until H1. No migration (`session_analytics`/`coaching_reports`/`feedback` already in the live schema). Spec: `docs/superpowers/specs/2026-05-12-v5-port-batch3-analytics-design.md`.
