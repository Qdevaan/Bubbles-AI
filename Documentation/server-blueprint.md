# Bubbles-AI Server v3 — Implementation Blueprint

**Status:** Plan • **Date:** 2026-05-10 • **Owner:** Backend
**Scope:** Full rewrite of `server_v2/` into `server/` (Bubbles Brain API v5).
**Goals (in priority order):** correctness → reliability → low p95 latency → low cost (free tier only) → developer ergonomics.
**Non-goals:** behavioural parity bugs, placeholder code, "TODO later" comments, paid SaaS.

---

## 1. Existing System (what we replace)

| Layer | Today (`server_v2/`) | Pain points |
|---|---|---|
| Framework | FastAPI + Uvicorn (2 workers) | Sync-leaking endpoints, heavyweight startup, model load on import |
| Auth | Supabase JWT, manual ownership checks per route | Repeated boilerplate, easy to miss |
| DB | `supabase-py` (sync) singleton | Sync calls inside async handlers, no pooling control |
| LLMs | Cerebras + Gemini + Groq, hand-rolled retry | No circuit breaker, no per-provider budgets, no streaming for batch |
| Vector | `sentence-transformers` MiniLM in-process | Model loaded at boot, RAM hog, CPU-bound on request thread |
| Graph | `networkx` per-user in-memory | Lost on restart, not shared across workers |
| STT | Deepgram WS proxy | Vendor lock-in on free trial only |
| TTS | Deepgram REST proxy | Same |
| Voice ID | SpeechBrain + torchaudio | Cold start 8–15 s, blocks event loop |
| Cache / RL | Redis (optional) + SlowAPI | Mixed in-memory fallback hides bugs in prod |
| Jobs | `apscheduler` in-process | Dies with worker, no distributed locking |
| Deploy | Docker Compose on a VM, `deploy.sh` | OK but no zero-downtime, no health gates |
| Observability | `print` + Uvicorn access log | Nothing to debug an incident with |

Routes carried forward (semantics preserved): `analytics`, `consultant`, `entities`, `gamification`, `grammar`, `health`, `performance`, `persona`, `sessions`, `stt`, `voice`.

---

## 2. Target Architecture

```
                                ┌──────────────────────────┐
                                │  Flutter client (mobile) │
                                └──────────────┬───────────┘
                                               │ HTTPS / WSS (mTLS-optional)
                                               ▼
                       ┌────────────────────────────────────────────┐
                       │  Caddy 2   (auto-TLS, HTTP/3, gzip+br)     │
                       └──────────────┬─────────────────────────────┘
                                      │ unix-socket
                                      ▼
                  ┌────────────────────────────────────────────────┐
                  │  Gunicorn  →  N × Uvicorn (uvloop+httptools)   │
                  │  FastAPI app (async-only handlers)             │
                  └──┬──────────┬──────────┬───────────┬───────────┘
                     │          │          │           │
                     ▼          ▼          ▼           ▼
              ┌──────────┐ ┌─────────┐ ┌────────┐ ┌─────────────┐
              │ Postgres │ │  Redis  │ │  ARQ   │ │ LLM Router  │
              │+pgvector │ │ (cache, │ │ worker │ │(Cerebras /  │
              │ (Supabase│ │ rate-l, │ │ pool   │ │ Groq /      │
              │  free)   │ │ pubsub) │ │        │ │ Gemini)     │
              └──────────┘ └─────────┘ └────┬───┘ └─────────────┘
                                            │
                            ┌───────────────┴────────────────┐
                            ▼                                ▼
                    ┌────────────────┐               ┌──────────────┐
                    │ Whisper / Groq │               │  LiveKit     │
                    │   STT (free)   │               │  Cloud free  │
                    └────────────────┘               └──────────────┘
```

### 2.1 Key design rules

1. **Async-only, top to bottom.** No blocking call ever runs on the event loop. Anything CPU- or IO-blocking goes to ARQ workers or `asyncio.to_thread`.
2. **Single source of truth = Postgres.** Per-user graphs live in `entities` + `entity_edges` (already exists). NetworkX is rebuilt on demand from Postgres into a per-request LRU cache.
3. **Stateless app processes.** Any state survives in Redis or Postgres. Lets us scale workers, drop them, restart without losing in-flight context.
4. **No model loaded at import time.** Embeddings + speaker ID are loaded lazily inside ARQ workers, not in the API process.
5. **One auth path.** A single dependency `CurrentUser` resolves JWT → user_id and ownership of any path-bound resource. No per-route duplication.
6. **Provider failover everywhere.** Every external dependency (LLM, STT, TTS, push) is behind a Router with a circuit breaker, per-provider budget, and explicit fallback chain.
7. **Cache by content hash.** Anything deterministic (embeddings, prompt+context hashes, persona renders) is cached in Redis with a stable hash key.
8. **Streaming first.** `/v1/consultant/ask` defaults to Server-Sent Events (SSE). Non-stream path is a thin collector over the stream.

