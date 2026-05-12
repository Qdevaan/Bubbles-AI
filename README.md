# Bubbles

An AI-powered conversation assistant platform built with Flutter (multi-platform client) and FastAPI (Python backend).

Bubbles combines live conversation support, consultant-style Q&A, voice workflows, memory retrieval, and knowledge graph capabilities into one product.

## Base Repository

This repository is a fresh start and is based on the previous codebase:

- https://github.com/Qdevaan/fyp_app

No commit history was carried over. The project files were re-initialized into a new clean history.

## Table of Contents

1. [Project Overview](#project-overview)
2. [Core Features](#core-features)
3. [Architecture](#architecture)
4. [Tech Stack](#tech-stack)
5. [Repository Structure](#repository-structure)
6. [Prerequisites](#prerequisites)
7. [Environment Configuration](#environment-configuration)
8. [Quick Start](#quick-start)
9. [Running the App](#running-the-app)
10. [Backend API Summary](#backend-api-summary)
11. [Database](#database)
12. [Development Commands](#development-commands)
13. [Troubleshooting](#troubleshooting)
14. [Production Notes](#production-notes)

## Project Overview

Bubbles is a full-stack AI assistant application designed around real-time and asynchronous communication support:

- Live Wingman mode for in-session advice.
- Consultant mode for deeper, context-aware Q&A.
- Voice command handling, wake-word support, and speaker enrollment.
- Persistent memory and entity graph extraction across sessions.
- Analytics and coaching reports for communication improvement.

The frontend is a Flutter app (Android, iOS, Web, Desktop), and the backend is a FastAPI service that integrates with Supabase, Groq, LiveKit, and embedding-based retrieval.

## Core Features

- Multi-mode AI interactions:
  - Live wingman advice during active conversations.
  - Consultant Q&A (blocking and streaming).
- Voice capabilities:
  - Voice command intent routing.
  - LiveKit token issuance for real-time sessions.
  - Voice enrollment endpoint for speaker embedding.
- Long-term memory and context:
  - Vector-based memory retrieval.
  - Knowledge graph updates from extracted entities and relations.
- Session intelligence:
  - Session logs and summaries.
  - Sentiment and turn-level analytics.
  - Auto-generated coaching reports.
- Broad app surface areas in Flutter:
  - Sessions, consultant, entities, graph explorer, health dashboard, tasks, expenses, integrations, smart-home, and more.

## Architecture

High-level flow:

1. Flutter client authenticates users and manages UI state with Provider.
2. Client calls FastAPI endpoints under `/v1` for AI, sessions, voice, analytics, and entities.
3. Backend orchestrates:
   - LLM calls (Groq)
   - embeddings and memory retrieval
   - graph/entity persistence
   - session and analytics storage in Supabase
4. Real-time voice/video capabilities are supported through LiveKit token generation and client integration.

## Tech Stack

Client (Flutter):

- Flutter / Dart
- Provider state management
- Supabase Flutter
- LiveKit client
- Speech and audio packages (speech_to_text, flutter_tts, record, porcupine_flutter)

Server (Python) — `server/` (Bubbles Brain API v5, async-only):

- FastAPI + Uvicorn (async top to bottom)
- `asyncpg` over PgBouncer; Alembic migrations; repository + Unit-of-Work layer
- LLM router with per-provider circuit breaker: Gemini → Cerebras → Groq (per task)
- ARQ workers over Redis for background jobs + cron
- Gemini `text-embedding-004` embeddings (bge-small ONNX offline fallback)
- Groq Whisper STT + Edge-TTS; LiveKit tokens
- structlog JSON logs, Prometheus `/metrics`, Sentry, OpenTelemetry; atomic Lua token-bucket rate limiting
- `uv` (deps), `ruff`, `mypy --strict`, `pytest`

> The previous backend (`server_v2/`, sync `supabase-py` + `networkx` + APScheduler) is retired — see `Documentation/server-vs-server_v2-review.md`. It now lives at `legacy/server_v2/` for reference only.

Infrastructure:

- Docker / Docker Compose for backend containerization
- Supabase as primary data platform

## Repository Structure

```text
fyp_app/
|- lib/                     # Flutter app code (screens, providers, services, models)
|- assets/                  # App assets (logos, text, wake-word model)
|- server/                  # Bubbles Brain API v5 (active backend) — see server/README.md
|  |- src/bubbles/          # application code (api, ai, db, jobs, voice, core)
|  |- alembic/              # database migrations (versioned, reversible)
|  |- tests/                # unit / integration / e2e
|  |- ops/                  # Grafana dashboard JSON, alert rules
|  |- pyproject.toml        # deps + tooling (uv, ruff, mypy, pytest)
|  |- Dockerfile            # multi-stage, distroless (runtime + worker targets)
|  |- docker-compose.yml    # dev: app + redis + caddy
|- legacy/server_v2/        # retired previous backend, kept for reference only
|- Documentation/
|  |- db_schema_final_v2.sql # Unified database schema reference
|- env/                     # Local environment files (ignored by git)
|- android/ ios/ web/ macos/ linux/ windows/
```

## Prerequisites

Install the following before local development:

- Flutter SDK (latest stable)
- Dart SDK (included with Flutter)
- Python 3.11+
- Pip
- Docker Desktop (optional, for containerized backend)
- Supabase project (URL + keys)
- Groq API key
- LiveKit credentials (if using realtime voice/video flows)

## Environment Configuration

Create this file:

`env/.env`

Recommended variables:

```env
# Supabase
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_KEY=
SUPABASE_SERVICE_KEY=

# Groq
GROQ_API_KEY=

# Deepgram (optional for STT flows)
DEEPGRAM_KEY=

# LiveKit
LIVEKIT_URL=
LIVEKIT_API_KEY=
LIVEKIT_API_SECRET=

# CORS (comma-separated origins or *)
ALLOWED_ORIGINS=*
```

Notes:

- The Flutter app attempts to load `env/.env` in development.
- For production Flutter builds, prefer `--dart-define` for sensitive values.
- The backend loads env values from `env/.env` first, with fallback to `server/.env`.

## Quick Start

### Option A: Run Backend with Docker (recommended)

From the `server` directory:

```bash
docker compose up --build
```

Backend will be available at:

- `http://localhost:8000`
- Health check: `http://localhost:8000/health`

### Option B: Run Backend Locally (without Docker)

From the `server` directory (needs [`uv`](https://docs.astral.sh/uv/)):

```bash
uv sync                # create venv + install deps from pyproject/uv.lock
cp .env.example .env   # fill in secrets
make dev               # uvicorn --reload on :8000
```

`make test` runs `ruff` + `mypy --strict` + `pytest`; `make migrate` applies Alembic migrations. Full DX in `server/README.md`. Background jobs (ARQ worker) run via the `worker` service in `docker-compose.yml`.

## Running the App

From the repository root:

```bash
flutter pub get
flutter run
```

If you want to inject secrets at runtime (recommended for release and CI):

```bash
flutter run \
  --dart-define=SUPABASE_URL=your_supabase_url \
  --dart-define=SUPABASE_ANON_KEY=your_supabase_anon_key
```

## Backend API Summary

Base:

- Root: `GET /`
- Health: `GET /health`

Versioned business endpoints:

- Sessions
  - `POST /v1/start_session`
  - `POST /v1/process_transcript_wingman`
  - `POST /v1/save_session`
- Consultant
  - `POST /v1/ask_consultant`
  - `POST /v1/ask_consultant_stream`
  - `POST /v1/ask_consultant/batch`
- Voice
  - `POST /v1/getToken`
  - `POST /v1/voice_command`
  - `POST /v1/enroll`
- Analytics
  - `POST /v1/save_feedback`
  - `GET /v1/session_analytics/{session_id}`
  - `GET /v1/coaching_report/{session_id}`
  - `GET /v1/digest/{user_id}`
  - `GET /v1/communication_trends/{user_id}`
- Entities
  - `POST /v1/ask_entity`
  - `GET /v1/graph_export/{user_id}`
  - `DELETE /v1/entities/{entity_id}`
  - `DELETE /v1/sessions/{session_id}`
  - `DELETE /v1/memories/{memory_id}`
- Gamification
  - `GET /v1/gamification/{user_id}`
  - `GET /v1/quests/{user_id}`
  - `GET /v1/rewards/{user_id}`
  - `POST /v1/rewards/{user_id}/redeem`
  - `GET /v1/leaderboard`
  - `POST /v1/leaderboard/{user_id}/opt_in`

## Database

Schema reference:

- `Documentation/db_schema_final_v2.sql`

This schema includes:

- User identity and settings
- Sessions and logs
- Consultant logs and sentiment records
- Entity graph tables
- Tasks, events, health, expenses, trips, integrations
- Analytics and coaching reports

Apply and adapt the SQL to your Supabase/PostgreSQL environment as needed.

## Development Commands

Flutter:

```bash
flutter analyze
flutter test
```

Python server (from `server/`):

```bash
uv sync
make dev
```

Docker backend:

```bash
cd server
docker compose up --build
```

## Troubleshooting

- App fails at startup with Supabase errors:
  - Confirm `SUPABASE_URL` and `SUPABASE_ANON_KEY` are set correctly.
- Backend `/health` returns degraded:
  - Verify DB credentials, `GROQ_API_KEY`, and model download availability.
- CORS issues in web builds:
  - Set `ALLOWED_ORIGINS` to include your frontend origin(s).
- Voice features not working:
  - Validate LiveKit keys and ensure microphone permissions are granted.
- Slow first backend startup:
  - Initial model downloads (torch/sentence-transformers) can take time.
