# Bubbles-AI — Tech Stack & Architecture (Poster Brief)

> Reference brief for poster generation. All facts verified against the live codebase
> (`pubspec.yaml`, `server/pyproject.toml`, source tree, Alembic migrations).
> Use this to feed a design tool (e.g. Claude design) for an academic / FYP poster.

---

## 1. One-Line Pitch

**Bubbles-AI** is a cross-platform, AI-powered **conversation & communication-coaching** app.
It listens to real conversations, gives **live in-session coaching** (Wingman), answers deep
questions afterwards (Consultant), tracks growth over time, drills weak spots with
**spaced repetition**, and gamifies the whole journey — all backed by a multi-provider LLM
router and a real-time async backend.

---

## 2. High-Level Architecture (3 tiers)

```
┌─────────────────────────────────────────────────────────────────┐
│                     CLIENT — Flutter App                          │
│   Android · iOS · Web · Windows · macOS · Linux                   │
│                                                                   │
│   Presentation (Screens + Widgets)                                │
│        ↓                                                          │
│   State (Riverpod / Provider)                                     │
│        ↓                                                          │
│   Repositories  →  Custom Cache (SQLite + SharedPrefs, SWR)       │
│        ↓                                                          │
│   Services (Voice, STT/TTS, Wake-word, API client, Auth)          │
└───────────────┬──────────────────────────────┬──────────────────┘
                │  REST / SSE / WebSocket        │  Realtime audio/video
                ▼                                ▼
┌─────────────────────────────────────┐   ┌──────────────────────┐
│   BACKEND — FastAPI "Brain API v5"   │   │   LiveKit (A/V rooms) │
│   (async-first, Python 3.12)         │   └──────────────────────┘
│                                       │
│   API v1  →  AI Router  →  LLM Providers (Gemini · Cerebras · Groq)
│   Auth (JWT)   DB Repos   ARQ Workers (background jobs)            │
└───────┬───────────────┬───────────────┬──────────────────────────┘
        ▼               ▼               ▼
  ┌───────────┐   ┌───────────┐   ┌──────────────────────────────┐
  │ Supabase  │   │   Redis    │   │  Observability                │
  │ Postgres  │   │ cache +    │   │  Sentry · Prometheus ·        │
  │ + Auth+RLS│   │ ARQ queue  │   │  OpenTelemetry · Grafana      │
  └───────────┘   └───────────┘   └──────────────────────────────┘
```

**Pattern:** Clean-ish layered architecture — Presentation → State → Repository → Service
on the client; API → Router → Provider + Repository + Worker on the server.
**Resilience:** per-provider circuit breakers, fallback chains, Redis token-bucket rate
limiting, idempotent background jobs.

---

## 3. Tech Stack at a Glance (poster table)

| Layer | Technology |
|-------|-----------|
| **Mobile / Client** | Flutter 3.10+ · Dart 3.10+ |
| **Client State** | Riverpod / Provider |
| **Client Storage** | SQLite (sqflite) · SharedPreferences (custom SWR cache) |
| **Voice (client)** | speech_to_text · flutter_tts · Picovoice Porcupine (wake-word) · LiveKit |
| **Backend** | FastAPI (async) · Uvicorn + Gunicorn · Python 3.12 |
| **Data Validation** | Pydantic v2 |
| **Database** | Supabase (PostgreSQL + Row-Level Security) |
| **DB Access** | SQLAlchemy 2 (async) · asyncpg · Alembic migrations |
| **Cache / Queue** | Redis · ARQ (async job queue) |
| **AI / LLM** | Google Gemini · Cerebras · Groq (via custom LLM Router) |
| **Embeddings** | Gemini text-embedding-004 (ONNX local fallback) |
| **Speech** | Groq Whisper (STT) · Edge-TTS (TTS) |
| **Realtime** | LiveKit · WebSockets · Server-Sent Events |
| **Grammar / NLP** | LanguageTool · NetworkX (knowledge graph) |
| **Observability** | Sentry · Prometheus · OpenTelemetry · Grafana · structlog |
| **DevOps** | Docker · Docker Compose · Caddy · uv · Ruff · mypy · pytest |

---

## 4. Frontend — Flutter (detail)

- **SDK:** Flutter `>=3.10.1`, Dart `>=3.10.1`. Single codebase → 6 platforms.
- **Architecture:** layered —
  - **Presentation:** 25+ screens, reusable widget library
  - **State:** 15+ Riverpod/Provider state holders
  - **Data:** 11 repositories over a custom `BaseRepository` cache
  - **Cache policies:** NetworkOnly · CacheFirst · **Stale-While-Revalidate**
  - **Services:** 25 services (API client, auth, voice, hydration, notifications)