---

## 3. Free-Tier Infrastructure

| Concern | Pick | Free quota that matters | Why |
|---|---|---|---|
| Compute | **Oracle Cloud — Always Free**: 4 ARM Ampere cores, 24 GB RAM, 200 GB block | Forever-free, no card hold | Fits whole stack incl. Whisper-tiny on CPU |
| | Backup: Fly.io (256 MB shared × 3) | 3 small VMs forever | Hot standby for blue/green |
| Postgres + pgvector | **Supabase Free** | 500 MB DB, 5 GB egress/mo, 50 K MAU | Already wired, includes Auth + Storage |
| Redis | **Upstash Redis (regional)** | 10 K cmd/day (per pair), 256 MB | TLS, REST + native; we use native protocol |
| | Local fallback: Redis 7-alpine on the VM | unlimited | Default in dev; primary on Oracle box |
| Object storage | **Supabase Storage Free** | 1 GB | Audio uploads, voice prints |
| LLM #1 (consultant, streaming) | **Gemini 2.5 Flash** free tier | 1.5 K req/day | Highest quality at 0 USD |
| LLM #2 (wingman, JSON-mode, fast) | **Cerebras Cloud** free | 1 M tokens/day Llama 3.1 8B | Sub-200 ms TTFT |
| LLM #3 (fallback + extraction) | **Groq** free | high RPM Llama 3.1 8B Instant | Fastest token/sec |
| Embeddings | **Gemini text-embedding-004** | free tier | Drops the 400 MB MiniLM blob |
| | Local fallback: `bge-small-en-v1.5` quantized | offline | Used when Gemini is down |
| STT | **Groq Whisper-large-v3-turbo** | free, ~10× realtime | Replaces paid Deepgram |
| | Local fallback: `faster-whisper` tiny.en on CPU | offline | Used in dev / circuit-open |
| TTS | **Microsoft Edge TTS** (`edge-tts`) | unlimited, no key | Natural voices, free |
| | Backup: ElevenLabs free 10 K char/mo | for premium voices | Optional per-persona |
| Realtime voice | **LiveKit Cloud Free** | 10 GB BW/mo | Already in app |
| Speaker ID | SpeechBrain ECAPA on ARQ worker | offline | Lazy-loaded once per worker |
| Grammar | `language_tool_python` server-mode | offline | Same as today |
| Push | Firebase Cloud Messaging | free | Same as today |
| Auth | Supabase Auth | free | Same as today |
| TLS / proxy | **Caddy 2** | free | Auto Let's Encrypt, HTTP/3 |
| CI/CD | GitHub Actions | 2 K min/mo | Lint, test, build, deploy |
| Container registry | GHCR | free for public, generous for private | Pulls onto Oracle VM |
| Logs | **Better Stack (Logtail)** | 1 GB/mo, 3-day retention | Structured JSON sink |
| Metrics | **Grafana Cloud Free** | 10 K series, 50 GB logs | Prometheus remote-write |
| Errors | **Sentry Free** | 5 K events/mo | Crash + perf traces |
| Tracing | **Grafana Tempo Free** | included | OTLP from app + workers |
| Uptime | **UptimeRobot Free** | 50 monitors @ 5 min | Hits `/health/ready` |
| Secrets | `.env` on VM + age-encrypted in repo | free | Simple, auditable |

---

## 4. Repo Layout

