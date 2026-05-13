# Bubbles Brain API v5 — TODO (to fully retire `server_v2`)

Source of truth for remaining work. Detail + rationale in `Documentation/server-vs-server_v2-review.md` §5–§6. Severity: **P0** = v5 not functionally equivalent / headline feature dead · **P1** = real feature missing, has workaround · **P2** = parity polish · **P3** = ops/hygiene.

Each item gets the usual spec → plan → subagent-driven execution cycle; specs in `docs/superpowers/specs/`.

---

## Order of work

### 1. H1 (P0) — Wire worker enqueues from the API  ← do first

- [x] `end_session` calls `enqueue_session_analytics` (existing helper, stable `_job_id`).
- [x] Wherever the assembled transcript is available, call `enqueue_extract_knowledge`.
- [x] Decide triggers for `enqueue_grammar_scan` (per `check_user_turn`?) and `enqueue_compute_embeddings` (after memory writes? cron?).
- [x] Integration test: end a session → assert the job was enqueued.

**Why first:** `workers/enqueue.py` helpers exist but nothing in `src/` imports them. Until wired, Batch 1's `session_entities` population and Batch 3's `compute_session_analytics` enhancement do nothing — no titles/summaries/highlights/coaching reports/entity links/embeddings are ever produced. Only cron (`seed_quests`, `send_reminders`) runs. Small change, biggest unlock.

### 2. H2 + H3 (P0) — Per-turn store + `process_transcript_wingman`

- [x] Decide: (a) add `session_turns` table + `log_turn` route; or (b) "client supplies full transcript at `end_session`" and document `session_replay` + per-turn metrics as permanently out of scope.
- [x] Alembic 0004 `session_logs` migration; `end_session` assembles transcript from rows, then enqueues (see H1).
- [x] Port `POST /v1/process_transcript_wingman` — advice via `LLMRouter` `wingman.*` tasks; persist each turn (H2(a)).
- [x] Port `GET /v1/session_replay/{session_id}`.
- [x] Worker fills per-turn `session_analytics` columns (`average_latency_ms`, `avg_advice_latency_ms`, `avg_sentiment_score`, `dominant_sentiment`) and `sentiment_trend`.
- [x] `save_session` now actually persists (v2 parity, batch-upload path for the Flutter offline buffer). Schema: `{session_id?, transcript?, logs[], title?, mode?, idempotency_key?, is_ephemeral?, user_id?(legacy/ignored)}` → `{status: "saved"|"ephemeral_skipped", session: SessionOut|null}`. Logs in v2/Flutter shape (`speaker`+`text`); auto-creates a session when `session_id` is absent; ends the session in place when it's present; runs the same `_enqueue_post_session_jobs` as `end_session`. `is_ephemeral` short-circuits before any DB write.

**Why:** v5 stores no per-turn content today. No `session_logs`/`sentiment_logs` writer; `process_transcript_wingman` (the actual live-wingman product feature) not ported; `suggest_reply` is only a one-shot stand-in.

### 3. H4 (P1) — Speaker HTTP routes

- [x] `POST /v1/enroll` — enqueue the existing `speaker_enroll` job.
- [x] `POST /v1/identify_speaker` — synchronous embedding compare vs stored vectors.
- [x] `/v1/identify_speaker` entry in `api/middleware.py` matches a real route now.

### 4. H5 (P1) — Stop truncating the coaching transcript

- [x] `ai/extraction._truncate` replaced by `prepare_transcript` (map-reduce, 32 KB budget, segment-condense with summary join, up to 3 passes, hard-clip only as last resort). Was: kept only the last 4000 chars → dropped every conversation's opening → skewed talk-time %, topics, tone.

### 5. H6 (P2) — XP-award worker + gamification completeness

- [x] `add_xp`: daily XP cap (500), streak-milestone bursts, first-action-today bonus.
- [x] Increment streak counters (`current_streak`, `longest_streak`, `streak_freezes`) — currently read by the profile but never written.
- [x] Achievement-detection worker → populate `user_achievements` → `badges[]` (currently always `[]`).
- [x] Add v2's `stats{}` block to the profile response.
- [x] Quest mission endpoints: `POST /v1/quests/{uid}/{uqid}/answer` (question-set), `POST /v1/quests/{uid}/{uqid}/attach_session` (conversation).