- **Key packages:**
  - State/UI: `provider`, `flutter_animate`, `fl_chart`, `force_directed_graphview`
  - Backend/Auth: `supabase_flutter`, `flutter_dotenv`
  - Voice: `speech_to_text`, `flutter_tts`, `record`, `flutter_sound`,
    `porcupine_flutter` (wake-word), `livekit_client`
  - Storage: `sqflite`, `shared_preferences`, `path_provider`
  - Other: `webview_flutter`, `flutter_markdown_plus`, `pdf`,
    `flutter_local_notifications`, `connectivity_plus`
- **Branding:** Manrope font bundled locally (offline-first, no CDN); WebP logos;
  native splash via `flutter_native_splash`.

---

## 5. Backend — FastAPI "Brain API v5" (detail)

- **Stack:** async-first FastAPI on Python 3.12, served by Uvicorn workers under Gunicorn.
- **22 API modules / 40+ endpoints** under `/v1`, grouped by feature:
  Sessions, Wingman, Consultant, Analytics, Voice, Speaker, STT, Grammar,
  Entities, Memories, Gamification, Drills, Scenarios, Dashboard, Persona.
- **AI Router (`ai/router.py`):** routes each task to an ordered chain of LLM providers
  with **per-provider circuit breakers** and automatic fallback.

  | Task | Model | Provider |
  |------|-------|----------|
  | Consultant (Q&A, streaming) | gemini-2.5-flash | Google Gemini |
  | Wingman (real-time advice) | llama3.1-8b | Cerebras → Groq |
  | Speech-to-text | whisper-large-v3-turbo | Groq |
  | Embeddings | text-embedding-004 | Gemini (ONNX fallback) |

- **Background workers (ARQ, 12 jobs):** embeddings, grammar scan, sentiment,
  knowledge extraction, rolling summaries, session analytics, speaker ID/enrollment,
  achievement detection, reminders — all **idempotent**.
- **Core infra:** circuit breaker, Redis Lua token-bucket rate limiter, retry (Tenacity),
  ULID IDs, structlog, Prometheus metrics, OpenTelemetry tracing.
- **Tooling:** `uv` (deps), Ruff (lint), mypy `--strict`, pytest (unit/integration/e2e),
  Locust (load), Docker multi-stage build (runtime + worker targets).

---

## 6. Data & AI

- **Database:** Supabase PostgreSQL with Row-Level Security; 7 Alembic migrations.
  Core entities: users, profiles, **sessions**, **turns**, **entities**, **memories**,
  feedback, plus feature tables: `session_entities`, `quests`, `achievements`,
  `leaderboard_entries`, `session_logs`, `voice_enrollments`, `scenarios`, `drill_cards`.
- **Knowledge graph:** LLM extracts entities + relations from transcripts; modeled with
  **NetworkX**, persisted via entity link tables, browsable in an interactive graph explorer.
- **Embeddings / semantic memory:** Gemini embeddings stored as Postgres vectors for
  semantic recall; local ONNX (all-MiniLM-L6-v2) fallback.

---

## 7. Core Features (for poster highlights)

| Feature | What it does |
|---------|--------------|
| 🎙️ **Live Wingman** | Real-time, in-conversation coaching from the live transcript |
| 💬 **AI Consultant** | Deep async Q&A about your conversations (streaming) |
| 📈 **Progress Dashboard** | Longitudinal metrics: sessions, sentiment, talk-time, XP |
| 🃏 **Spaced-Repetition Drills** | Leitner-box review of weak spots / past mistakes |
| 🎚️ **Live Confidence Meter** | Real-time confidence feedback during a session |
| 🎮 **Gamification** | Quests, achievements, rewards, leaderboard, XP & streaks |
| 🕸️ **Knowledge Graph Explorer** | Browse people/topics/entities mentioned over time |
| 🗣️ **Voice & Speaker ID** | Wake-word, STT/TTS, speaker enrollment & identification |
| ✍️ **Grammar & Sentiment** | Automatic grammar checks and per-session sentiment |
| 🎭 **Scenario Generator** | AI-generated roleplay practice scenarios |

---

## 8. Suggested Poster Talking Points

- **"One codebase, six platforms"** — Flutter targets Android, iOS, Web, Windows, macOS, Linux.
- **"Multi-provider AI with zero-downtime fallback"** — Gemini + Cerebras + Groq behind a
  circuit-breaking router.
- **"Real-time + async"** — live coaching over WebSocket/LiveKit, heavy lifting offloaded to
  Redis-backed ARQ workers.
- **"Offline-first client"** — Stale-While-Revalidate cache over local SQLite.
- **"Production-grade observability"** — Sentry, Prometheus, OpenTelemetry, Grafana from day one.

---

## 9. Visual / Design Notes for the Poster

- **Brand font:** Manrope (weights 400/500/600/700).
- **Suggested diagram:** the 3-tier block diagram in §2 — Client → Backend → (Postgres / Redis / AI).
- **Icon set ideas:** speech bubble (brand), waveform (voice), graph nodes (knowledge graph),
  flame (streaks/gamification), shield (RLS/security).
- **Color cue:** "Bubbles" → rounded, friendly, conversational; pair a calm primary with an
  energetic accent for the AI/coaching angle.