```
server/                                # new top-level (replaces server_v2/)
├── pyproject.toml                     # uv + hatchling, ruff, mypy, pytest config
├── uv.lock
├── Dockerfile                         # multi-stage, distroless final
├── docker-compose.yml                 # dev: app + redis + caddy
├── docker-compose.prod.yml            # prod: same + ARQ worker + watchtower
├── Caddyfile
├── .dockerignore
├── .env.example                       # template, no secrets
├── .github/workflows/
│   ├── ci.yml                         # ruff + mypy + pytest + integration
│   └── deploy.yml                     # SSH-deploy to Oracle on tag
├── alembic/                           # migrations (replaces ad-hoc *.sql)
│   ├── env.py
│   └── versions/
├── scripts/
│   ├── seed_quests.py
│   ├── backfill_embeddings.py
│   └── load_test.py                   # k6/locust scenarios
└── src/bubbles/
    ├── __init__.py
    ├── app.py                         # create_app() factory
    ├── lifespan.py                    # startup/shutdown orchestration
    ├── settings.py                    # pydantic-settings, frozen
    ├── deps.py                        # FastAPI dependency providers
    ├── core/
    │   ├── logging.py                 # structlog → JSON → Logtail
    │   ├── tracing.py                 # OpenTelemetry setup
    │   ├── errors.py                  # typed exceptions + handlers
    │   ├── ids.py                     # ULID helpers
    │   ├── time.py                    # tz-aware utc helpers
    │   ├── cache.py                   # Redis-backed L1/L2 cache
    │   ├── ratelimit.py               # Redis token-bucket
    │   ├── circuit.py                 # circuit breaker primitive
    │   ├── retry.py                   # tenacity policies (jitter, budgets)
    │   ├── hashing.py                 # blake3 cache keys
    │   └── concurrency.py             # bounded gather, semaphores
    ├── db/
    │   ├── pool.py                    # asyncpg pool to Supabase pgbouncer
    │   ├── repo/                      # one repo per aggregate
    │   │   ├── sessions.py
    │   │   ├── entities.py
    │   │   ├── personas.py
    │   │   ├── grammar.py
    │   │   ├── gamification.py
    │   │   └── memories.py
    │   └── unit_of_work.py            # tx scope per request
    ├── auth/
    │   ├── jwt.py                     # Supabase JWKS verify (cached)
    │   ├── current_user.py            # CurrentUser dependency
    │   └── ownership.py               # path → resource owner check
    ├── ai/
    │   ├── router.py                  # provider fallback chain
    │   ├── providers/
    │   │   ├── gemini.py
    │   │   ├── cerebras.py
    │   │   ├── groq.py
    │   │   └── base.py                # protocol: complete / stream / json
    │   ├── prompts/                   # jinja2 templates (move from app/prompts)
    │   │   ├── consultant/
    │   │   ├── wingman/
    │   │   └── personas/
    │   ├── prompt_cache.py            # prompt+ctx hash → response cache
    │   ├── embeddings.py              # Gemini + bge fallback
    │   ├── streaming.py               # SSE encoder + token-budget guard
    │   └── extraction.py              # entities/highlights/title/summary
    ├── voice/
    │   ├── stt.py                     # Groq Whisper async client
    │   ├── tts.py                     # Edge-TTS streaming
    │   ├── livekit.py                 # token + room helpers
    │   └── speaker_id.py              # ARQ-only, ECAPA
    ├── graph/
    │   ├── service.py                 # build subgraph, query expansion
    │   └── cache.py                   # per-(user,session) LRU
    ├── domain/
    │   ├── sessions/                  # service + schemas
    │   ├── consultant/
    │   ├── entities/
    │   ├── grammar/
    │   ├── persona/
    │   ├── gamification/
    │   ├── performance/
    │   └── analytics/
    ├── api/
    │   ├── router.py                  # mounts /v1
    │   ├── middleware.py              # request-id, timing, gzip+br
    │   ├── errors.py                  # FastAPI exception handlers
    │   └── v1/
    │       ├── health.py
    │       ├── sessions.py
    │       ├── consultant.py
    │       ├── entities.py
    │       ├── grammar.py
    │       ├── persona.py
    │       ├── gamification.py
    │       ├── analytics.py
    │       ├── performance.py
    │       ├── voice.py
    │       └── stt.py                 # WS endpoint
    ├── workers/
    │   ├── arq_settings.py
    │   ├── jobs/
    │   │   ├── compute_session_analytics.py
    │   │   ├── extract_knowledge.py
    │   │   ├── compute_embeddings.py
    │   │   ├── speaker_enroll.py
    │   │   ├── grammar_scan.py
    │   │   ├── send_reminders.py
    │   │   └── seed_quests.py
    │   └── scheduler.py               # cron-style entries
    └── tests/
        ├── unit/
        ├── integration/               # spins up real Postgres + Redis
        ├── e2e/                       # FastAPI TestClient + recorded LLM
        └── load/
```

---

## 5. Cross-cutting Components (industry-standard, no placeholders)

### 5.1 Settings (`src/bubbles/settings.py`)
- `pydantic-settings` v2, frozen, `model_config = SettingsConfigDict(env_file=".env", extra="forbid")`.
- Required: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `SUPABASE_JWKS_URL`, `DATABASE_URL` (asyncpg DSN to PgBouncer).
- Optional with defaults: provider keys, model names, timeouts, budgets, sample rates.
- One `Settings` instance, injected via `Depends(get_settings)`. No hidden globals.

### 5.2 Logging (`core/logging.py`)
- `structlog` JSON renderer, ISO8601 timestamps, request-id + user-id auto-bound.
- Captures: method, path, status, latency_ms, db_time_ms, ai_time_ms, provider, tokens, cache_hit.
- Sink: stdout → Docker → Vector → Logtail HTTP source.

### 5.3 Tracing (`core/tracing.py`)
- OpenTelemetry SDK, OTLP exporter to Grafana Tempo (free).
- Auto-instrumentation: FastAPI, asyncpg, httpx, redis-asyncio.
- Manual spans around LLM calls with attributes `ai.provider`, `ai.model`, `ai.tokens.in/out`, `ai.cache_hit`.