### 6. H7 / H8 (P2)

- [x] H7 — port `GET /v1/performance_summary/{user_id}`.
- [x] H8 — `backfill_session_entities` one-off worker job (after H1; pre-`0002` sessions have no entity links).

### 7. H9–H14 (P3) — Ops / hygiene

- [x] H9 — ElevenLabs premium-TTS fallback behind the same interface as Edge-TTS.
- [x] H10 — ARQ dead-letter queue + Prometheus alert on `arq_jobs_failed`.
- [x] H11 — Locust load test wired into `.github/workflows/load-test.yml` — nightly + workflow_dispatch against `secrets.STAGING_URL` / `secrets.STAGING_BUBBLES_TOKEN` (clean-skip when secrets are unset).
- [x] H12 — `.github/workflows/ci.yml` `integration` job sets `RUN_INTEGRATION=1`; testcontainers DeprecationWarning fixed (`filterwarnings` ignore in `pyproject.toml`).
- [x] H13 — `scripts/check_schema_drift.py` (tolerant column-inventory comparator vs `Documentation/db_schema.sql`, since the prod dump has RLS / `auth` schema / `uuid_generate_v4()` that the Alembic-built DB doesn't) + `migrations` CI job: builds Alembic head, applies baseline.sql, runs the comparator, then round-trips `downgrade base → upgrade head`.
- [x] H14a — pick one `idempotency_key` `max_length` (currently `200` in `SaveFeedbackRequest`, `128` elsewhere).
- [x] H14b — `coaching_report.tone_scores` filter `isinstance(v, int | float)` also accepts `bool` — exclude `bool`.
- [x] H14c — `core/transcript._SPEAKER_RE` mis-parses a bare line containing `https://...` as speaker `"https"` — guard against `/`-containing or long prefixes.

### 8. Final retirement

- [x] **2026-05-13** — Doc-noted follow-ups (closed): rolling-summary every-N-turns (`workers/jobs/rolling_summarize.py` + `_ROLLING_SUMMARY_EVERY_N_TURNS=20` in `wingman.py`); multiplayer turns (`StartSessionRequest.is_multiplayer` → `sessions_repo.start` → `SessionOut.is_multiplayer`); LLM transcript-evaluator for conversation missions (`analytics.mission_eval` chain + `evaluate_conversation_mission` + `complete_conversation_quest(eval_passed=, eval_reason=)`); consultant `ask_consultant`/`save_memory` quest hooks (commit `a67775c`).
- [ ] *(Skipped — deliberate)* prod `sentiment_logs` table — botched dual-column shape (`sentiment_score`+`score`, `emotion_label`+`label`); canonical data lives on `session_logs`.
- [ ] When everything above lands and nothing references `legacy/server_v2/`: `git rm -r legacy/server_v2/`.
- [ ] Live cutover per `Documentation/server-blueprint.md` §18 (subdomain → flip `kUseApiV5` → 48 h soak → repoint DNS).

---

## API keys / credentials needed

Backend reads these from env (`env/.env`, fallback `server/.env`); see `server/src/bubbles/settings.py`. Frozen settings — required ones fail fast at startup.

### Required (app won't start without them)

- [x] **`SUPABASE_URL`** — Supabase project URL. *Supabase dashboard → Project Settings → API.*
- [x] **`SUPABASE_SERVICE_KEY`** — Supabase `service_role` secret key. *Same page. Server-side only — never ship to the Flutter client.*
- [ ] **`SUPABASE_JWKS_URL`** — JWKS endpoint for verifying Supabase JWTs (`https://<ref>.supabase.co/auth/v1/.well-known/jwks.json`).
- [ ] **`DATABASE_URL`** — asyncpg DSN to Supabase **PgBouncer** (port `6543`, transaction mode). *Supabase → Database → Connection string → "Connection pooling".*
- [ ] **`REDIS_URL`** — Redis/Upstash connection URL (cache, rate-limit, ARQ queue). Free tier: Upstash. Defaults to `redis://localhost:6379/0` but a real one is required in deploy.

### AI providers (need ≥1 LLM key for anything useful; all three recommended for the failover chain)

- [x] **`GEMINI_API_KEY`** — Google AI Studio (`aistudio.google.com`). Used for the consultant model **and** `text-embedding-004` embeddings. Free tier. First in the LLM chain.
- [x] **`CEREBRAS_API_KEY`** — Cerebras Cloud (`cloud.cerebras.ai`). Wingman model. Free tier. Second in the chain.
- [x] **`GROQ_API_KEY`** — GroqCloud (`console.groq.com`). Wingman fallback model **and** Whisper STT (`whisper-large-v3-turbo`). Free tier. Third in the chain + STT.

### Voice (only if using realtime audio / LiveKit)

- [x] **`LIVEKIT_URL`**, **`LIVEKIT_API_KEY`**, **`LIVEKIT_API_SECRET`** — LiveKit Cloud (`cloud.livekit.io`) or self-hosted. Needed for `getToken` / realtime sessions. (TTS = Edge-TTS, needs no key. STT = Groq Whisper, uses `GROQ_API_KEY`.)
- [ ] **`ELEVENLABS_API_KEY`** — ElevenLabs (`elevenlabs.io`). Optional. When set, the `premium` / `premium-male` TTS presets use ElevenLabs; falls back to Edge-TTS on any failure or when unset.

### Push notifications (optional)

- [ ] **`FIREBASE_CREDENTIALS_JSON`** — FCM service-account JSON (as a string) for `send_reminders`. *Firebase console → Project Settings → Service accounts.*

### Observability (optional in dev; `SENTRY_DSN` **required when `APP_ENV=production`**)

- [x] **`SENTRY_DSN`** — Sentry project DSN. Hard requirement in prod (startup invariant).
- [ ] **`OTEL_EXPORTER_OTLP_ENDPOINT`** — OTLP traces collector endpoint (e.g. Grafana Tempo / Honeycomb). Optional.
- [ ] **`LOGTAIL_SOURCE_TOKEN`** — Better Stack / Logtail source token for log shipping. Optional.

### Flutter client (separate from the backend keys above)

- [x] **`SUPABASE_URL`** + **`SUPABASE_ANON_KEY`** — the *anon* (publishable) key, not the service key. Loaded from `env/.env` in dev, `--dart-define` for release builds.
- [x] **`LIVEKIT_URL`** (+ token comes from the backend `getToken`) — if the client does realtime audio.

> **Cost target:** Gemini (free) + Cerebras (free) + Groq (free) + Supabase (free) + Upstash Redis (free) + Edge-TTS (no key) → ~$0/mo. Only LiveKit and ElevenLabs are potential paid items, both optional.

---

## Done

- [x] Batch 1 — entity routes (`graph_export`, `entity_timeline`, `DELETE sessions/{id}`, `DELETE memories/{id}`; `session_entities` table, Alembic `0002`). Spec: `2026-05-11-v5-port-batch1-entity-routes-design.md`.
- [x] Batch 2 — gamification HTTP (`gamification/{user_id}`, `quests/{user_id}`, `rewards/{user_id}`+`/redeem`, `leaderboard`+`/opt_in`; `xp_transactions`/`achievements`/`user_achievements`, Alembic `0003`; `core/gamification.py`; ledger-aware idempotent `add_xp`). Spec: `2026-05-12-v5-port-batch2-gamification-design.md`. Remaining: H6.
- [x] Batch 3 — analytics reads + feedback (`save_feedback`, `session_analytics/{id}`, `coaching_report/{id}`, `digest/{user_id}`, `communication_trends/{user_id}`; `compute_session_analytics` worker writes metrics row + LLM coaching report — inert until H1; no migration). Spec: `2026-05-12-v5-port-batch3-analytics-design.md`. Remaining: H1, H2, H5.