### 5.4 Error model (`core/errors.py`)
- Typed exceptions: `NotFound`, `Forbidden`, `RateLimited`, `UpstreamUnavailable`, `BadRequest`, `Conflict`, `ValidationFailed`.
- Each maps to a fixed HTTP code and a stable JSON envelope `{error: {code, message, request_id}}`.
- Never leak Postgres, Supabase, or provider error strings to clients.

### 5.5 Caching (`core/cache.py`)
- Two tiers: `cachetools.TTLCache` per-process (microsecond) + Redis (cross-process).
- Helpers: `cache.get_or_set(key, factory, ttl)`, `cache.invalidate(prefix)`.
- Keys are `b3:{ns}:{blake3(payload)}`; namespaces: `prompt`, `embed`, `persona`, `graph`.

### 5.6 Rate limit (`core/ratelimit.py`)
- Redis Lua token-bucket, atomic.
- Tiers: per-IP (anonymous), per-user (authed), per-route (consultant heavier).
- Returns `Retry-After` and `X-RateLimit-*` headers.

### 5.7 Circuit breaker + retry (`core/circuit.py`, `core/retry.py`)
- Half-open with sliding window error rate; trips at 50% errors over last 30 s.
- `tenacity` policies with exponential backoff + jitter, capped attempts, per-provider budget.

### 5.8 DB pool (`db/pool.py`)
- `asyncpg` pool to Supabase via PgBouncer transaction-mode (`?pgbouncer=true`).
- `min_size=2`, `max_size=10` per worker; statement cache disabled (PgBouncer requires it).
- Lifespan: warm pool on startup, drain on shutdown.
- One pool, injected via `Depends(get_pool)`.

### 5.9 Auth (`auth/`)
- JWKS fetched once, cached for 1 h, refreshed on `kid` miss.
- `CurrentUser` dependency: verifies JWT, returns `UserId`, attaches to log context.
- `RequireOwnership(resource)` dependency: checks `resource.user_id == current_user.id` against repo.
- `DEBUG_SKIP_AUTH` only allowed when `APP_ENV=development`; ABORT app start otherwise.

### 5.10 LLM router (`ai/router.py`)
- Per-task chain config (e.g. `consultant.stream` → `[gemini-flash, cerebras-llama, groq-llama]`).
- Each call: pick first non-tripped provider, enforce token budget, time budget, fallback on `UpstreamUnavailable` or timeout.
- Hot-path metric: `ai.fallback_depth` (0 = primary served).
- Streaming: providers normalize to a single async iterator of `Chunk(text, finish_reason, usage)`.

### 5.11 Prompt cache (`ai/prompt_cache.py`)
- Key: `blake3(model + prompt_template_id + render(ctx))`.
- TTL: 1 h for consultant answers, 24 h for extractions.
- Streamed responses are buffered and stored only on full completion (no partial cache pollution).
- Bypass header: `X-No-Cache: 1` (auth-only).

### 5.12 Background jobs (`workers/`)
- ARQ over Redis. One worker container with N coroutines.
- Heavy / slow jobs only: embeddings, knowledge extraction, analytics, speaker enroll, reminders.
- Cron entries: stale-session cleanup, quest seeding, daily digest, mistake retention.
- Idempotent by `job_id = sha256(payload)`; dedupe via Redis SETNX.

### 5.13 Streaming + WS
- SSE for `consultant/ask`, `entities/ask`. `text/event-stream`, heartbeat every 15 s.
- `/v1/stt/stream` WebSocket: client → 16 kHz PCM frames; server forwards to Groq Whisper (or local faster-whisper); emits partial + final JSON events.

---

## 6. API Surface (frozen contract; same paths as today)

All under `/v1`. Bold = behaviour change.

| Method | Path | Notes |
|---|---|---|
| GET | `/health/live` | Liveness — process up |
| GET | `/health/ready` | Readiness — DB+Redis+JWKS reachable |
| GET | `/health/deep` | Pings each LLM provider with 1-token probe (auth-only) |
| POST | `/v1/start_session` | idempotent on `client_session_id` |
| POST | `/v1/save_session` | as today |
| POST | `/v1/end_session` | enqueues analytics job, returns 202 + job id |
| POST | `/v1/process_transcript_wingman` | as today |
| POST | `/v1/sessions/{id}/context` | as today |
| POST | `/v1/suggest_reply` | as today |
| **POST** | `/v1/ask_consultant` | **defaults to SSE; old JSON shape under `?stream=false`** |
| POST | `/v1/ask_consultant/batch` | as today |
| POST | `/v1/ask` | thin alias for legacy clients |
| POST | `/v1/ask_entity` | **graph-aware: extracts entities first, then prompts** (todos #12) |
| GET | `/v1/graph_export/{user_id}` | as today |
| GET | `/v1/entity_timeline/{entity_id}` | as today |
| DELETE | `/v1/entities/{id}` `/sessions/{id}` `/memories/{id}` | as today |
| POST | `/v1/check_user_turn` | as today |
| GET | `/v1/user_mistakes` | as today |
| GET | `/v1/me/persona`, PUT | as today |
| GET | `/v1/gamification/{user_id}` | as today |
| GET | `/v1/quests/{user_id}`, POST `/answer`, `/attach_session` | as today |
| GET | `/v1/rewards/{user_id}`, POST `/redeem` | as today |
| GET | `/v1/leaderboard`, POST `/opt_in` | as today |
| GET | `/v1/performance_summary/{user_id}` | as today |
| GET | `/v1/session_analytics/{id}` | as today |
| GET | `/v1/coaching_report/{id}` | as today |
| GET | `/v1/session_replay/{id}` | as today |
| GET | `/v1/digest/{user_id}` | as today |
| GET | `/v1/communication_trends/{user_id}` | as today |
| POST | `/v1/save_feedback` | as today |
| WS | `/v1/stt/stream` | normalised event schema |
| POST | `/v1/tts` | streaming audio out (`audio/mpeg`) |
| POST | `/v1/process_audio`, `/getToken`, `/voice_command`, `/enroll`, `/identify_speaker` | as today |

---

## 7. Performance Targets (SLO)

| Endpoint | p50 | p95 | p99 | Budget breakdown |
|---|---|---|---|---|
| `/health/*` | 5 ms | 20 ms | 50 ms | — |
| `start_session` | 80 ms | 250 ms | 500 ms | DB 30, JWT 10, ctx warm enq |
| `ask_consultant` (TTFT, SSE) | 350 ms | 900 ms | 1.5 s | router 20, prompt 30, LLM 300 |
| `ask_entity` | 450 ms | 1.2 s | 2 s | extract 200, graph 50, LLM 350 |
| `check_user_turn` | 120 ms | 300 ms | 600 ms | LT 50, LLM 80 |
| `process_transcript_wingman` | 200 ms | 500 ms | 900 ms | extract 150, persist 50 |
| `gamification/*` reads | 60 ms | 150 ms | 300 ms | DB only |
| `tts` (TTFB) | 150 ms | 400 ms | 800 ms | Edge-TTS connect |
| `stt` partial latency | 200 ms | 500 ms | 1 s | Groq Whisper |

Error budget: 99.5% monthly per route.
Deploy gate: load test must hold p95 at 2× expected RPS for 5 min.

---

## 8. Database Plan

- Supabase Postgres + RLS (already enabled per memory 2319).
- Move ad-hoc `*.sql` migrations to **Alembic** (versioned, reversible, DAG).
- New indexes:
  - `entities (user_id, last_mention_at DESC)` — graph rebuild
  - `entity_edges (user_id, src_id) INCLUDE (dst_id, weight)`
  - `consultant_logs (user_id, session_id, created_at)` — replay
  - `user_mistakes (user_id, created_at DESC) WHERE resolved = false`
  - HNSW on `memories.embedding` (`vector_l2_ops`, m=16, ef=64) — already advised
- Add `request_id text` and `idempotency_key text UNIQUE` to write tables that don't have it.
- Connection: asyncpg → PgBouncer (Supabase pooled host, port 6543), transaction mode.

---

## 9. Security

- TLS terminated at Caddy with HSTS, `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`.
- Strict CORS allowlist (Flutter app origin only in prod; `*` in dev).
- All routes require `CurrentUser` except `/health/live`, `/health/ready`, `/v1/getToken` (rate-limited, captcha optional).
- Body size cap 2 MB (10 MB for `/process_audio`, `/enroll`).
- Pydantic `extra="forbid"` on all request schemas.
- Output sanitiser strips AI-generated prompt-injection markers from echoed text.
- Service-role Supabase key never crosses worker boundary; only DB access by anon + RLS for user-scoped reads where possible.
- Secrets: `.env` chmod 600, age-encrypted copy in repo (`.env.age`), CI uses GH Encrypted Secrets.
- `DEBUG_SKIP_AUTH` aborts startup when `APP_ENV != development`.

---

## 10. Observability

- **Logs:** structlog JSON → stdout → Logtail HTTP.
- **Metrics:** `prometheus-client` `/metrics` endpoint (basic-auth) → Grafana Cloud agent scrape; OR direct remote-write.
- **Traces:** OpenTelemetry → Grafana Tempo (OTLP).
- **Errors:** Sentry SDK, sample rate 1.0 in dev / 0.2 in prod, performance traces 0.1.
- **Dashboards (Grafana):** RPS, p95 by route, LLM fallback depth, provider error rate, cache hit rate, DB pool wait, ARQ queue depth.
- **Alerts:**
  - p95 > SLO for 10 min → page
  - error rate > 2% over 5 min → page
  - DB pool saturation > 80% → warn
  - any provider circuit open > 2 min → warn
  - ARQ backlog > 500 → warn

---

## 11. Deployment

- One Oracle ARM VM (4 cores, 24 GB).
- `docker compose -f docker-compose.prod.yml up -d` runs: Caddy, Redis, app (4 workers via Gunicorn+UvicornWorker), ARQ worker, Vector log shipper.
- **Zero-downtime:** rolling restart via `docker compose up -d --no-deps --build server` after health probe passes; Caddy keeps connections; old container drains 30 s.
- **Backups:** Supabase PITR (free tier 7 days) + nightly `pg_dump` to Supabase Storage.
- **DR:** if Oracle dies, redeploy on Fly.io secondary in ≤ 15 min via `fly deploy`; DNS via Cloudflare with 60 s TTL.

---

## 12. Build Phases (concrete tasks, in order)

Each phase ends with green CI (lint + type + tests) and a tag.

### Phase 0 — Repo bootstrap (1 day)
- [ ] `uv init`, `pyproject.toml` with Python 3.12, pinned core deps.
- [ ] Ruff (lint+format), mypy strict, pytest, pytest-asyncio, pytest-postgresql, pytest-redis.
- [ ] `.editorconfig`, `.gitattributes`, `.gitignore`.
- [ ] Pre-commit hooks: ruff, mypy, end-of-file-fixer, no-secrets.
- [ ] `make dev` / `make test` / `make lint` / `make migrate`.

### Phase 1 — Core infra (2 days)
- [ ] `settings.py`, `logging.py`, `tracing.py`, `errors.py`, `ids.py`, `time.py`.
- [ ] `cache.py`, `ratelimit.py`, `circuit.py`, `retry.py`.
- [ ] FastAPI `create_app()` factory + middleware (request-id, timing, gzip+br, body-size).
- [ ] `db/pool.py` asyncpg pool, healthcheck.
- [ ] `auth/jwt.py` + `auth/current_user.py` with JWKS cache.

### Phase 2 — Persistence + repos (2 days)
- [ ] Alembic init, generate migrations from current `db_schema.sql` snapshot.
- [ ] Repos for: sessions, entities, personas, grammar, gamification, memories.
- [ ] Unit-of-work tx wrapper.
- [ ] Integration tests against ephemeral Postgres (testcontainers).

### Phase 3 — AI router + prompts (2 days)
- [ ] Provider protocol; Gemini, Cerebras, Groq adapters with streaming.
- [ ] Router with per-task chains, circuit breaker, budget.
- [ ] Prompt template loader (Jinja) + persona fragments port.
- [ ] Prompt cache (Redis), embeddings (Gemini + bge fallback).
- [ ] Extraction module (knowledge, highlights, title, summary, mistakes).
- [ ] Replay tests with recorded responses (`vcr.py`-style for HTTP).

### Phase 4 — Domain services (3 days)
- [ ] `consultant`: streaming + non-stream + batch.
- [ ] `entities`: graph build/query, entity-aware ask flow (todo #12).
- [ ] `grammar`: LT + LLM correction, mistake persistence.
- [ ] `persona`: get/put with role-family classifier.
- [ ] `gamification`: quests, rewards, leaderboard (port logic, keep schemas).
- [ ] `performance`, `analytics`: read endpoints + materialised CTEs.
- [ ] `sessions`: start/save/end/context, idempotency.

### Phase 5 — Voice (2 days)
- [ ] LiveKit token + room helpers.
- [ ] STT WS to Groq Whisper, fallback faster-whisper local.
- [ ] TTS streaming via edge-tts.
- [ ] `process_audio`, `voice_command` (LLM intent classifier).
- [ ] Speaker enroll/identify in ARQ worker.

### Phase 6 — Workers + schedules (1 day)
- [ ] ARQ container, settings, healthcheck.
- [ ] Jobs listed in `workers/jobs/`.
- [ ] Cron schedules.
- [ ] Idempotency + dead-letter queue.

### Phase 7 — Observability + ops (1 day)
- [ ] Prom `/metrics`, OTLP, Sentry, Logtail.
- [ ] Grafana dashboard JSON checked into `ops/`.
- [ ] Alert rules YAML.

### Phase 8 — Deploy (1 day)
- [ ] Multi-stage Dockerfile, distroless final.
- [ ] `docker-compose.prod.yml` with healthchecks + restart policies.
- [ ] Caddyfile w/ auto-TLS.
- [ ] GH Action: build → push GHCR → SSH `docker compose pull && up -d` on tag `v*`.
- [ ] Migration step gated before app rollout.

### Phase 9 — Load + chaos (1 day)
- [ ] k6 scenarios: cold-start, steady, spike, provider-outage simulation.
- [ ] Verify SLOs.
- [ ] Kill-redis, kill-DB, kill-LLM tests; assert graceful 503 with `Retry-After`.

### Phase 10 — Cutover (0.5 day)
- [ ] Run new server side-by-side with `server_v2` on subdomain `api2.bubbles.app`.
- [ ] Flutter feature flag `kUseApiV5` to flip per-environment.
- [ ] Soak 48 h on staging traffic.
- [ ] Flip prod, decommission `server_v2/`, archive branch.

**Total: ~14 working days for a single dev. Parallelisable down to ~7 with two devs (split AI router + voice from domain work).**

---

## 13. Test Strategy

- **Unit:** every pure function, every repo against in-memory Postgres template.
- **Integration:** spin up Postgres + Redis with `testcontainers`. Hit real routes with `httpx.AsyncClient(app=...)`.
- **Contract:** golden JSON snapshots for every v1 endpoint to lock the public schema; fail CI on shape change.
- **AI replay:** record real Gemini/Cerebras/Groq calls once with `pytest-recording`; replay in CI offline.
- **Load:** k6 in `scripts/load_test.py` runs in nightly action against staging.
- **Chaos:** `toxiproxy` between app and DB/Redis in integration tests for timeout + connection-reset cases.
- Coverage gate: 85% lines, 100% on `auth/`, `core/circuit.py`, `core/ratelimit.py`, `ai/router.py`.

---

## 14. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Free-tier LLM quota exhausted under load | high | high | Three-provider chain, per-user daily budget, cache. Auto-fallback to local llama.cpp if all open. |
| Supabase free pool exhaustion | med | high | PgBouncer transaction mode, `max_size=10` per worker, slow-query budget alerts. |
| Oracle Free instance reclaimed | low | high | Fly.io standby with same image, DNS flip. |
| Whisper free quota | med | med | Local `faster-whisper` tiny.en fallback compiled into worker image. |
| Cold start of speaker-id model on first enroll | high | low | Lazy-load + cache in worker, warm via job on deploy. |
| RLS bug exposes another user's data | low | critical | Repos always pass `user_id`; ownership dependency on every route; integration test asserts cross-user 404. |
| `language_tool_python` JVM OOM on ARM | med | med | Cap concurrency (semaphore=2), restart worker if RSS > 1 GB. |

---

## 15. Acceptance Criteria

- [ ] All `/v1/*` endpoints from `server_v2/` respond with same shape (contract snapshots green).
- [ ] p95 SLOs in §7 hit on staging under 2× expected RPS.
- [ ] Zero `print`, zero broad `except Exception:` without re-raise/log, zero TODO comments in `src/`.
- [ ] `mypy --strict` passes. `ruff check` clean. Coverage ≥ 85%.
- [ ] Provider outage simulation: app stays 200/SSE for at least one fallback in chain.
- [ ] Restart of any single container does not drop in-flight HTTP requests (Caddy retries idempotent ones, drains the rest in 30 s).
- [ ] Cold deploy completes in < 90 s including migration.
- [ ] Free-tier monthly cost: **$0**.

---

## 16. Open Decisions (decide before Phase 3)

1. Keep MiniLM local OR fully switch to Gemini embeddings? → **Decided:** Gemini `text-embedding-004` primary; bge-small ONNX behind `embed-local` extra as offline fallback.
2. Default consultant model: `gemini-2.5-flash` (current) vs `gemini-2.5-flash-preview` vs Cerebras Llama-3.1-70B? → **Decided:** `gemini-2.5-flash` primary, Cerebras `llama3.1-8b` second, Groq `llama-3.1-8b-instant` third (configured in `DEFAULT_CHAINS`). Re-benchmark before GA.
3. Graph storage: pure pgvector + edges in Postgres OR add SQLite-backed `kuzu`? → **Decided:** Postgres-only (`entities` + `entity_relations`). Reassess if `entity_timeline` p95 > 500 ms.
4. ARQ vs Dramatiq vs Celery? → **Decided:** ARQ (asyncio-native, Redis-only).
5. Edge-TTS reliability for production volumes? → Ship Edge-TTS as default; ElevenLabs free as a second voice provider behind the same interface (not yet wired — follow-up).

---

## 17. Build Progress (as of this revision)

| Phase | Status | Notes |
|---|---|---|
| 0 — Repo bootstrap | ✅ done | `server/` w/ uv, ruff, mypy strict, pytest, pre-commit, Makefile, CI |
| 1 — Core infra | ✅ done | settings, logging, tracing, errors, cache, ratelimit, circuit, retry, db pool, auth, middleware, health |
| 2 — Persistence + repos | ✅ done | Alembic baseline, UoW, 11 row models, 6 repos, testcontainers integration suites |
| 3 — AI router + prompts | ✅ done | Gemini/Cerebras/Groq adapters (direct HTTP), router w/ per-task chains + breaker, Jinja prompts, prompt cache, embeddings, extraction, SSE |
| 4 — Domain services + routes | ✅ done | sessions, consultant (SSE+JSON+batch), entity-aware ask, persona, grammar; deps + lifespan wiring |
| 5 — Voice | ✅ done | Groq Whisper STT, Edge-TTS, LiveKit tokens, `process_audio`, `voice_command`, WS `/v1/stt/stream` |
| 6 — Workers + schedules | ✅ done | ARQ settings + lifecycle, 7 jobs, idempotency (SETNX), enqueue helpers, cron |
| 7 — Observability + ops | ✅ done | Prometheus `/metrics` + middleware, Sentry, Logtail handler, OTLP, Grafana dashboard JSON, alert rules |
| 8 — Deploy | ✅ done | multi-stage Dockerfile (runtime/worker), Caddyfile (auto-TLS, h3, SSE-safe), prod + dev compose, GH Actions deploy w/ migration gate |
| 9 — Load + chaos | ✅ done | k6 + locust load scripts, deps fail-soft (503 not 500), chaos tests (provider outage, Redis-down degrade) |
| 10 — Cutover | ⏳ pending | runbook below; needs a live deploy + Flutter flag |

Test suite at this revision: **85 unit tests + integration suites** (run with `RUN_INTEGRATION=1`), `ruff` clean, `mypy --strict` clean.

---

## 18. Phase 10 — Cutover Runbook

> Pre-req: Phases 0–9 merged; `bubbles-server` + `bubbles-worker` images pushed to GHCR; Oracle Always-Free VM provisioned with Docker + `/opt/bubbles/{.env, docker-compose.prod.yml, Caddyfile}`.

### 18.1 Stand up v5 side-by-side
1. On the VM: `cd /opt/bubbles && export GHCR_OWNER=<owner> TAG=v5.0.0`.
2. `docker compose -f docker-compose.prod.yml up -d` — `migrate` runs `alembic upgrade head` (baseline `0001` is a no-op against the existing Supabase DB), then `server` + `worker` + `caddy` come up.
3. Point DNS `api2.bubbles.app` at the VM (Cloudflare, 60 s TTL). Caddy auto-issues TLS.
4. Smoke: `curl -fsS https://api2.bubbles.app/health/ready` → 200; `curl https://api2.bubbles.app/health/deep` with a real JWT → providers map populated.
5. `server_v2/` keeps serving `api.bubbles.app` untouched.

### 18.2 Flutter feature flag
- Add `kUseApiV5` (env-driven, default `false`). Resolves the base URL: `false` → `api.bubbles.app` (v2), `true` → `api2.bubbles.app` (v5).
- Behaviour deltas the client must handle:
  - `POST /v1/ask_consultant` now defaults to **SSE** — pass `?stream=false` to keep the old JSON shape, or switch the consultant screen to consume `event: token` / `event: done`.
  - `POST /v1/end_session` returns the updated session synchronously; analytics (title/summary/highlights) land asynchronously via the worker — the client should poll `GET /v1/session_analytics/{id}` or refresh on next open.
  - `POST /v1/ask_entity` returns `{answer, entities[], provider}` — render the cited entities.
  - WS `/v1/stt/stream` event schema: `{"type":"final","text":...}` / `{"type":"error","message":...}`.
- Ship a build with `kUseApiV5=true` to **internal/staging** flavour only.

### 18.3 Soak (48 h)
- Watch the Grafana dashboard (`ops/grafana_dashboard.json`): RPS, p95 by route, error rate, LLM fallback depth, cache hit %, DB pool, ARQ depth.
- Alert rules (`ops/alerts.yml`) page on: 5xx > 2% (5 m), p95 > 1.5 s (10 m), provider circuit open (2 m), DB pool > 80%, ARQ backlog > 500.
- Acceptance to proceed: all §7 p95 SLOs held under real staging traffic; zero unhandled 500s; no provider stuck open > 5 m; free-tier quotas not exhausted.

### 18.4 Flip prod
1. Repoint `api.bubbles.app` → VM (or swap Caddy site block to serve both names). Keep `api2` as an alias.
2. Set `kUseApiV5=true` in the production Flutter flavour; ship the release.
3. Keep `server_v2/` running for 7 days as instant rollback (flip DNS + flag back).

### 18.5 Decommission v2
- After 7 clean days: stop the `server_v2/` container, snapshot its DB (`pg_dump` → Supabase Storage), `git rm -r server_v2/`, remove its CI workflows, archive the `feat/server-v3` branch into `main`.
- Update `CLAUDE.md` / docs: the server lives in `server/`.

### 18.6 Rollback (any stage)
- **Pre-flip:** set `kUseApiV5=false`; v5 keeps running on `api2` for debugging.
- **Post-flip, < 7 days:** DNS `api.bubbles.app` → old v2 host; `kUseApiV5=false` in a hotfix release; investigate v5 offline.
- **Data:** v5 writes to the same Supabase DB as v2 — no data migration to undo. The only forward-only change is any *new* Alembic revision beyond `0001`; each must ship a working `downgrade()`.

---

*End of blueprint. Edit history goes in git. No prose drift.*
