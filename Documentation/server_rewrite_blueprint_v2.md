# Bubbles AI - Server Rewrite Blueprint (Production Spec)

> **Purpose**: Complete, production-grade reference document for rewriting the FastAPI server from scratch.
> Consolidated and fully restructured to integrate security, observability, error handling, and performance patterns.

---

## 1. Executive Summary & Architecture

### 

#### 

Bubbles is a full-stack AI assistant built around **real-time conversation coaching**. The Flutter app (Android/iOS/Web/Desktop) connects to a FastAPI Python backend that provides:

- **Live Wingman** — Real-time advice during active conversations (low-latency 8B model)
- **Consultant** — Deep Q&A with full context retrieval (high-quality 70B model)
- **Voice Commands** — Natural-language intent routing
- **Memory & Knowledge Graph** — Persistent vector memory + entity relationship graphs
- **Analytics & Coaching** — Session metrics, sentiment tracking, coaching reports
- **Voice Enrollment** — Speaker embedding via ECAPA-TDNN model

#### 

```mermaid
graph TB
    subgraph Flutter Client
        A[Screens & Providers] --> B[ApiService]
        B --> C[HTTP / SSE]
    end

    subgraph FastAPI Server
        C --> D[Routes Layer]
        D --> E[Services Layer]
        E --> F[Database Layer]
        E --> G[LLM Layer - Groq]
        E --> H[Embedding Layer - MiniLM]
    end

    subgraph External
        F --> I[(Supabase PostgreSQL)]
        G --> J[Groq Cloud API]
        K[Redis] --> D
        L[LiveKit] --> D
    end
```

#### 

1. Flutter sends HTTP request with `Authorization: Bearer <supabase_jwt>`
2. `auth_guard.py` validates JWT via Supabase `auth.get_user(token)`
3. Route handler receives request + `VerifiedUser`
4. Route calls service methods (wrapped in `asyncio.to_thread()` for sync DB calls)
5. Services interact with Supabase (DB), Groq (LLM), and SentenceTransformer (embeddings)
6. Response returned to Flutter

---

### 

#### 

```mermaid
sequenceDiagram
    participant F as Flutter
    participant S as Server
    participant DB as Supabase
    participant LLM as Groq
    participant E as Embeddings

    F->>S: POST /v1/start_session
    S->>DB: INSERT sessions
    S->>S: Store in session_store
    S-->>F: {session_id}

    loop Every speech chunk
        F->>S: POST /v1/process_transcript_wingman
        S->>DB: INSERT session_logs (speaker turn)
        par Context loading
            S->>DB: RPC match_memory
            S->>DB: SELECT knowledge_graphs
            S->>DB: SELECT entities + attrs + rels
        end
        S->>LLM: Wingman advice (8B)
        S->>DB: INSERT session_logs (LLM turn)
        S->>LLM: Unified extraction (8B)
        par Persistence
            S->>DB: UPSERT entities, attrs, rels
            S->>DB: INSERT events, tasks, highlights
            S->>E: Encode + INSERT memory
            S->>DB: UPSERT knowledge_graphs
        end
        S-->>F: {advice}
    end

    F->>S: POST /v1/end_session
    S->>LLM: Generate summary
    S->>DB: UPDATE sessions (completed)
    S->>DB: UPSERT session_analytics
    S-->>F: {status: completed}
```

#### 

```mermaid
sequenceDiagram
    participant F as Flutter
    participant S as Server
    participant DB as Supabase
    participant LLM as Groq

    F->>S: POST /v1/ask_consultant
    S->>DB: INSERT sessions (if no session_id)
    par Context Assembly
        S->>DB: SELECT knowledge_graphs → graph context
        S->>DB: RPC match_memory → vector context
        S->>DB: SELECT consultant_logs → history
        S->>DB: SELECT sessions → summaries
        S->>DB: SELECT entities → entity context
    end
    S->>LLM: Consultant answer (70B)
    par Post-processing
        S->>DB: INSERT consultant_logs
        S->>DB: INSERT session_logs (Q + A)
        S->>DB: UPDATE sessions (tokens)
        S->>DB: INSERT memory (with embedding)
        S->>DB: UPSERT knowledge_graphs
    end
    S-->>F: {answer, session_id}
```

---

## 2. Technology Stack & Environment

### 

#### 

| Package | Purpose | Version |
|---------|---------|---------|
| `fastapi` | Web framework | Latest |
| `uvicorn` | ASGI server | Latest |
| `pydantic` | Request validation | v2 |

#### 

| Package | Purpose | Notes |
|---------|---------|-------|
| `groq` | LLM inference (Llama 3) | Async + Sync clients |
| `sentence-transformers` | Embedding model (`all-MiniLM-L6-v2`) | 384-dim vectors |
| `torch` | ML backend for sentence-transformers | CPU-only build |
| `networkx` | In-memory knowledge graphs | Per-user graphs |

#### 

| Package | Purpose |
|---------|---------|
| `supabase` | PostgreSQL via Supabase client (service-role key, RLS disabled) |
| `redis[asyncio]` | Optional session state store (multi-worker support) |

#### 

| Package | Purpose |
|---------|---------|
| `slowapi` | Rate limiting (IP-based) |
| `httpx` | HTTP client (available but not actively used) |
| `python-dotenv` | Environment variable loading |
| `python-multipart` | File upload parsing (voice enrollment) |

#### 

```env
# Supabase
SUPABASE_URL=            # Project URL
SUPABASE_ANON_KEY=       # Anon key (not used by server, kept for reference)
SUPABASE_SERVICE_KEY=    # Service-role key (bypasses RLS)
SUPABASE_DB_URL=         # Direct PostgreSQL connection string (for asyncpg)
                         # Format: postgresql://postgres:[password]@db.[project].supabase.co:6543/postgres
                         # NOTE: Use port 6543 (Supavisor pooler), NOT 5432 (direct)

# LLM — Primary Providers
GROQ_API_KEY=            # Groq inference API key
CEREBRAS_API_KEY=        # Cerebras inference API key (wingman primary)
GEMINI_API_KEY=          # Google AI Studio API key (consultant primary)

# Voice/Video
LIVEKIT_URL=             # LiveKit server URL
LIVEKIT_API_KEY=         # LiveKit API key
LIVEKIT_API_SECRET=      # LiveKit API secret

# Optional
DEEPGRAM_API_KEY=        # Speech-to-text (optional)
REDIS_URL=               # Native Redis URL: rediss://default:<password>@<host>:6379
                         # ⚠️ Must be the native Redis protocol URL, NOT the Upstash REST URL
ALLOWED_ORIGINS=*        # CORS origins
DEBUG_SKIP_AUTH=false    # NEVER true in production
APP_ENV=development      # development | staging | production
SELF_URL=                # Server's own URL (for anti-cold-start self-ping)
```

> [!WARNING]
> **Upstash provides TWO URLs**: a REST API URL (`https://...upstash.io`) and a native Redis URL (`rediss://...upstash.io:6379`). The `redis[asyncio]` library requires the **native** URL. Using the REST URL will fail silently.

#### 

| Constant | Value | Used For |
|----------|-------|----------|
| `EMBEDDING_MODEL` | `all-MiniLM-L6-v2` | Memory embeddings (384-dim) |
| `CONSULTANT_MODEL` | `llama-3.3-70b-versatile` | Deep Q&A, coaching reports |
| `WINGMAN_MODEL` | `llama-3.1-8b-instant` | Real-time advice, extraction |

---

### 

```
server/
├── .dockerignore
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
│
└── app/
    ├── __init__.py              # Package marker
    ├── main.py                  # FastAPI app entry point
    ├── config.py                # Centralized settings (env vars)
    ├── database.py              # Supabase client singleton
    │
    ├── models/
    │   ├── __init__.py
    │   └── requests.py          # Pydantic request schemas
    │
    ├── routes/
    │   ├── __init__.py
    │   ├── health.py            # GET /, GET /health
    │   ├── sessions.py          # Session lifecycle + wingman
    │   ├── consultant.py        # Consultant Q&A (blocking, streaming, batch)
    │   ├── voice.py             # Voice commands, LiveKit tokens, enrollment
    │   ├── analytics.py         # Feedback, session analytics, coaching reports
    │   ├── gamification.py      # Gamification profile, quests, XP
    │   └── entities.py          # Entity queries, graph export, deletions
    │
    ├── services/
    │   ├── __init__.py          # Service singleton initialization
    │   ├── brain_service.py     # LLM inference (Groq)
    │   ├── session_service.py   # Session CRUD, turn logging
    │   ├── entity_service.py    # Entity CRUD, events, tasks, highlights
    │   ├── graph_service.py     # NetworkX knowledge graphs
    │   ├── vector_service.py    # Embedding + pgvector memory
    │   ├── gamification_service.py # XP, streaks, quests, achievements
    │   └── audit_service.py     # Audit logging
    │
    └── utils/
        ├── __init__.py
        ├── auth_guard.py        # JWT verification dependency
        ├── session_store.py     # Redis/in-memory session state
        ├── rate_limit.py        # SlowAPI limiter
        └── text_sanitizer.py    # Prompt injection protection
```

> **Total: 22 Python files** (4 infrastructure + 7 services + 7 routes + 4 utilities)

#### Build Order (Dependency Graph)

Files must be created in this order to avoid circular imports and missing dependencies:

```
Phase 1 — Zero Dependencies:
  config.py, database.py

Phase 2 — Infrastructure:
  models/requests.py, utils/auth_guard.py, utils/rate_limit.py,
  utils/text_sanitizer.py, utils/session_store.py

Phase 3 — Services (depend on database.py + config.py):
  vector_service.py, brain_service.py, session_service.py,
  entity_service.py, graph_service.py, audit_service.py,
  gamification_service.py [NEW], services/__init__.py

Phase 4 — Routes (depend on services + utils):
  health.py, sessions.py, consultant.py, voice.py,
  analytics.py, entities.py, gamification.py [NEW]

Phase 5 — Assembly:
  main.py (mounts all routes, configures middleware)
```

---

### 

```
env/
├── .env.development     # Local: DEBUG_SKIP_AUTH=true, localhost Supabase
├── .env.staging         # Render/Railway: Real DB, test API keys, DEBUG_SKIP_AUTH=false
└── .env.production      # Production: Service-role key, all keys real, no debug
```

**`config.py` — Use `pydantic-settings` for type-safe configuration**:
```python
from pydantic_settings import BaseSettings
from pydantic import Field
import os

class Settings(BaseSettings):
    """Type-validated, fail-fast configuration.
    Missing required fields raise clear errors at startup, not at request time."""
    
    # Required — server will NOT start without these
    SUPABASE_URL: str
    SUPABASE_SERVICE_KEY: str
    GROQ_API_KEY: str
    
    # LLM providers (for LiteLLM multi-provider gateway)
    CEREBRAS_API_KEY: str = ""
    GEMINI_API_KEY: str = ""
    
    # Optional with defaults
    SUPABASE_ANON_KEY: str = ""         # Not used by server, kept for reference
    SUPABASE_DB_URL: str = ""           # Direct PostgreSQL URL for asyncpg
    DEEPGRAM_API_KEY: str = ""
    LIVEKIT_URL: str = ""
    LIVEKIT_API_KEY: str = ""
    LIVEKIT_API_SECRET: str = ""
    REDIS_URL: str = ""                 # Native Redis URL (not REST)
    DEBUG_SKIP_AUTH: bool = False
    ALLOWED_ORIGINS: str = "*"
    APP_ENV: str = "development"        # development | staging | production
    SELF_URL: str = ""                  # For anti-cold-start self-ping
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    
    # AI Model Names (constants)
    EMBEDDING_MODEL: str = "all-MiniLM-L6-v2"
    CONSULTANT_MODEL: str = "llama-3.3-70b-versatile"
    WINGMAN_MODEL: str = "llama-3.1-8b-instant"

    class Config:
        env_file = "../../env/.env"
        env_file_encoding = "utf-8"
        extra = "ignore"  # Don't crash on unknown env vars

settings = Settings()
```

> [!TIP]
> `pydantic-settings` replaces both `python-dotenv` and manual `os.getenv()` calls. If `SUPABASE_URL` or `GROQ_API_KEY` are missing, the server crashes at startup with a clear error like `"SUPABASE_URL field required"` instead of failing silently at the first request.

## 3. API Contracts & Routing

### 

> [!NOTE]
> These are the exact calls the Flutter `ApiService` makes. Your new server must support all of them.

| Flutter Method | HTTP | Server Endpoint | Body Fields |
|---|---|---|---|
| `createLiveSession()` | POST | `/v1/start_session` | `user_id, mode, target_entity_id, is_ephemeral, is_multiplayer, persona` |
| `sendTranscriptToWingman()` | POST | `/v1/process_transcript_wingman` | `user_id, transcript, speaker_role, mode, session_id` |
| `saveSession()` | POST | `/v1/save_session` | `user_id, transcript, logs` |
| `endLiveSession()` | POST | `/v1/end_session` | `session_id, user_id` |
| `askConsultant()` | POST | `/v1/ask_consultant` | `user_id, question` |
| `askConsultantStream()` | POST | `/v1/ask_consultant_stream` | `user_id, question, mode, session_id` |
| `getToken()` | POST | `/v1/getToken` | `userId, roomName` |
| `enrollVoice()` | POST | `/v1/enroll` | `user_id, user_name, file` (multipart) |
| `parseVoiceCommand()` | POST | `/v1/voice_command` | `user_id, command` |
| `saveFeedback()` | POST | `/v1/save_feedback` | `user_id, feedback_type, session_id, session_log_id, consultant_log_id, value, comment` |
| `getSessionAnalytics()` | GET | `/v1/session_analytics/{session_id}` | — |
| `getCoachingReport()` | GET | `/v1/coaching_report/{session_id}` | — |
| `askAboutEntity()` | POST | `/v1/ask_entity` | `user_id, entity_name` |
| `getGraphExport()` | GET | `/v1/graph_export/{user_id}` | — |
| `getGamification()` | GET | `/v1/gamification/{user_id}` | — |
| `getQuests()` | GET | `/v1/quests/{user_id}` | — |
| `getDigest()` | GET | `/v1/digest/{user_id}` | `?period=week` (query param) | **[NEW]**
| `getCommunicationTrends()` | GET | `/v1/communication_trends/{user_id}` | `?weeks=8` (query param) | **[NEW]**
| `getEntityTimeline()` | GET | `/v1/entity_timeline/{entity_id}` | `?user_id=` (query param) | **[NEW]**
| `getSessionReplay()` | GET | `/v1/session_replay/{session_id}` | — | **[NEW]**

> [!WARNING]
> **Dead code identified**: `ApiService.processAudioChunk()` calls `POST /v1/process_audio` but this endpoint does not exist on the server and has zero callers in the Flutter app. This method should be removed from `api_service.dart` during the client cleanup phase.

> [!NOTE]
> The `/v1/gamification/{user_id}` and `/v1/quests/{user_id}` endpoints are fully documented in [Section 14 — Gamification & Quests System](#14-gamification--quests-system). The new endpoints (`digest`, `communication_trends`, `entity_timeline`, `session_replay`) are documented in [Section 6.1.7 — Intelligent Features](#).

---

### 

#### 

| Endpoint | Method | Auth | Rate Limit | Purpose |
|----------|--------|------|------------|---------|
| `/` | GET | ❌ | ❌ | Returns server status + model names |
| `/health` | GET | ❌ | ❌ | Validates DB, LLM key, embeddings model |

**Health check verifies**:
1. DB connectivity (queries `profiles` table)
2. Embedding model loaded (`vector_svc.model is not None`)
3. Groq API key present and >10 chars

**Returns HTTP 503** with `"status": "degraded"` if any check fails.

---

#### 

| Endpoint | Method | Auth | Rate Limit | Purpose |
|----------|--------|------|------------|---------|
| `/v1/start_session` | POST | ✅ | 10/min | Create new session |
| `/v1/process_transcript_wingman` | POST | ✅ | 30/min | Real-time wingman processing |
| `/v1/save_session` | POST | ✅ | 10/min | Save completed session |
| `/v1/end_session` | POST | ✅ | 10/min | End active session |

##### 

**Request**: `StartSessionRequest`
**Flow**:
1. `session_svc.start_session()` → DB INSERT into `sessions`
2. `session_store.set_live_session()` → Redis/memory mapping
3. `session_store.set_metadata()` → Store ephemeral/multiplayer/persona flags
4. Cap global sessions at 500 (evict oldest)
5. **If `target_entity_id` is provided** → assemble pre-session briefing (see below)
6. `audit_svc.log()` → DB INSERT into `audit_log`

**Response**:
```json
{
  "session_id": "<uuid>",
  "briefing": {
    "entity_name": "Sarah",
    "entity_type": "person",
    "relationship": "colleague — works in marketing",
    "key_facts": [
      "Prefers async communication",
      "Recently promoted to team lead"
    ],
    "unresolved_items": [
      {"type": "task", "title": "Send Q3 report draft", "status": "pending"},
      {"type": "event", "title": "Team offsite next Thursday"}
    ],
    "last_interaction": "3 days ago — discussed project timeline",
    "conversation_tips": "Tends to appreciate directness. Last session sentiment was positive."
  }
}
```

> [!NOTE]
> The `briefing` field is `null` when no `target_entity_id` is provided or when the entity has no data. The Flutter client already passes `targetEntityId` when launching a roleplay session (`new_session_screen.dart:L89`).

**Pre-Session Briefing Assembly** (inside `start_session` route or a dedicated `briefing_service.py`):
```python
async def assemble_briefing(user_id: str, entity_id: str) -> dict | None:
    """Assemble context briefing for a target entity. Returns None if no data."""
    try:
        # 1. Fetch entity + attributes + relations
        entity_ctx = await entity_svc.get_entity_context(user_id, entity_id)
        if not entity_ctx:
            return None
        
        # 2. Fetch unresolved tasks (keyword search for entity name in title/description)
        tasks = await asyncio.to_thread(
            lambda: db.table("tasks").select("title, status, priority")
                .eq("user_id", user_id).eq("status", "pending")
                .limit(5).execute()
        )
        
        # 3. Fetch upcoming events
        events = await asyncio.to_thread(
            lambda: db.table("events").select("title, due_text")
                .eq("user_id", user_id).limit(5).execute()
        )
        
        # 4. Find last session with this entity
        last_session = await asyncio.to_thread(
            lambda: db.table("sessions").select("summary, created_at, sentiment_score")
                .eq("user_id", user_id).eq("target_entity_id", entity_id)
                .order("created_at", desc=True).limit(1).maybe_single().execute()
        )
        
        # 5. Vector search for recent memories about this entity
        entity_name = ...  # from entity_ctx
        memories = await vector_svc.search_memory(user_id, entity_name, match_count=3)
        
        return {
            "entity_name": entity_name,
            "entity_type": ...,
            "relationship": ...,  # from entity_relations
            "key_facts": [...],   # from entity_attributes + memories
            "unresolved_items": [...],  # from tasks + events
            "last_interaction": ...,    # from last_session
            "conversation_tips": ...    # from sentiment + LLM summary (optional)
        }
    except Exception as e:
        print(f"Briefing assembly failed: {e}")
        return None
```

**DB Tables Read**: `entities`, `entity_attributes`, `entity_relations`, `tasks`, `events`, `sessions`, `memory`
**DB Tables Written**: `sessions`, `audit_log`

---

##### 

**Request**: `WingmanRequest`
**This is the most complex endpoint. Full pipeline:**

1. **Log incoming transcript** → `session_logs` (with inline sentiment)
2. **Load contexts in parallel** (4 concurrent calls):
   - `graph_svc.find_context()` → reads `knowledge_graphs`
   - `vector_svc.search_memory()` → RPC `match_memory` on `memory`
   - `entity_svc.get_entity_context()` → reads `entities`, `entity_attributes`, `entity_relations`
   - **[NEW]** `vector_svc.search_memory(threshold=0.8)` → high-similarity check for "you've discussed this before" detection (see §6.1.7)
3. **[NEW] Inject user preference hints** → `brain_svc._get_user_feedback_hints(user_id)` reads recent `feedback` ratings to adapt wingman tone (see §6.1.7)
4. **Generate wingman advice** → Groq LLM call (async) — now includes similarity context + feedback hints in system prompt
4. **Log LLM advice** → `session_logs` (with model metadata)
5. **Update token usage** → `sessions` table
6. **Unified extraction** (ONE LLM call) → entities, relations, events, tasks, conflicts
7. **Persist entities** → `entities`, `entity_attributes`, `entity_relations`
8. **Update knowledge graph** → `knowledge_graphs`
9. **Save conflicts as highlights** → `highlights`
10. **Save events** → `events`
11. **Save tasks** → `tasks`
12. **Save to memory** → `memory` (with embedding)
13. **Rolling summarization** (every 20 turns) → updates `sessions.summary`
14. **Sentiment logging** → `sentiment_logs` (via log_message)

**Response**: `{"advice": "<string>"}`

**DB Tables Written**: `session_logs`, `sentiment_logs`, `sessions`, `entities`, `entity_attributes`, `entity_relations`, `knowledge_graphs`, `highlights`, `events`, `tasks`, `memory`

---

##### 

**Request**: `SaveSessionRequest`
**Flow**:
1. Skip if ephemeral → `{"session_id": "ephemeral-skipped"}`
2. Create session record → `sessions`
3. Bulk-log turns → `session_logs`
4. Unified extraction (LLM) → entities, events, tasks
5. Extract highlights (separate LLM call)
6. Persist all: `entities`, `entity_attributes`, `entity_relations`, `events`, `tasks`, `highlights`
7. Update knowledge graph → `knowledge_graphs`
8. Generate summary → update `sessions`
9. Save to memory → `memory`
10. Audit log → `audit_log`

**DB Tables Written**: `sessions`, `session_logs`, `entities`, `entity_attributes`, `entity_relations`, `highlights`, `events`, `tasks`, `knowledge_graphs`, `memory`, `audit_log`

---

##### 

**Request**: `EndSessionRequest`
**Flow**:
1. Check ephemeral flag from session store
2. If not ephemeral: read full transcript from `session_logs`, generate summary, extract highlights + tasks
3. Mark session completed → `sessions`
4. Save summary to memory → `memory`
5. Clean up session store (Redis/memory)
6. Fire background analytics computation → `session_analytics`
7. Audit log → `audit_log`

**DB Tables Written**: `sessions`, `memory`, `highlights`, `tasks`, `session_analytics`, `audit_log`

---

#### 

| Endpoint | Method | Auth | Rate Limit | Purpose |
|----------|--------|------|------------|---------|
| `/v1/ask_consultant` | POST | ✅ | 10/min | Blocking Q&A |
| `/v1/ask_consultant_stream` | POST | ✅ | 10/min | SSE streaming Q&A |
| `/v1/ask_consultant/batch` | POST | ✅ | ❌ | Concurrent multi-question |

##### 

**Request**: `ConsultantRequest`
**Context Assembly** (5 parallel fetches):
1. Graph context → `knowledge_graphs`
2. Vector memory → `memory` (RPC)
3. Consultant history → `consultant_logs`
4. Session summaries → `sessions`
5. Entity context (if target) → `entities`, `entity_attributes`, `entity_relations`

**Then**:
- LLM call (70B, async)
- Log Q&A → `consultant_logs` + `session_logs`
- Track tokens → `sessions`
- Save to memory → `memory`
- Save graph → `knowledge_graphs`
- Audit → `audit_log`

**Response**: `{"answer": "<string>", "session_id": "<uuid>"}`

---

##### 

Same context assembly, but uses Groq streaming API. Yields `data: {"token": "..."}` events via SSE. Post-stream: logs same data as blocking endpoint.

**Response**: `text/event-stream` with events:
- `{"token": "<chunk>"}` — streamed tokens
- `{"done": true, "session_id": "<uuid>"}` — completion signal
- `{"error": "<message>"}` — error

---

#### 

| Endpoint | Method | Auth | Rate Limit | Purpose |
|----------|--------|------|------------|---------|
| `/v1/getToken` | POST | ❌ | 15/min | LiveKit JWT token generation |
| `/v1/voice_command` | POST | ❌ | 15/min | Voice command intent routing |
| `/v1/enroll` | POST | ❌ | 5/min | Voice enrollment (multipart) |

##### 

- Generates LiveKit JWT with room join, publish, subscribe grants
- **No DB interaction**

##### 

- **Step 1**: LLM classifies intent → `start_session`, `ask_consultant`, `view_sessions`, `go_home`, `general_chat`
- **Step 2**: Routes based on intent:
  - `start_session` → returns `{"action": "navigate", "target": "/new-session"}`
  - `ask_consultant` → full consultant pipeline (creates session, fetches context, generates answer)
  - `go_home`/`view_sessions` → navigation responses
  - `general_chat` → casual LLM response

**DB Tables**: `sessions`, `consultant_logs`, `knowledge_graphs`, `memory`, `audit_log`

##### 

- Receives audio file upload
- Loads ECAPA-TDNN speaker model (lazy, first call only)
- Extracts 192-dim speaker embedding
- **DB WRITE**: `voice_enrollments` — upserts embedding + increments `samples_count`
- **DB READ**: `voice_enrollments` — checks existing count
- Audit log → `audit_log`

---

#### 

| Endpoint | Method | Auth | Rate Limit | Purpose |
|----------|--------|------|------------|---------|
| `/v1/save_feedback` | POST | ❌ | 30/min | Save user feedback |
| `/v1/session_analytics/{session_id}` | GET | ❌ | 20/min | Get session metrics |
| `/v1/coaching_report/{session_id}` | GET | ❌ | 10/min | Get/generate coaching report |

##### 

- **DB WRITE**: `feedback` — inserts rating/comment
- **Columns**: `user_id, feedback_type, session_id, log_id, consultant_log_id, value, rating, comment`

##### 

- **DB READ**: `session_analytics` — pre-computed metrics
- **DB READ**: `session_logs` — on-the-fly talk-time calculation
- **DB READ**: `sentiment_logs` — sentiment trend data
- **Computed fields**: `talk_time_user_seconds`, `talk_time_others_seconds`, `longest_monologue_seconds`, `user_filler_count`, `mutual_engagement_score`
- **Filler words tracked**: um, uh, like, literally, basically, actually

##### 

- **DB READ**: `coaching_reports` — returns cached report if exists
- **If not cached**: reads transcript from `session_logs`, generates via 70B LLM
- **DB WRITE**: `coaching_reports` — caches generated report
- **Report fields**: `user_talk_pct`, `others_talk_pct`, `key_topics`, `key_decisions`, `action_items`, `follow_up_people`, `filler_words`, `filler_word_count`, `tone_summary`, `engagement_trend`, `suggestions`, `strengths`, `report_text`

##### 

- Fired as background task when session ends
- **DB READ**: `session_logs` (all), `sessions` (timestamps), `memory` (count), `events` (count), `highlights` (count)
- **DB WRITE**: `session_analytics` — upserts full metrics row

---

#### 

| Endpoint | Method | Auth | Rate Limit | Purpose |
|----------|--------|------|------------|---------|
| `/v1/ask_entity` | POST | ❌ | 15/min | AI summary of an entity |
| `/v1/graph_export/{user_id}` | GET | ❌ | ❌ | Export knowledge graph as JSON |
| `/v1/entities/{entity_id}` | DELETE | ✅ | 10/min | Delete entity + cascade |
| `/v1/sessions/{session_id}` | DELETE | ✅ | 10/min | Delete session |
| `/v1/memories/{memory_id}` | DELETE | ✅ | 10/min | Delete memory |

> [!WARNING]
> **Security Fix**: All DELETE endpoints MUST require JWT authentication and verify ownership (`WHERE user_id = verified_user.user_id`) before performing the deletion. Without this, anyone with a valid UUID can delete any user's data. The rate limit of 10/min prevents bulk deletion abuse.

##### 

- **DB READ**: `entities` (fuzzy ilike search), `entity_attributes`, `entity_relations`, `entities` (target names)
- **DB RPC**: `match_memory` — vector search for entity mentions
- **LLM**: Generates 2-4 sentence summary using all context
- Audit → `audit_log`

##### 

- **DB DELETE**: `entity_attributes`, `entity_relations` (both source and target), `entities`
- Audit → `audit_log`

---

### 

All endpoints are prefixed with `/v1`. This section defines the versioning policy:

- **Breaking changes** (renamed fields, removed endpoints, changed response structure) → bump to `/v2`
- **Non-breaking additions** (new optional fields, new endpoints) → stay in `/v1`
- **Both versions run simultaneously** during transition periods (minimum 30 days)
- Flutter client sends `X-API-Version: 1` header for server-side compatibility detection
- Server responds with `X-API-Version: 1` header to confirm which version handled the request

**When to bump**:
| Change Type | Version Bump? |
|---|---|
| Add new endpoint | ❌ No |
| Add optional field to response | ❌ No |
| Add optional field to request | ❌ No |
| Rename response field | ✅ Yes |
| Remove endpoint | ✅ Yes |
| Change field type (string → int) | ✅ Yes |
| Change error response format | ✅ Yes |

---

### 

The Flutter client retries requests with exponential backoff (§12, `_withRetry`). Without idempotency, retried writes can:
- End the same session twice
- Insert duplicate turns into `session_logs`
- Award duplicate XP (mitigated by §14.3 anti-abuse, but belt + suspenders)

**Implementation**: Accept an `Idempotency-Key` header on mutating endpoints.

```python
from typing import Optional
from fastapi import Header

async def check_idempotency(key: Optional[str], session_store) -> Optional[dict]:
    """Returns cached response if this key was already processed."""
    if not key:
        return None
    cached = await session_store.get(f"idempotent:{key}")
    if cached:
        return json.loads(cached)
    return None

async def save_idempotency(key: Optional[str], response: dict, session_store, ttl: int = 3600):
    """Cache the response for this idempotency key."""
    if key:
        await session_store.set(f"idempotent:{key}", json.dumps(response), ex=ttl)
```

**Apply to these endpoints**:

| Endpoint | Risk Without Idempotency |
|---|---|
| `POST /v1/end_session` | Session ended twice, duplicate analytics, double XP |
| `POST /v1/save_session` | Duplicate session_logs, duplicate entities |
| `POST /v1/save_feedback` | Duplicate feedback rows |
| `POST /v1/start_session` | Multiple sessions created for same intent |

**Flutter client sends**:
```dart
final idempotencyKey = '${userId}_${sessionId}_${DateTime.now().millisecondsSinceEpoch ~/ 10000}';
request.headers['Idempotency-Key'] = idempotencyKey;
```

## 4. Models & Input Validation

### 

All defined in `app/models/requests.py`:

| Model | Fields | Used By |
|-------|--------|---------|
| `StartSessionRequest` | `user_id*, mode, target_entity_id, is_ephemeral, is_multiplayer, persona, device_id, session_type` | `/start_session` |
| `SaveSessionRequest` | `user_id*, transcript*, logs*, is_ephemeral` | `/save_session` |
| `EndSessionRequest` | `session_id*, user_id*` | `/end_session` |
| `WingmanRequest` | `user_id*, transcript*, session_id, speaker_role, speaker_label, confidence, mode, persona` | `/process_transcript_wingman` |
| `ConsultantRequest` | `user_id*, question*(max 5000), session_id, mode, persona` | `/ask_consultant`, `/ask_consultant_stream` |
| `BatchConsultantRequest` | `user_id*, questions*, mode` | `/ask_consultant/batch` |
| `EntityQueryRequest` | `user_id*, entity_name*(max 200)` | `/ask_entity` |
| `VoiceCommandRequest` | `user_id*, command*(max 2000)` | `/voice_command` |
| `TokenRequest` | `userId*, roomName` | `/getToken` |
| `FeedbackRequest` | `user_id*, session_id, session_log_id, consultant_log_id, feedback_type*, value(-1 to 5), comment(max 1000)` | `/save_feedback` |

#### 

All endpoints MUST return errors in this format. This ensures the Flutter client has a **single, consistent error-parsing contract** across all 15+ endpoints.

```python
class ErrorResponse(BaseModel):
    error: str                      # Machine-readable code: "rate_limited", "auth_failed", "llm_timeout", "validation_error"
    message: str                    # Human-readable: "Too many requests, please try again in 30s"
    details: dict | None = None     # Optional context: {"retry_after": 30, "field": "transcript"}
    request_id: str | None = None   # Correlation ID for debugging (from X-Request-ID header)
```

**Standard error codes**:

| HTTP Status | `error` Code | When |
|-------------|-------------|------|
| 400 | `validation_error` | Pydantic validation failure, missing required fields |
| 401 | `auth_failed` | Missing/invalid/expired JWT token |
| 403 | `forbidden` | User doesn't own the requested resource |
| 404 | `not_found` | Session/entity/memory doesn't exist |
| 429 | `rate_limited` | SlowAPI rate limit exceeded |
| 500 | `internal_error` | Unhandled server exception |
| 502 | `llm_error` | Groq/LiteLLM API failure after all retries |
| 503 | `service_unavailable` | DB unreachable, embedding model not loaded |

**Global exception handler** (add to `main.py`):
```python
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError

@app.exception_handler(HTTPException)
async def http_error_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": exc.detail if isinstance(exc.detail, str) else exc.detail.get("code", "unknown"),
            "message": str(exc.detail),
            "request_id": getattr(request.state, "request_id", None),
        }
    )

@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=400,
        content={
            "error": "validation_error",
            "message": "Invalid request parameters",
            "details": {"errors": exc.errors()},
            "request_id": getattr(request.state, "request_id", None),
        }
    )
```

**Flutter client matching handler**:
```dart
class ApiError {
  final String error;
  final String message;
  final Map<String, dynamic>? details;
  final String? requestId;

  bool get isRateLimited => error == 'rate_limited';
  bool get isAuthFailed => error == 'auth_failed';
  bool get isLlmError => error == 'llm_error';

  factory ApiError.fromResponse(http.Response response) {
    final body = jsonDecode(response.body);
    return ApiError(
      error: body['error'] ?? 'unknown',
      message: body['message'] ?? 'An error occurred',
      details: body['details'],
      requestId: body['request_id'],
    );
  }
}
```

---

### 

**Purpose**: Defense-in-depth validation beyond Pydantic field constraints.

```python
# utils/validation.py

# Maximum sizes (characters)
MAX_TRANSCRIPT_LENGTH = 50_000       # ~12,500 words — longer transcripts are truncated
MAX_BATCH_LOGS = 500                 # Max turns in save_session.logs[]
MAX_ENTITY_NAME_LENGTH = 200         # Already in Pydantic, enforced here too
MAX_QUESTION_LENGTH = 5_000          # Already in Pydantic ✅
MAX_COMMAND_LENGTH = 2_000           # Already in Pydantic ✅
MAX_COMMENT_LENGTH = 1_000           # Already in Pydantic ✅

# Unicode normalization
import unicodedata
def normalize_text(text: str) -> str:
    """NFC-normalize unicode input for consistent entity matching."""
    return unicodedata.normalize("NFC", text.strip())

# Validation helper
def validate_transcript(transcript: str) -> str:
    """Truncate + normalize transcript input."""
    normalized = normalize_text(transcript)
    if len(normalized) > MAX_TRANSCRIPT_LENGTH:
        normalized = normalized[:MAX_TRANSCRIPT_LENGTH]
    return normalized

def validate_batch_logs(logs: list) -> list:
    """Cap batch log size to prevent abuse."""
    return logs[:MAX_BATCH_LOGS]
```

**Apply in route handlers**:
```python
# In sessions.py
@router.post("/v1/process_transcript_wingman")
async def process_wingman(req: WingmanRequest, ...):
    req.transcript = validate_transcript(req.transcript)
    ...

@router.post("/v1/save_session")
async def save_session(req: SaveSessionRequest, ...):
    req.logs = validate_batch_logs(req.logs)
    ...
```

> [!IMPORTANT]
> Rate limiting by IP alone is insufficient — one user with multiple IPs (VPN, mobile data) can bypass limits. For business-critical endpoints (wingman, consultant), also rate-limit by `user_id` extracted from the JWT. Use a compound key: `f"{user_id}:{endpoint}"`.

---

### 

Strips known injection patterns:
- `ignore all previous instructions`
- `you are now a/an/the`
- `system:`, `assistant:`, `[INST]`, `<|im_start|>`, `### System/Human/Assistant`

Caps input at 5000 characters.

## 5. Security & Auth Flow

### 

**FastAPI Dependency**: `get_verified_user` → returns `VerifiedUser(user_id, email)`

**Two modes**:
1. **Production**: Extracts `Bearer <token>` from `Authorization` header → calls `supabase.auth.get_user(token)` → returns verified user_id
2. **Debug** (`DEBUG_SKIP_AUTH=true`): Reads `user_id` from request body JSON directly

**HTTP Errors**: 401 (missing/invalid token), 400 (debug mode parse failure)

### 

Every endpoint that accesses user-specific resources must verify ownership. This is especially critical for endpoints that were previously unauthenticated (see §6.6 fix).

```python
# Standard ownership check — use in all data-access endpoints
async def verify_ownership(resource_table: str, resource_id: str, user_id: str) -> bool:
    """Verify that the resource belongs to the requesting user."""
    result = await asyncio.to_thread(
        lambda: db.table(resource_table)
            .select("user_id")
            .eq("id", resource_id)
            .maybe_single()
            .execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail={"code": "not_found", "message": f"{resource_table} not found"})
    if result.data["user_id"] != user_id:
        raise HTTPException(status_code=403, detail={"code": "forbidden", "message": "You don't own this resource"})
    return True
```

### 

SlowAPI's default `get_remote_address` only rate-limits by IP. For authenticated endpoints, also rate-limit by `user_id`:

```python
def get_rate_limit_key(request: Request) -> str:
    """Compound rate limit key: user_id if authenticated, else IP."""
    user = getattr(request.state, "verified_user", None)
    if user:
        return f"user:{user.user_id}"
    return get_remote_address(request)
```

### 

Simple `Limiter(key_func=get_remote_address)` — keyed by client IP.

## 6. Service Specifications & Business Logic

### 

#### 

**File**: `app/services/brain_service.py`

**Purpose**: All LLM inference calls (Groq/Llama 3). Handles prompt building, retries, token tracking.

**Initialization**:
- `self.aclient = AsyncGroq(api_key=...)` — Primary async client for all route handlers
- `self.client = Groq(api_key=...)` — Sync fallback (startup checks only)

**Methods**:

##### 

- **Model**: `WINGMAN_MODEL` (8B, fast)
- **Max tokens**: 60
- **Temperature**: 0.6
- **Retries**: 2 attempts with 500ms delay
- **Returns**: `{"answer": str, "model_used": str, "latency_ms": int, "tokens_prompt": int, "tokens_completion": int, "tokens_used": int, "finish_reason": str}`
- **Special**: Returns `"WAITING"` if user is doing fine (no advice needed)
- **Persona handling**: Builds different system prompts based on mode (roleplay, casual, formal, stoic, aggressive_coach, empathetic_friend, serious)

##### 

- **Model**: `CONSULTANT_MODEL` (70B, accurate)
- **Max tokens**: 800
- **Temperature**: 0.7
- **Retries**: 3 attempts with progressive delay (1s, 2s, 3s)
- **Context truncation**: Each context source capped at ~1000 tokens
- **Returns**: Same metadata dict structure as wingman

##### 

- **CRITICAL**: Consolidated extraction — replaces 4 separate LLM calls
- **Model**: `WINGMAN_MODEL`
- **Max tokens**: 1200
- **Temperature**: 0.1
- **Response format**: `json_object` (forced JSON)
- **Extracts in ONE call**: entities, relations, events, tasks, conflicts
- **[NEW] Smart due date extraction**: When tasks mention temporal references ("by Friday", "next week", "tomorrow"), the extraction prompt resolves them to ISO dates relative to the current date. The `tasks` table has a `due_date` column that is currently never populated — this fixes that.
- **Conflict detection**: Compares new relations against existing graph context
- **Returns**: `{"entities": [...], "relations": [...], "events": [...], "tasks": [{..., "due_date": "2026-04-11"}], "conflicts": [...], ...metadata}`

##### 

- **Model**: `WINGMAN_MODEL`
- **Max tokens**: 600
- **Temperature**: 0.2
- **Extracts**: insights, action_items, key_facts (max 5)
- **Returns**: `[{"type": str, "title": str, "body": str}]`

##### 

- **Model**: `WINGMAN_MODEL`
- **Max tokens**: 150
- **Temperature**: 0.4
- **Returns**: 2-3 sentence summary

##### 

- `_estimate_tokens(text)`: `len(words) * 1.3`
- `_truncate_to_token_limit(text, limit)`: Word-based truncation
- `_persona_instruction(mode, persona)`: Returns persona-specific prompt suffix
- `_build_consultant_system_prompt(...)`: Full system prompt builder for consultant
- `_extract_metadata(completion, model, latency_ms)`: Extracts Groq usage stats

**DB Tables**: None directly (pure LLM layer)

---

#### 

**File**: `app/services/session_service.py`

**Purpose**: Session CRUD, turn logging with inline sentiment, consultant history, token usage tracking.

**Methods**:

##### 

- **DB WRITE**: `sessions` table — inserts new row
- **Ephemeral sessions**: Generates UUID locally, skips DB entirely
- **Columns written**: `user_id, title, session_type, mode, status("active"), is_ephemeral, is_multiplayer, persona, device_id`

##### 

- **DB WRITE**: `sessions` table — simpler insert (used by save_session and consultant)
- **Columns written**: `user_id, title, session_type, mode, status("active"), summary(optional)`

##### 

- **DB WRITE**: `session_logs` table — inserts turn
- **DB WRITE**: `sentiment_logs` table — inserts sentiment entry
- **DB READ**: `session_logs` (count for auto turn_index)
- **DB READ**: `sessions` (to get user_id for sentiment_logs)
- **Inline Sentiment Analysis**: Keyword-based scoring (positive/negative word lists), stress detection (filler words, punctuation arousal, hesitation markers)
- **Skips DB entirely if `is_ephemeral=True`**
- **Columns written to `session_logs`**: `session_id, role, content, turn_index, sentiment_score, sentiment_label, speaker_label, confidence, model_used, latency_ms, tokens_used, finish_reason`
- **Columns written to `sentiment_logs`**: `session_id, user_id, turn_index, speaker_role, sentiment_score, score, label`

##### 

- **DB WRITE**: `session_logs` — bulk insert with sequential turn indices
- **Input format**: `[{"speaker": "user", "text": "..."}]`

##### 

- **DB READ**: `session_logs` — reads all sentiment_scores for aggregation
- **DB WRITE**: `sessions` — updates `status="completed"`, `ended_at`, `end_time`, `summary`, `sentiment_score` (aggregate)

##### 

- **DB READ**: `sessions` — current token counts
- **DB WRITE**: `sessions` — increments `token_usage_prompt`, `token_usage_completion`, `total_cost_usd`
- **Cost formula**: `(total_tokens / 1,000,000) × $0.05`

##### 

- **DB WRITE**: `consultant_logs` — inserts Q&A (writes both `question/answer` AND `query/response` columns for compatibility)
- **DB WRITE**: `session_logs` — logs user message + LLM response as turns

##### 

- **DB READ**: `consultant_logs` — last N Q&A pairs, ordered by `created_at DESC`

##### 

- **DB READ**: `sessions` — completed sessions with non-null summaries

##### 

- **DB READ**: `session_logs` — exact count

---

#### 

**File**: `app/services/entity_service.py`

**Purpose**: Entity CRUD with fuzzy deduplication, relation management, event/task/highlight/conflict persistence.

**Methods**:

##### 

- **DB READ**: `entities` — fetches ALL user entities for fuzzy comparison
- **Algorithm**: `SequenceMatcher` with 0.85 threshold
- **Returns**: entity_id if near-duplicate found

##### 

- **DB READ**: `entities` — exact match on `canonical_name`
- **DB WRITE**: `entities` — insert new OR update `last_seen_at` + increment `mention_count`
- **Deduplication**: Checks fuzzy match before creating new entity
- **Valid types**: person, place, organization, event, object, concept

##### 

- **DB WRITE**: `entity_attributes` — upsert on `(entity_id, attribute_key)` conflict
- **Columns**: `entity_id, attribute_key, attribute_value, updated_at, source_session, source_session_id`

##### 

- **DB WRITE**: `entity_relations` — upsert on `(source_id, target_id, relation)` conflict

##### 

- **DB READ**: `entities`, `entity_attributes`, `entity_relations`, `entities` (for target display names)
- **Returns**: Formatted text block with entity details, attributes, and relations

##### 

- **Orchestrator**: Calls `_upsert_entity`, `_upsert_attributes`, `_upsert_relation` for each extracted item
- **Rollback**: On failure, deletes all created entities + their attributes and relations
- **Input**: `{"entities": [...], "relations": [...]}`

##### 

- **DB WRITE**: `highlights` — type `"conflict"`
- **Columns**: `user_id, highlight_type, title, body, content, session_id`

##### 

- **DB WRITE**: `events`
- **Columns**: `user_id, title, due_text, description, session_id`

##### 

- **DB WRITE**: `tasks`
- **Columns**: `user_id, title, status("pending"), description, priority, source_session_id`
- **Priority validation**: low, medium, high, urgent (defaults to medium)

##### 

- **DB WRITE**: `highlights`
- **Valid types**: conflict, action_item, insight, key_fact
- **Columns**: `user_id, highlight_type, title, body, content, session_id`

---

#### 

**File**: `app/services/graph_service.py`

**Purpose**: Per-user NetworkX graphs for relationship-based context retrieval.

**State**: `self.active_graphs: Dict[str, nx.Graph]` — in-memory cache

**Methods**:

##### 

- **DB READ**: `knowledge_graphs` — loads `graph_data` (JSON)
- Deserializes via `nx.node_link_graph()`
- Creates empty graph if no data exists

##### 

- **DB WRITE**: `knowledge_graphs` — upserts `graph_data` + `updated_at`
- Serializes via `nx.node_link_data()`
- **Frees memory**: Deletes graph from `active_graphs` after save

##### 

- **Semantic search**: Encodes all node names + query via SentenceTransformer
- **Fallback**: Keyword substring matching if model unavailable
- **Cosine similarity threshold**: 0.3
- **Returns**: `"Fact: A relation B\nFact: C relation D"` (max `top_k` facts)

##### 

- Adds edges to in-memory graph: `G.add_edge(source, target, relation=relation)`

**Shared model**: `graph_svc.model = vector_svc.model` (set in `services/__init__.py`)

---

#### 

**File**: `app/services/vector_service.py`

**Purpose**: SentenceTransformer embeddings + pgvector-backed memory search/save.

**Initialization**: Loads `all-MiniLM-L6-v2` model on startup (slow first load)

**Methods**:

##### 

- **DB RPC**: `match_memory` — pgvector cosine similarity search
- **Parameters**: `query_embedding` (384-dim), `match_threshold=0.5`, `match_count=3`, `p_user_id`
- **Returns**: Formatted memory strings or "No relevant past memories."

##### 

- **DB WRITE**: `memory` — inserts content + 384-dim embedding vector
- **Encoding**: Runs in `asyncio.to_thread()` to avoid blocking event loop
- **Columns**: `user_id, content, memory_type, embedding, session_id`

##### 

- **DB WRITE**: `memory` — sets `is_archived = true` for entries older than cutoff
- **Deduplication**: Skips memories with identical `content` hash within the same session
- **Schedule**: Should be called as a background task during `end_session` or via periodic cleanup
- **Reasoning**: The `memory` table grows indefinitely. The `expires_at` and `is_archived` columns exist in the schema but are never written to. Without cleanup, vector search degrades as the collection grows past ~50K rows.

```python
from datetime import datetime, timedelta, timezone

async def cleanup_old_memories(self, user_id: str, max_age_days: int = 90):
    """Archive memories older than max_age_days to keep vector search fast."""
    try:
        cutoff = (datetime.now(timezone.utc) - timedelta(days=max_age_days)).isoformat()
        await asyncio.to_thread(
            lambda: db.table("memory")
                .update({"is_archived": True})
                .eq("user_id", user_id)
                .eq("is_archived", False)
                .lt("created_at", cutoff)
                .execute()
        )
    except Exception as e:
        print(f"Memory cleanup failed: {e}")
```

> [!IMPORTANT]
> **Timezone standardization**: Use `datetime.now(timezone.utc)` everywhere. `datetime.utcnow()` is deprecated in Python 3.12+ and returns a naive datetime that can cause subtle bugs when compared to timezone-aware timestamps from Supabase.

> [!NOTE]
> The `match_memory` RPC should be updated to filter out archived memories: `AND NOT is_archived` in the SQL function body.

---

#### 

**File**: `app/services/audit_service.py`

**Purpose**: Fire-and-forget audit trail for every significant server action.

##### 

- **DB WRITE**: `audit_log`
- **Never raises**: Failures are print-only
- **Columns**: `user_id, action, entity_type, entity_id, details(jsonb), ip_address, user_agent, created_at`

---

### 

> [!NOTE]
> Duolingo-inspired gamification engine adapted for AI conversation coaching. Drives daily engagement through streaks, XP progression, daily quests, and achievement badges. Designed with **ethical guardrails** — no punishment mechanics, compassionate streak recovery, and intrinsic-motivation-aligned rewards.

#### 

Inspired by **Duolingo** (streaks, XP, quests), **Habitica** (RPG progression), **Headspace** (mindful milestones), and **Finch** (nurture-driven engagement) — but adapted for Bubbles AI's unique context as a conversation coaching assistant.

| Duolingo Mechanic | Bubbles AI Adaptation | Psychological Driver |
|---|---|---|
| Daily streak | Usage streak (any session/consultant interaction) | Loss aversion (gentle) |
| XP per lesson | XP per session, question, entity extraction | Progression & accomplishment |
| Daily quests (3/day) | Randomized from 8 quest templates | Variable rewards & curiosity |
| Levels | Progressive XP curve (triangular numbers) | Milestone satisfaction |
| Badges/trophies | 20 achievement badges across 5 categories | Collection & status |
| Streak freeze | 1 free freeze; earned via milestones | Safety net against churn |
| Leagues/leaderboards | *(Not in v1 — single-player focus)* | — |

**Ethical Guardrails** (critical for a coaching-adjacent app):
- **No punishment**: Streak breaks → "Welcome back!" (never "You lost your streak")
- **No guilt**: Missed days → streak resets silently with encouragement
- **No dark patterns**: No FOMO notifications, no pay-to-win, no artificial urgency
- **Aligned incentives**: XP rewards actual feature usage (sessions, Q&A, extraction), not vanity metrics

---

#### 

##### 

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `user_id` | UUID PK | — | FK → `auth.users(id)` ON DELETE CASCADE |
| `total_xp` | INTEGER | 0 | Cumulative XP earned |
| `level` | INTEGER | 1 | Current level (derived from `total_xp`) |
| `current_streak` | INTEGER | 0 | Consecutive active days |
| `longest_streak` | INTEGER | 0 | All-time max streak |
| `last_active_date` | DATE | NULL | Last date with meaningful activity |
| `streak_freezes` | INTEGER | 1 | Available streak freezes (starts with 1) |
| `created_at` | TIMESTAMPTZ | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | `now()` | Last modification timestamp |

---

##### 

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | UUID PK | `gen_random_uuid()` | Transaction ID |
| `user_id` | UUID | — | FK → `auth.users(id)` ON DELETE CASCADE |
| `amount` | INTEGER | — | XP amount (CHECK > 0) |
| `source_type` | TEXT | — | See source types below |
| `source_id` | TEXT | NULL | Session ID, quest ID, or achievement ID |
| `description` | TEXT | NULL | Human-readable: "Completed wingman session" |
| `created_at` | TIMESTAMPTZ | `now()` | When XP was awarded |

**Valid `source_type` values**: `session_complete`, `consultant_qa`, `quest_complete`, `streak_bonus`, `entity_extraction`, `achievement_unlock`, `first_session_today`

**Index**: `(user_id, created_at DESC)` — for recent XP history queries.

---

##### 

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | TEXT PK | — | Stable slug: `'first_session'`, `'streak_7'`, `'xp_1000'` |
| `title` | TEXT | — | Display name: "Week Warrior" |
| `description` | TEXT | — | Unlock condition: "Used Bubbles 7 days in a row" |
| `icon` | TEXT | `'🏆'` | Emoji or icon identifier |
| `category` | TEXT | `'general'` | `'streak'`, `'session'`, `'mastery'`, `'general'` |
| `criteria_type` | TEXT | — | `'total_xp'`, `'streak'`, `'session_count'`, `'consultant_count'`, `'entity_count'`, `'quest_count'` |
| `criteria_value` | INTEGER | — | Threshold to unlock |
| `xp_reward` | INTEGER | 0 | Bonus XP for unlocking |
| `sort_order` | INTEGER | 0 | Display ordering |
| `created_at` | TIMESTAMPTZ | `now()` | — |

---

##### 

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `user_id` | UUID | — | FK → `auth.users(id)` ON DELETE CASCADE |
| `achievement_id` | TEXT | — | FK → `achievements(id)` ON DELETE CASCADE |
| `awarded_at` | TIMESTAMPTZ | `now()` | When earned |

**PK**: `(user_id, achievement_id)` — prevents duplicate awards.

---

##### 

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | TEXT PK | — | Stable slug: `'daily_session_1'`, `'daily_consultant_1'` |
| `title` | TEXT | — | Display name: "Have a Conversation" |
| `description` | TEXT | NULL | Additional detail |
| `quest_type` | TEXT | `'daily'` | `'daily'`, `'weekly'`, `'milestone'` |
| `action_type` | TEXT | — | `'complete_session'`, `'ask_consultant'`, `'use_wingman_turns'`, `'extract_entities'`, `'save_memory'` |
| `target` | INTEGER | 1 | Actions required to complete |
| `xp_reward` | INTEGER | 25 | XP granted on completion |
| `is_active` | BOOLEAN | `true` | Whether quest is available for assignment |
| `sort_order` | INTEGER | 0 | Display ordering |
| `created_at` | TIMESTAMPTZ | `now()` | — |

---

##### 

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | UUID PK | `gen_random_uuid()` | Row ID |
| `user_id` | UUID | — | FK → `auth.users(id)` ON DELETE CASCADE |
| `quest_id` | TEXT | — | FK → `quest_definitions(id)` ON DELETE CASCADE |
| `progress` | INTEGER | 0 | Current action count |
| `target` | INTEGER | — | Copied from `quest_definitions.target` at assignment |
| `is_completed` | BOOLEAN | `false` | Whether quest is done |
| `assigned_date` | DATE | `CURRENT_DATE` | Day the quest was assigned |
| `completed_at` | TIMESTAMPTZ | NULL | When completed |
| `xp_awarded` | BOOLEAN | `false` | Prevents double XP award |
| `created_at` | TIMESTAMPTZ | `now()` | — |

**Unique constraint**: `(user_id, quest_id, assigned_date)` — one instance per quest per day.

**Index**: `(user_id, assigned_date, is_completed)` — fast lookup of today's active quests.

---

##### 

```sql
-- ============================================================
-- GAMIFICATION TABLES — Run in Supabase SQL Editor
-- ============================================================

CREATE TABLE IF NOT EXISTS user_gamification (
    user_id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    total_xp        INTEGER NOT NULL DEFAULT 0,
    level           INTEGER NOT NULL DEFAULT 1,
    current_streak  INTEGER NOT NULL DEFAULT 0,
    longest_streak  INTEGER NOT NULL DEFAULT 0,
    last_active_date DATE,
    streak_freezes  INTEGER NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS xp_transactions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount          INTEGER NOT NULL CHECK (amount > 0),
    source_type     TEXT NOT NULL,
    source_id       TEXT,
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_xp_transactions_user ON xp_transactions(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS achievements (
    id              TEXT PRIMARY KEY,
    title           TEXT NOT NULL,
    description     TEXT NOT NULL,
    icon            TEXT NOT NULL DEFAULT '🏆',
    category        TEXT NOT NULL DEFAULT 'general',
    criteria_type   TEXT NOT NULL,
    criteria_value  INTEGER NOT NULL,
    xp_reward       INTEGER NOT NULL DEFAULT 0,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_achievements (
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    achievement_id  TEXT NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
    awarded_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, achievement_id)
);

CREATE TABLE IF NOT EXISTS quest_definitions (
    id              TEXT PRIMARY KEY,
    title           TEXT NOT NULL,
    description     TEXT,
    quest_type      TEXT NOT NULL DEFAULT 'daily',
    action_type     TEXT NOT NULL,
    target          INTEGER NOT NULL DEFAULT 1,
    xp_reward       INTEGER NOT NULL DEFAULT 25,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_quests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    quest_id        TEXT NOT NULL REFERENCES quest_definitions(id) ON DELETE CASCADE,
    progress        INTEGER NOT NULL DEFAULT 0,
    target          INTEGER NOT NULL,
    is_completed    BOOLEAN NOT NULL DEFAULT false,
    assigned_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    completed_at    TIMESTAMPTZ,
    xp_awarded      BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, quest_id, assigned_date)
);
CREATE INDEX idx_user_quests_active ON user_quests(user_id, assigned_date, is_completed);
```

---

#### 

**File**: `app/services/gamification_service.py`

**Purpose**: All gamification logic — XP awarding, level computation, streak management, quest progress tracking, and achievement detection. Designed as fire-and-forget: **never raises**, **never blocks critical paths**.

**Initialization**: No model loading, no external clients — pure DB + math.

**Error Handling**: All methods wrapped in try/except. Failures are print-only. Gamification failures must NEVER break core functionality (wingman, consultant, sessions).

**Methods**:

##### 

- **DB WRITE**: `xp_transactions` — inserts XP ledger entry
- **DB READ/WRITE**: `user_gamification` — upserts row, increments `total_xp`, recalculates `level`
- **Side effect**: Calls `check_achievements(user_id)` after XP update
- **First-of-day bonus**: If `last_active_date != today`, awards additional 10 XP with source `first_session_today`
- **Never raises**: Prints error and returns silently on failure

##### 

- **DB READ/WRITE**: `user_gamification`
- **Logic**:
  ```
  today = date.today()  # ⚠️ See timezone note below
  if last_active_date == today:       → no-op (already counted today)
  elif last_active_date == yesterday: → current_streak += 1
  elif last_active_date == 2_days_ago AND streak_freezes > 0:
                                      → streak_freezes -= 1 (freeze consumed, streak preserved)
  else:                               → current_streak = 1 (reset with "Welcome back!")

  if current_streak > longest_streak: → longest_streak = current_streak
  last_active_date = today
  ```
- **Streak bonus**: Awards `min(current_streak × 5, 50)` XP via `award_xp()` with `source_type='streak_bonus'`

> [!IMPORTANT]
> **Timezone consideration**: `date.today()` uses the server's local timezone. A user at UTC+5 (Pakistan) using the app at 11pm will have their activity counted as the same day on a UTC server, but as the next day for their local experience. For an FYP this is acceptable — all streak dates are in **server UTC time**. Document this clearly so the Flutter client can display "daily reset happens at midnight UTC" in the quests UI.

##### 

- **DB READ**: `user_quests` — checks for quests assigned today
- **If no quests today**:
  - **DB READ**: `quest_definitions` — fetches all active `daily` quests
  - Randomly selects 3 (using `random.sample`)
  - **DB WRITE**: `user_quests` — inserts 3 rows with `assigned_date = today`, `target` copied from definition
- **Returns**: List of quest dicts with `id, quest_id, title, description, xp_reward, target, progress, is_completed`

##### 

- **DB READ**: `user_quests` JOIN `quest_definitions` — finds today's quests matching `action_type` that are not completed
- **DB WRITE**: `user_quests` — increments `progress` by `count`
- **Auto-complete**: If `progress >= target`, sets `is_completed = true`, `completed_at = now()`
- **Awards XP**: Calls `award_xp(user_id, xp_reward, 'quest_complete', quest_id)` on completion
- **Achievement check**: Increments quest completion counter for achievement detection

##### 

- **DB READ**: `achievements` — all achievement definitions
- **DB READ**: `user_achievements` — already-earned achievement IDs
- **DB READ**: Aggregate stats from multiple tables:
  - `total_xp` from `user_gamification`
  - `current_streak` from `user_gamification`
  - `session_count` from `sessions` (WHERE `user_id` AND `status = 'completed'`)
  - `consultant_count` from `consultant_logs` (COUNT WHERE `user_id`)
  - `entity_count` from `entities` (COUNT WHERE `user_id`)
  - `quest_count` from `user_quests` (COUNT WHERE `user_id` AND `is_completed = true`)
- **For each un-earned achievement**: If user's stat ≥ `criteria_value` → unlock
- **DB WRITE**: `user_achievements` — inserts earned achievement
- **DB Side effect**: If `xp_reward > 0`, calls `award_xp()` with `source_type='achievement_unlock'`
- **Guard**: Recursive XP → achievement → XP loop is bounded by checking `user_achievements` before awarding (prevents infinite recursion)

##### 

The gamification system must prevent XP farming. Without these guards, a user could call `POST /end_session` 100 times to earn 3,000 XP, or replay sessions to trigger entity extraction XP.

**1. Duplicate source_id prevention** (in `award_xp`):
```python
async def award_xp(self, user_id, amount, source_type, source_id=None, description=None):
    try:
        # Anti-duplicate: Check if this exact source was already awarded
        if source_id:
            existing = db.table("xp_transactions") \
                .select("id") \
                .eq("user_id", user_id) \
                .eq("source_type", source_type) \
                .eq("source_id", source_id) \
                .maybe_single() \
                .execute()
            if existing.data:
                return  # Already awarded for this source — skip
        # ... proceed with XP award ...
    except Exception as e:
        print(f"award_xp error: {e}")
```

**2. Daily XP caps**: No user can earn more than 500 XP/day from automated sources (sessions, extraction). Quests and achievements are exempt.

**3. Session completion validation**: Before awarding `session_complete` XP, verify:
- Session has `status = 'active'` (not already completed)
- Session has at least 3 turns in `session_logs` (prevents empty-session farming)
- Session `user_id` matches the requesting user

**4. Quest progress is non-reversible**: Deleting entities or sessions does NOT reduce quest progress or reclaim XP. XP is an immutable ledger.

##### 

- **DB READ**: `user_gamification` — core stats (creates default row via upsert if missing)
- **DB READ**: `user_achievements` JOIN `achievements` — earned badges with metadata
- **DB READ**: `xp_transactions` — last 10 entries (recent XP history)
- **DB READ**: Aggregate stats from `sessions`, `consultant_logs`, `entities`, `user_quests`
- **Computes**: `xp_to_next_level`, `xp_progress_pct` using level formula
- **Returns**: Full profile dict (see response schema in §14.4)

##### 

- Calls `get_or_assign_daily_quests(user_id)` to ensure today's quests are assigned
- **Returns**: Quest list with progress + metadata (see response schema in §14.4)

##### 

###### 

- **Formula**: `level = floor((1 + sqrt(1 + 4 × total_xp / 50)) / 2)`
- Uses triangular number progression: Level N requires `50 × N × (N-1)` cumulative XP
- **Examples**: 0 XP → L1, 100 XP → L2, 300 XP → L3, 600 XP → L4, 1000 XP → L5

###### 

- Returns cumulative XP required to reach `level`: `50 × level × (level - 1)`

###### 

- Returns cumulative XP required for `level + 1`: `50 × (level) × (level + 1)`

**DB Tables**: `user_gamification` (R/W), `xp_transactions` (R/W), `achievements` (R), `user_achievements` (R/W), `quest_definitions` (R), `user_quests` (R/W), `sessions` (R), `consultant_logs` (R), `entities` (R)

---

#### 

| Endpoint | Method | Auth | Rate Limit | Purpose |
|----------|--------|------|------------|---------|
| `/v1/gamification/{user_id}` | GET | ✅ | 20/min | Full gamification profile |
| `/v1/quests/{user_id}` | GET | ✅ | 20/min | Today's quests with progress |

##### 

**Flow**:
1. Validate `user_id` from path parameter against JWT-verified user
2. Call `gamification_svc.get_gamification_profile(user_id)`
3. Return full profile

**Response**:
```json
{
  "xp": 450,
  "level": 3,
  "xp_current_level": 300,
  "xp_next_level": 600,
  "xp_to_next_level": 150,
  "xp_progress_pct": 0.5,
  "current_streak": 5,
  "longest_streak": 12,
  "streak_freezes": 1,
  "last_active_date": "2026-04-07",
  "badges": [
    {
      "id": "first_session",
      "title": "First Steps",
      "description": "Completed your first wingman session",
      "icon": "🎯",
      "category": "session",
      "awarded_at": "2026-04-01T10:30:00Z"
    }
  ],
  "recent_xp": [
    {
      "amount": 30,
      "source_type": "session_complete",
      "description": "Completed wingman session",
      "created_at": "2026-04-07T14:20:00Z"
    }
  ],
  "stats": {
    "total_sessions": 12,
    "total_consultant_questions": 8,
    "total_entities": 34,
    "total_quests_completed": 7
  }
}
```

> [!IMPORTANT]
> **XP Level Fields**: The server MUST return `xp_current_level` (cumulative XP at start of current level) and `xp_next_level` (cumulative XP needed for next level) using the triangular formula `50 × N × (N-1)`. The Flutter client (`quests_screen.dart:L99-102`) currently uses a flat `100 × level` formula which is **wrong**. By returning these pre-calculated values, the client can display the progress bar correctly without reimplementing the formula.

**DB Tables Read**: `user_gamification`, `user_achievements`, `achievements`, `xp_transactions`, `sessions`, `consultant_logs`, `entities`, `user_quests`

---

##### 

**Flow**:
1. Validate `user_id` from path parameter against JWT-verified user
2. Call `gamification_svc.get_or_assign_daily_quests(user_id)` — creates today's quests if none exist
3. Return quest list with progress

**Response**:
```json
{
  "quests": [
    {
      "id": "uuid-of-user-quest",
      "quest_id": "daily_session_1",
      "title": "Have a Conversation",
      "description": "Complete 1 wingman session",
      "xp_reward": 30,
      "target": 1,
      "progress": 0,
      "is_completed": false,
      "assigned_date": "2026-04-07"
    },
    {
      "quest_id": "daily_consultant_1",
      "title": "Ask the Expert",
      "description": "Ask 1 question to the Consultant",
      "xp_reward": 20,
      "target": 1,
      "progress": 1,
      "is_completed": true,
      "completed_at": "2026-04-07T15:00:00Z"
    }
  ],
  "daily_reset_at": "2026-04-08T00:00:00Z",
  "total_completed_today": 1,
  "total_quests_today": 3
}
```

**DB Tables Read/Written**: `user_quests` (R/W), `quest_definitions` (R)

---

#### 

XP is awarded via **fire-and-forget** `asyncio.create_task()` calls in existing routes. Gamification failures never block or fail the parent request.

| Existing Route | Trigger Point | XP Action | Quest Progress |
|---|---|---|---|
| `POST /process_transcript_wingman` | After successful advice generation | — | `use_wingman_turns` +1 |
| `POST /process_transcript_wingman` | After entity extraction | `entity_extraction` (5 XP × entities, cap 5) | `extract_entities` +count |
| `POST /process_transcript_wingman` | After memory save | — | `save_memory` +1 |
| `POST /end_session` | After session marked completed | `session_complete` (30 XP) | `complete_session` +1 |
| `POST /end_session` | After session marked completed | `update_streak()` | — |
| `POST /end_session` | After summary saved to memory | — | `save_memory` +1 |
| `POST /save_session` | After session fully saved | `session_complete` (30 XP) | `complete_session` +1 |
| `POST /save_session` | After session fully saved | `update_streak()` | — |
| `POST /save_session` | After memory save | — | `save_memory` +1 |
| `POST /ask_consultant` | After answer returned | `consultant_qa` (15 XP) | `ask_consultant` +1 |
| `POST /ask_consultant` | After answer returned | `update_streak()` | — |
| `POST /ask_consultant` | After consultant answer saved to memory | — | `save_memory` +1 |
| `POST /ask_consultant_stream` | After stream completed (post-processing) | `consultant_qa` (15 XP) | `ask_consultant` +1 |
| `POST /ask_consultant_stream` | After stream completed (post-processing) | `update_streak()` | — |
| `POST /ask_consultant_stream` | After consultant answer saved to memory | — | `save_memory` +1 |

**Implementation pattern** (added at the end of existing route handlers):
```python
# Fire-and-forget — never blocks the response
asyncio.create_task(gamification_svc.award_xp(
    user_id, 30, "session_complete", session_id, "Completed wingman session"
))
asyncio.create_task(gamification_svc.increment_quest_progress(
    user_id, "complete_session", 1
))
asyncio.create_task(gamification_svc.update_streak(user_id))
```

**Import required** in `sessions.py` and `consultant.py`:
```python
from app.services import gamification_svc
```

---

#### 

| Action | XP Amount | Source Type | Cap |
|--------|-----------|-------------|-----|
| Complete a wingman session | 30 | `session_complete` | — |
| Ask a consultant question | 15 | `consultant_qa` | — |
| First action of the day | 10 | `first_session_today` | 1/day |
| Entity extraction | 5 per entity | `entity_extraction` | 25 XP/session (5 entities max) |
| Daily streak bonus | 5 × streak_count | `streak_bonus` | 50 XP/day (streak ≥ 10) |
| Quest completion | varies (15–60) | `quest_complete` | 3 quests/day |
| Achievement unlocked | varies (25–1000) | `achievement_unlock` | — |

**Typical daily earnings** (active user):
- 2 sessions (60 XP) + 1 consultant Q (15 XP) + streak bonus (25 XP at day 5) + first-of-day (10 XP) + quests (70 XP) = **~180 XP/day**

---

#### 

**Formula**: `cumulative_xp(level) = 50 × level × (level - 1)`

| Level | Cumulative XP Required | XP in This Level | Approx. Days at ~150 XP/day |
|-------|------------------------|-------------------|--------------------------|
| 1 | 0 | 100 | 0 |
| 2 | 100 | 200 | 1 |
| 3 | 300 | 300 | 2 |
| 4 | 600 | 400 | 4 |
| 5 | 1,000 | 500 | 7 |
| 7 | 2,100 | 700 | 14 |
| 10 | 4,500 | 1,000 | 30 |
| 15 | 10,500 | 1,500 | 70 |
| 20 | 19,000 | 2,000 | 127 |

A user earning ~150 XP/day (2-3 sessions + quests + streak bonus) reaches:
- **Level 5** in ~1 week (strong early progression feel)
- **Level 10** in ~1 month (sustained engagement)
- **Level 15** in ~2.5 months (dedicated user milestone)

---

#### 

##### 

| ID | Icon | Title | Category | Criteria | XP Reward |
|---|---|---|---|---|---|
| `streak_3` | 🔥 | 3-Day Streak | streak | streak ≥ 3 | 25 |
| `streak_7` | ⚡ | Week Warrior | streak | streak ≥ 7 | 75 |
| `streak_14` | 💪 | Fortnight Force | streak | streak ≥ 14 | 150 |
| `streak_30` | 👑 | Monthly Master | streak | streak ≥ 30 | 500 |
| `first_session` | 🎯 | First Steps | session | sessions ≥ 1 | 50 |
| `sessions_5` | 🗣️ | Getting the Hang | session | sessions ≥ 5 | 100 |
| `sessions_25` | 🎤 | Conversation Pro | session | sessions ≥ 25 | 250 |
| `sessions_100` | 🏆 | Master Communicator | session | sessions ≥ 100 | 1000 |
| `first_consul` | 🧠 | Curious Mind | mastery | consultant ≥ 1 | 25 |
| `consul_10` | 💡 | Deep Thinker | mastery | consultant ≥ 10 | 100 |
| `consul_50` | 📚 | Wisdom Seeker | mastery | consultant ≥ 50 | 300 |
| `xp_100` | ⭐ | Rising Star | general | total_xp ≥ 100 | 0 |
| `xp_500` | 🌟 | Shining Bright | general | total_xp ≥ 500 | 0 |
| `xp_1000` | 💫 | Supernova | general | total_xp ≥ 1000 | 0 |
| `xp_5000` | 🏅 | Legendary | general | total_xp ≥ 5000 | 0 |
| `entities_10` | 👥 | People Person | mastery | entities ≥ 10 | 50 |
| `entities_50` | 🕸️ | Network Builder | mastery | entities ≥ 50 | 200 |
| `quests_5` | 📋 | Quest Starter | general | quests ≥ 5 | 50 |
| `quests_25` | 🎖️ | Quest Master | general | quests ≥ 25 | 200 |

##### 

```sql
INSERT INTO achievements (id, title, description, icon, category, criteria_type, criteria_value, xp_reward, sort_order) VALUES
('streak_3',      '3-Day Streak',        'Used Bubbles 3 days in a row',          '🔥', 'streak',  'streak',           3,   25,  1),
('streak_7',      'Week Warrior',        'Used Bubbles 7 days in a row',          '⚡', 'streak',  'streak',           7,   75,  2),
('streak_14',     'Fortnight Force',     'Used Bubbles 14 days in a row',         '💪', 'streak',  'streak',          14,  150,  3),
('streak_30',     'Monthly Master',      'Used Bubbles 30 days in a row',         '👑', 'streak',  'streak',          30,  500,  4),
('first_session', 'First Steps',         'Completed your first wingman session',  '🎯', 'session', 'session_count',    1,   50, 10),
('sessions_5',    'Getting the Hang',    'Completed 5 wingman sessions',          '🗣️', 'session', 'session_count',    5,  100, 11),
('sessions_25',   'Conversation Pro',    'Completed 25 wingman sessions',         '🎤', 'session', 'session_count',   25,  250, 12),
('sessions_100',  'Master Communicator', 'Completed 100 wingman sessions',        '🏆', 'session', 'session_count',  100, 1000, 13),
('first_consul',  'Curious Mind',        'Asked your first consultant question',  '🧠', 'mastery', 'consultant_count',  1,   25, 20),
('consul_10',     'Deep Thinker',        'Asked 10 consultant questions',         '💡', 'mastery', 'consultant_count', 10,  100, 21),
('consul_50',     'Wisdom Seeker',       'Asked 50 consultant questions',         '📚', 'mastery', 'consultant_count', 50,  300, 22),
('xp_100',        'Rising Star',         'Earned 100 total XP',                   '⭐', 'general', 'total_xp',       100,    0, 30),
('xp_500',        'Shining Bright',      'Earned 500 total XP',                   '🌟', 'general', 'total_xp',       500,    0, 31),
('xp_1000',       'Supernova',           'Earned 1000 total XP',                  '💫', 'general', 'total_xp',      1000,    0, 32),
('xp_5000',       'Legendary',           'Earned 5000 total XP',                  '🏅', 'general', 'total_xp',      5000,    0, 33),
('entities_10',   'People Person',       'Discovered 10 entities',                '👥', 'mastery', 'entity_count',    10,   50, 40),
('entities_50',   'Network Builder',     'Discovered 50 entities',                '🕸️', 'mastery', 'entity_count',    50,  200, 41),
('quests_5',      'Quest Starter',       'Completed 5 daily quests',              '📋', 'general', 'quest_count',      5,   50, 50),
('quests_25',     'Quest Master',        'Completed 25 daily quests',             '🎖️', 'general', 'quest_count',     25,  200, 51);
```

##### 

| ID | Title | Action Type | Target | XP Reward |
|---|---|---|---|---|
| `daily_session_1` | Have a Conversation | `complete_session` | 1 | 30 |
| `daily_session_2` | Talk it Out | `complete_session` | 2 | 60 |
| `daily_consultant_1` | Ask the Expert | `ask_consultant` | 1 | 20 |
| `daily_consultant_3` | Knowledge Hunter | `ask_consultant` | 3 | 50 |
| `daily_wingman_10` | Active Listener | `use_wingman_turns` | 10 | 25 |
| `daily_wingman_25` | Flow State | `use_wingman_turns` | 25 | 50 |
| `daily_entities_3` | Discover Connections | `extract_entities` | 3 | 35 |
| `daily_memory_1` | Memory Keeper | `save_memory` | 1 | 15 |

##### 

```sql
INSERT INTO quest_definitions (id, title, description, quest_type, action_type, target, xp_reward, sort_order) VALUES
('daily_session_1',    'Have a Conversation',  'Complete 1 wingman session',          'daily', 'complete_session',   1, 30, 1),
('daily_session_2',    'Talk it Out',          'Complete 2 wingman sessions',         'daily', 'complete_session',   2, 60, 2),
('daily_consultant_1', 'Ask the Expert',       'Ask 1 question to the Consultant',    'daily', 'ask_consultant',     1, 20, 3),
('daily_consultant_3', 'Knowledge Hunter',     'Ask 3 questions to the Consultant',   'daily', 'ask_consultant',     3, 50, 4),
('daily_wingman_10',   'Active Listener',      'Process 10 wingman turns',            'daily', 'use_wingman_turns', 10, 25, 5),
('daily_wingman_25',   'Flow State',           'Process 25 wingman turns',            'daily', 'use_wingman_turns', 25, 50, 6),
('daily_entities_3',   'Discover Connections', 'Extract 3 new entities',              'daily', 'extract_entities',   3, 35, 7),
('daily_memory_1',     'Memory Keeper',        'Save at least 1 memory',              'daily', 'save_memory',        1, 15, 8);
```

---

#### 

```mermaid
sequenceDiagram
    participant F as Flutter
    participant S as Server
    participant DB as Supabase
    participant G as GamificationSvc

    Note over F,G: === User completes a session ===
    F->>S: POST /v1/end_session
    S->>DB: UPDATE sessions (completed)
    S->>S: asyncio.create_task (fire-and-forget)
    S-->>F: {status: "completed"}

    Note over S,G: Background (non-blocking)
    S->>G: award_xp(user_id, 30, "session_complete")
    G->>DB: INSERT xp_transactions
    G->>DB: UPSERT user_gamification (total_xp, level)
    G->>G: check_achievements(user_id)
    G->>DB: SELECT achievements vs user_achievements
    G->>DB: INSERT user_achievements (if newly earned)

    S->>G: increment_quest_progress(user_id, "complete_session")
    G->>DB: UPDATE user_quests (progress++)
    G->>DB: If quest completed → award_xp(xp_reward)

    S->>G: update_streak(user_id)
    G->>DB: UPDATE user_gamification (streak, last_active_date)
    G->>DB: award_xp(streak_bonus)

    Note over F,G: === User opens Quests screen ===
    F->>S: GET /v1/gamification/{user_id}
    S->>G: get_gamification_profile(user_id)
    G->>DB: SELECT user_gamification
    G->>DB: SELECT user_achievements JOIN achievements
    G->>DB: SELECT xp_transactions (last 10)
    G->>DB: COUNT sessions, consultant_logs, entities, user_quests
    G-->>S: profile dict
    S-->>F: {xp, level, badges, recent_xp, stats}

    F->>S: GET /v1/quests/{user_id}
    S->>G: get_or_assign_daily_quests(user_id)
    G->>DB: SELECT user_quests WHERE assigned_date = today
    G->>DB: If none → SELECT quest_definitions → INSERT 3 user_quests
    G-->>S: quests list
    S-->>F: {quests: [...], daily_reset_at}
```

---

#### 

No new request models needed (both endpoints use path-parameter `user_id`).

Response models are implicit (Dict returns), but the response schemas are documented in §14.4 above. The Flutter client expects:

| Flutter Field | Gamification Response | Type |
|---|---|---|
| `_gamification?['xp']` | `xp` | `int` |
| `_gamification?['level']` | `level` | `int` |
| `_gamification?['badges']` | `badges` | `List[Dict]` (each has `id, title, description, icon, category, awarded_at`) |
| `_quests?['quests']` | `quests` | `List[Dict]` (each has `title, xp_reward, target, progress, is_completed`) |

---

#### 

**Update** `app/services/__init__.py`:

```python
from app.services.gamification_service import GamificationService
gamification_svc = GamificationService()
```

**Update** `app/main.py` — mount router:

```python
from app.routes import gamification
v1.include_router(gamification.router)
```

---

## 7. Data Layer & Core Infra

### 

#### 

**Purpose**: Creates the FastAPI app, mounts routers, configures middleware, starts background tasks.

**Responsibilities**:
- Initialize FastAPI with metadata (title, version, description) using `lifespan` context manager
- Configure CORS middleware from `ALLOWED_ORIGINS`
- Register SlowAPI rate limiter + exception handler
- Mount `health.router` at root (no prefix, no auth)
- Mount all business routers under `/v1` prefix (including `gamification.router` — **[NEW]**)  
- Start background task: stale session cleanup (every 30 min, 6h TTL)
- Print startup diagnostics (auth mode, session store backend)

**Key Design Decisions**:
- Auth is **not** applied as middleware — it's per-endpoint via `Depends(get_verified_user)`
- Health check remains public (no auth required)
- Background cleanup is a single `asyncio.create_task` launched on startup
- **Use `lifespan` context manager** (NOT `@app.on_event("startup")` which is deprecated in FastAPI)

**Graceful Shutdown Pattern**:
```python
import asyncio
from contextlib import asynccontextmanager

# Track all fire-and-forget tasks so we can drain them on shutdown
_background_tasks: set[asyncio.Task] = set()

def fire_and_forget(coro):
    """Create a tracked background task. Use instead of bare asyncio.create_task()
    for gamification XP, quest progress, and other non-critical work."""
    task = asyncio.create_task(coro)
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # === Startup warm-up ===
    vector_svc.model  # Trigger lazy load
    _ = vector_svc.encode("warmup query")  # Pre-JIT ONNX
    if hasattr(database, 'connect'):
        await database.connect()  # asyncpg pool
    
    # Verify LLM connectivity
    await brain_svc.aclient.chat.completions.create(
        model=settings.WINGMAN_MODEL,
        messages=[{"role": "user", "content": "ping"}],
        max_tokens=1
    )
    print("🚀 All services warmed up and ready")
    
    # Start background cleanup
    cleanup_task = asyncio.create_task(_cleanup_stale_sessions())
    
    yield  # Server is running
    
    # === Shutdown: drain background tasks ===
    cleanup_task.cancel()
    if _background_tasks:
        print(f"⏳ Draining {len(_background_tasks)} background task(s)...")
        done, pending = await asyncio.wait(_background_tasks, timeout=10)
        if pending:
            print(f"⚠️ {len(pending)} task(s) did not complete in time")
    if hasattr(database, 'disconnect'):
        await database.disconnect()
    print("👋 Server shut down cleanly")

app = FastAPI(title="Bubbles Brain API", version="3.0.0", lifespan=lifespan)
```

> [!IMPORTANT]
> **All `asyncio.create_task()` calls for gamification (XP, quests, streaks) should use `fire_and_forget()` instead.** This ensures that on server shutdown (deploy, restart), in-flight XP awards complete before the process exits. Without this, users randomly lose earned XP on every deploy.

**DB Tables**: None directly (delegates to services)

---

#### 

**Purpose**: Single `Settings` class holding all environment variables.

**Key Behavior**:
- Loads `.env` from `../../env/.env` (project root) first, then falls back to `../.env`
- Exposes LiveKit env vars to `os.environ` for SDK auto-detection
- `DEBUG_SKIP_AUTH` flag: when `true`, JWT verification is bypassed entirely

**No DB interaction.**

---

#### 

**Purpose**: Creates a single `supabase.Client` instance using the **service-role key**.

**Key Details**:
- Uses `SUPABASE_SERVICE_KEY` (not anon key) — bypasses all RLS
- Sets PostgREST timeout to 10 seconds
- Module-level singleton: `from app.database import db`
- Gracefully handles connection failure (sets `db = None`)

**All 40+ tables** are accessed through this client.

---

#### 

**`Dockerfile`**: Python 3.11-slim, installs build tools, copies requirements first (layer cache), exposes port 8000.

**`docker-compose.yml`**:
- **Redis** (7-alpine): appendonly persistence, 256MB max, LRU eviction, healthcheck
- **Server**: builds from Dockerfile, loads `../env/.env`, overrides `REDIS_URL`, 4 workers, healthcheck
- Volumes: `model_cache` (sentence-transformers), `redis_data`

---

### 

**Auto-selecting backend**: If `REDIS_URL` is set, uses Redis; otherwise, in-memory dicts.

**Interface** (all async):
- `set_live_session(user_id, session_id)` — Maps user to active session
- `get_live_session(user_id)` → session_id
- `set_metadata(session_id, metadata)` — Stores metadata dict (ephemeral, persona, etc.)
- `get_metadata(session_id)` → dict
- `delete_session(session_id, user_id)` — Removes all keys
- `increment_turn_count(session_id)` → int
- `evict_stale(cutoff)` — Removes sessions older than cutoff
- `evict_oldest_if_over(max_count)` — Cap total sessions

**Redis TTL**: 6 hours for all keys.

### 

> [!IMPORTANT]
> This matrix shows which server files READ (R), WRITE (W), or DELETE (D) each table.

| DB Table | sessions.py | consultant.py | voice.py | analytics.py | entities.py | Services |
|----------|:-----------:|:-------------:|:--------:|:------------:|:-----------:|:--------:|
| `sessions` | R/W | R/W | W | R | — | session_svc(R/W) |
| `session_logs` | W | W | — | R | — | session_svc(R/W) |
| `consultant_logs` | — | W | W | — | — | session_svc(R/W) |
| `sentiment_logs` | W | — | — | R | — | session_svc(W) |
| `memory` | W | W | — | R | — | vector_svc(R/W) |
| `knowledge_graphs` | W | W | W | — | R | graph_svc(R/W) |
| `entities` | W | — | — | — | R/D | entity_svc(R/W) |
| `entity_attributes` | W | — | — | — | R/D | entity_svc(R/W) |
| `entity_relations` | W | — | — | — | R/D | entity_svc(R/W) |
| `highlights` | W | — | — | R | — | entity_svc(W) |
| `events` | W | — | — | R | — | entity_svc(W) |
| `tasks` | W | — | — | — | — | entity_svc(W) |
| `feedback` | — | — | — | W | — | — |
| `session_analytics` | W | — | — | R/W | — | — |
| `coaching_reports` | — | — | — | R/W | — | — |
| `voice_enrollments` | — | — | R/W | — | — | — |
| `audit_log` | W | W | W | W | W | audit_svc(W) |
| `profiles` | — | — | — | — | — | health.py(R) |
| `tags` | — | — | — | — | — | — (Flutter-only) |
| `session_tags` | — | — | — | — | — | — (Flutter-only) |
| `user_gamification` | — | — | — | — | — | gamification_svc(R/W) |
| `xp_transactions` | — | — | — | — | — | gamification_svc(R/W) |
| `achievements` | — | — | — | — | — | gamification_svc(R) |
| `user_achievements` | — | — | — | — | — | gamification_svc(R/W) |
| `quest_definitions` | — | — | — | — | — | gamification_svc(R) |
| `user_quests` | — | — | — | — | — | gamification_svc(R/W) |

#### 

These tables are managed directly by the Flutter app through Supabase client:
- `user_settings`, `user_devices`, `onboarding_progress`, `profiles` (CRUD)
- `tags`, `session_tags`, `entity_tags`
- `health_metrics`, `expenses`, `trips`
- `iot_devices`, `iot_logs`
- `notifications`, `notification_tokens`
- `integrations`, `calendar_integrations`, `calendar_sync_log`
- `team_workspaces`, `team_members`, `shared_sessions`
- `subscriptions`, `subscription_usage`
- `feature_flags`, `data_deletion_requests`, `app_feedback`
- `multimodal_attachments`, `audio_sessions`, `session_exports`
- `user_routines`, `api_keys`, `webhooks`

---

### 

#### 

- **All route handlers are `async`**
- **Sync Supabase calls** are wrapped in `asyncio.to_thread()` to avoid blocking the event loop
- **LLM calls** use `AsyncGroq` natively (truly async)
- **Embedding** calls use `asyncio.to_thread()` (CPU-bound)
- **Background tasks** use `asyncio.create_task()` for fire-and-forget work

#### 

- JWT verification via Supabase `auth.get_user()`
- Prompt injection sanitization on all user inputs
- Rate limiting on all business endpoints
- Service-role key used server-side (RLS disabled — server enforces ownership)
- CORS configurable per deployment

#### 

- **Redis** for production multi-worker deployments
- **In-memory dicts** for local/single-worker development
- 6-hour TTL on all session state
- Global cap of 500 concurrent sessions
- Background cleanup every 30 minutes

## 8. Error Handling & Degradation

### 

- Services **never raise** — they return fallback values and print errors
- Routes catch exceptions and return HTTP error codes
- Audit service is fully fire-and-forget (never raises)
- LLM calls have exponential backoff retries (2-3 attempts)

### 

```mermaid
flowchart TD
    A[Request Arrives] --> B{Auth Check}
    B -->|Fail| C[401 auth_failed]
    B -->|Pass| D{Rate Limit Check}
    D -->|Exceeded| E[429 rate_limited]
    D -->|Pass| F{Pydantic Validation}
    F -->|Fail| G[400 validation_error]
    F -->|Pass| H[Route Handler]
    H -->|LLM Timeout| I[502 llm_error]
    H -->|DB Down| J[503 service_unavailable]
    H -->|Ownership Check Fail| K[403 forbidden]
    H -->|Resource Missing| L[404 not_found]
    H -->|Unhandled| M[500 internal_error]
    H -->|Success| N[200 Response]

    style C fill:#ff6b6b
    style E fill:#ffa06b
    style G fill:#ffa06b
    style I fill:#ff6b6b
    style J fill:#ff6b6b
    style N fill:#51cf66
```

### 

| Service | On Failure Returns | Never Raises | Critical to User |
|---|---|---|---|
| `BrainService` | Fallback dict with `"answer": "WAITING"` (wingman) or re-raises for consultant | ✅ (wingman) / ❌ (consultant) | ✅ |
| `SessionService` | `None` or empty string | ✅ | ✅ |
| `EntityService` | Empty list `[]` or skips persistence | ✅ | ❌ |
| `GraphService` | Empty string `""` or empty graph | ✅ | ❌ |
| `VectorService` | `"No relevant past memories."` | ✅ | ❌ |
| `AuditService` | Silent failure (print only) | ✅ | ❌ |
| `GamificationService` | Silent failure (print only) | ✅ | ❌ |

---

### 

§11.2 states "Services never raise — they return fallback values" but doesn't specify what those fallback values are. This matrix defines **exact behavior** when external dependencies fail:

| Dependency | Failure Mode | Affected Endpoints | Fallback Behavior |
|---|---|---|---|
| **Groq API** (rate limited) | HTTP 429 / timeout | wingman, consultant, extraction | LiteLLM auto-fallback to Cerebras/Gemini. If ALL fail: wingman returns `{"advice": "WAITING"}`, consultant returns HTTP 502 with `llm_error` |
| **Groq API** (malformed JSON from extraction) | JSON parse error | wingman (extraction step) | Skip extraction + persistence entirely. Log error. User still receives advice. |
| **Embedding model** (not loaded) | `vector_svc.model is None` | wingman, consultant, save_session | Skip memory search, return `"No relevant past memories."` as context. Health endpoint reports `"status": "degraded"`. |
| **Supabase DB** (unreachable) | Connection timeout | ALL | Health returns 503. Session endpoints return HTTP 503 with `db_unavailable`. Queue critical writes to Redis if available. |
| **Supabase DB** (single query fails) | Individual query error | Varies | Log error, continue with empty result for READ operations. For WRITE failures: return error to client for critical writes (session_logs), skip silently for non-critical writes (audit_log, sentiment_logs). |
| **Redis** (unavailable) | Connection refused | Session state | Auto-fallback to in-memory dicts (already implemented via `session_store.py`). |
| **Knowledge graph** (corrupt JSON) | Parse error on `graph_data` | wingman, consultant | Create fresh empty graph for user. Log error with old data for debugging. |
| **ECAPA-TDNN model** (fails to load) | Import/download error | `/v1/enroll` | Return HTTP 503 with `"model_unavailable"`. Do NOT crash the server. |

> [!IMPORTANT]
> **Critical rule**: A failure in extraction, persistence, or context loading must NEVER prevent the user from receiving wingman advice. The user-facing response path (log → context → LLM → respond) is sacred. Everything after that is best-effort.

### 

Every external call must have an explicit timeout. Without these, a single hung LLM call can block a worker indefinitely.

| External Call | Timeout | Retry Count | Retry Delay | Notes |
|---|---|---|---|---|
| Groq LLM — wingman advice | 5s | 2 | 500ms | User is waiting in real-time |
| Groq LLM — consultant answer | 15s | 3 | 1s, 2s, 3s (progressive) | User expects slower response |
| Groq LLM — extraction | 10s | 1 | — | Background work, no retry needed |
| Groq LLM — summary | 8s | 1 | — | Background work |
| Groq LLM — highlight extraction | 8s | 1 | — | Background work |
| Supabase PostgREST (general) | 10s | 0 | — | Already configured in `database.py` |
| `match_memory` RPC (vector search) | 5s | 0 | — | Should be fast with HNSW index |
| Embedding encode (`to_thread`) | 3s | 0 | — | CPU-bound, ~8-20ms normally |
| ECAPA-TDNN voice embedding | 30s | 0 | — | Lazy model load on first call |
| LiveKit token generation | 5s | 0 | — | Local JWT signing, effectively instant |
| Redis operations | 2s | 0 | — | Should be <10ms, timeout catches network issues |

**Implementation**: Set timeouts via `asyncio.wait_for()` for async calls:
```python
try:
    result = await asyncio.wait_for(
        brain_svc.get_wingman_advice(...),
        timeout=5.0
    )
except asyncio.TimeoutError:
    logger.error("llm_timeout", model="wingman", timeout_s=5)
    return {"advice": "WAITING"}
```

## 9. Observability & SLAs

### 

Performance targets for each endpoint. Use these to measure whether optimizations (§13) are working.

| Endpoint | Target P50 | Target P95 | Hard Limit (timeout) | Notes |
|---|---|---|---|---|
| `POST /v1/process_transcript_wingman` | < 800ms | < 1500ms | 10s | Most critical — user is mid-conversation |
| `POST /v1/ask_consultant` (blocking) | < 3s | < 6s | 30s | User expects deeper processing |
| `POST /v1/ask_consultant_stream` (TTFB) | < 500ms | < 1s | 60s | Time-to-first-byte matters most |
| `POST /v1/start_session` | < 200ms | < 500ms | 10s | Quick UI transition |
| `POST /v1/end_session` | < 1s | < 2s | 30s | Background work is hidden |
| `POST /v1/save_session` | < 2s | < 4s | 15s | Batch processing |
| `GET /v1/gamification/{user_id}` | < 200ms | < 500ms | 10s | Dashboard load |
| `GET /v1/quests/{user_id}` | < 200ms | < 500ms | 10s | Dashboard load |
| `GET /v1/session_analytics/{id}` | < 300ms | < 500ms | 10s | Pre-computed data |
| `GET /v1/coaching_report/{id}` | < 500ms (cached) / < 5s (gen) | < 1s / < 8s | 30s | May trigger LLM generation |
| `GET /health` | < 50ms | < 200ms | 5s | Must be fast for uptime monitors |

> [!TIP]
> Measure these with the structured logger (§7.5). Add a middleware that logs total request duration for every endpoint, then aggregate P50/P95 offline.

---

### 

Every request receives a unique `X-Request-ID` header that flows through all services and into audit logs. This is **essential** for debugging — without it, tracing a single wingman request across 10+ DB calls and 2 LLM calls is impossible.

```python
# Middleware in main.py
from uuid import uuid4

@app.middleware("http")
async def add_request_id(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID", str(uuid4())[:12])
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response
```

**Propagation**: Pass `request_id` into:
- `audit_svc.log(... details={"request_id": rid})` — audit trail correlation
- Error responses (`ErrorResponse.request_id`) — client-side debugging
- Groq API calls (`user=request_id`) — provider-side observability
- Structured logger context (`logger.info("event", request_id=rid)`) — log filtering

### 

**Purpose**: JSON-formatted logging with timing context for debugging latency across the wingman pipeline's 10+ sub-operations.

**Why not `print()`**: When the wingman endpoint takes 5s instead of 800ms, you need to know *which* sub-operation was slow. `print()` provides no structured data, no timestamps, and no ability to filter in production.

```python
import logging
import json
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone

class StructuredLogger:
    """JSON logger with timing context and request correlation."""

    def __init__(self, name: str):
        self.logger = logging.getLogger(name)
        self.logger.setLevel(logging.INFO)
        if not self.logger.handlers:
            handler = logging.StreamHandler()
            handler.setFormatter(logging.Formatter('%(message)s'))
            self.logger.addHandler(handler)

    def info(self, event: str, **kwargs):
        self.logger.info(json.dumps({
            "event": event,
            "ts": datetime.now(timezone.utc).isoformat(),
            **kwargs
        }))

    def error(self, event: str, **kwargs):
        self.logger.error(json.dumps({
            "event": event,
            "level": "error",
            "ts": datetime.now(timezone.utc).isoformat(),
            **kwargs
        }))

    @asynccontextmanager
    async def timed(self, event: str, **extra):
        """Async context manager that logs operation duration."""
        start = time.perf_counter()
        try:
            yield
        finally:
            duration_ms = round((time.perf_counter() - start) * 1000, 1)
            self.info(event, duration_ms=duration_ms, **extra)
```

**Usage in wingman pipeline**:
```python
logger = StructuredLogger("wingman")

async with logger.timed("context_fetch", user_id=user_id):
    graph_ctx, vector_ctx, entity_ctx = await asyncio.gather(...)
# Output: {"event": "context_fetch", "duration_ms": 145.2, "user_id": "..."}

async with logger.timed("llm_advice", model="wingman"):
    advice = await brain_svc.get_wingman_advice(...)
# Output: {"event": "llm_advice", "duration_ms": 312.8, "model": "wingman"}
```

**Recommended loggers** (one per service):
```python
brain_logger = StructuredLogger("brain")
session_logger = StructuredLogger("session")
entity_logger = StructuredLogger("entity")
vector_logger = StructuredLogger("vector")
gamification_logger = StructuredLogger("gamification")
```

### 

See §7.5 for the `StructuredLogger` implementation. This section defines the standard log events.

**Standard log events per endpoint**:

| Endpoint | Log Events |
|---|---|
| `process_transcript_wingman` | `wingman.start`, `wingman.context_fetch`, `wingman.llm_advice`, `wingman.extraction`, `wingman.persistence`, `wingman.complete` |
| `ask_consultant` | `consultant.start`, `consultant.context_fetch`, `consultant.llm_answer`, `consultant.post_process`, `consultant.complete` |
| `end_session` | `session.end_start`, `session.summary`, `session.analytics`, `session.complete` |
| `save_session` | `session.save_start`, `session.extraction`, `session.persistence`, `session.complete` |

**Every log event includes**: `request_id`, `user_id`, `duration_ms`, `timestamp`.

### 

Extend the existing `/health` endpoint to report sub-system latencies:

```json
{
  "status": "healthy",
  "checks": {
    "database": {"status": "ok", "latency_ms": 12},
    "embedding_model": {"status": "ok", "model": "e5-small-v2"},
    "llm_key": {"status": "ok", "provider": "groq"},
    "redis": {"status": "ok", "latency_ms": 3},
    "active_sessions": 12
  },
  "version": "2.0.0",
  "uptime_seconds": 86400
}
```

---

## 10. FYP Optimizations & Advanced Architecture

### 

> [!NOTE]
> All recommendations below prioritize **free tiers** and **student-friendly pricing**. Each subsection identifies the current bottleneck, the proposed solution, expected latency improvement, and implementation difficulty.

---

#### 

The current architecture uses **Groq** exclusively for all LLM calls. While Groq is fast, you're vulnerable to single-provider rate limits and outages, and you're not leveraging the fastest available options for each task type.

##### 

**Problem**: Single-provider dependency. If Groq rate-limits you (especially on the free tier), the entire app stalls.

**Solution**: Use [LiteLLM](https://github.com/BerriAI/litellm) as a unified LLM gateway with automatic fallback.

| Feature | Benefit |
|---------|---------|
| OpenAI-compatible API | Drop-in replacement — minimal code changes |
| Automatic fallback chains | If Groq fails → Cerebras → Google → Mistral |
| Rate limit detection | Auto-switches provider on 429 errors |
| Token tracking | Built-in spend/usage analytics |

**Implementation**:
```yaml
# litellm_config.yaml
model_list:
  - model_name: "wingman"
    litellm_params:
      model: "groq/llama-3.1-8b-instant"
      api_key: "os.environ/GROQ_API_KEY"
  - model_name: "wingman"  # Same name = fallback pool
    litellm_params:
      model: "cerebras/llama-3.1-8b"
      api_key: "os.environ/CEREBRAS_API_KEY"
  - model_name: "consultant"
    litellm_params:
      model: "groq/llama-3.3-70b-versatile"
      api_key: "os.environ/GROQ_API_KEY"
  - model_name: "consultant"
    litellm_params:
      model: "gemini/gemini-2.5-flash"
      api_key: "os.environ/GEMINI_API_KEY"

router_settings:
  routing_strategy: "latency-based-routing"
  num_retries: 3
  retry_after: 1

fallbacks:
  - "wingman": ["wingman"]
  - "consultant": ["consultant"]
```

**Free Tier**: LiteLLM itself is open-source and free. You just collect free API keys from multiple providers.

**Estimated Impact**: Eliminates rate-limit-induced failures entirely. Reduces P99 latency by routing to the fastest available provider.

**Difficulty**: 🟢 Easy — `pip install litellm`, replace `Groq()` calls with `litellm.completion()`

---

##### 

**Problem**: Groq's 8B model is fast (~500 tok/s), but Cerebras is **significantly faster** on the same models.

**Solution**: Use [Cerebras Inference API](https://cloud.cerebras.ai) as the primary provider for the Wingman (8B) model.

| Provider | Llama 3.1 8B Speed | Free Tier |
|----------|-------------------|-----------|
| **Cerebras** | ~2,000+ tok/s | 30 RPM, 1M tokens/day |
| **Groq** | ~500-800 tok/s | 30 RPM, 14.4K tokens/min |
| **Together AI** | ~200-400 tok/s | $1 free credit |

**Free Tier**: 30 RPM, 1M tokens/day — no credit card required.

**Estimated Impact**: **2-4x faster** wingman response times (from ~200ms to ~50-100ms for 60-token responses).

**Difficulty**: 🟢 Easy — OpenAI-compatible API, just change `base_url` and `api_key`

---

##### 

**Problem**: The 70B consultant model has high latency (~2-5s per response on Groq free tier).

**Solution**: Use [Google AI Studio](https://aistudio.google.com) — Gemini 2.5 Flash for the consultant role.

| Feature | Gemini 2.5 Flash |
|---------|-----------------|
| **Speed** | Comparable to Groq 70B, faster on complex prompts |
| **Context Window** | 1M tokens (vs ~128K for Llama 3.3 70B) |
| **Free Tier** | 1,500 req/day, 1M tokens/min (extremely generous) |
| **Quality** | Competitive with GPT-4o on reasoning benchmarks |

**Why this matters for your app**: The consultant already does 5 parallel context fetches before the LLM call. Gemini's massive context window means you can send ALL context without truncation (currently capped at ~1000 tokens each).

**Estimated Impact**: Better answers (no context truncation), similar or faster latency, 50x more free tokens than Groq.

**Difficulty**: 🟢 Easy — Use via LiteLLM with `gemini/gemini-2.5-flash`

---

##### 

| Provider | Role | Free Limit | Cost After |
|----------|------|-----------|------------|
| **Cerebras** | Wingman (8B) | 1M tok/day | ~$0.10/M tok |
| **Groq** | Wingman fallback | 14.4K tok/min | Free (generous enough) |
| **Google AI Studio** | Consultant (Gemini Flash) | 1,500 req/day, 1M tok/min | Pay-as-you-go |
| **Mistral AI** | Consultant fallback | 1M tok/month (free experiment) | ~$0.30/M tok |

> [!TIP]
> By combining these 4 free tiers with LiteLLM routing, you effectively get **unlimited LLM inference for an FYP** — more than enough for demos, testing, and even a small user base.

---

#### 

##### 

**Problem**: `all-MiniLM-L6-v2` with PyTorch is slow to load (~10s cold start) and uses ~500MB RAM. CPU inference takes ~15-30ms per embedding.

**Solution**: Switch to **`e5-small`** with **ONNX Runtime** for 2-3x faster inference.

| Model | Dimensions | Latency (CPU) | RAM | Quality (MTEB) |
|-------|-----------|---------------|-----|----------------|
| `all-MiniLM-L6-v2` (current) | 384 | ~20ms | ~500MB | Good |
| **`e5-small-v2`** (recommended) | 384 | **~8ms** | ~200MB | Better |
| `nomic-embed-text-v2` | 768 (MRL→256) | ~12ms | ~300MB | Best |

**Key changes**:
```python
# Before (slow, heavy)
from sentence_transformers import SentenceTransformer
model = SentenceTransformer("all-MiniLM-L6-v2")  # PyTorch backend

# After (fast, lightweight)
from optimum.onnxruntime import ORTModelForFeatureExtraction
from transformers import AutoTokenizer
import numpy as np

tokenizer = AutoTokenizer.from_pretrained("intfloat/e5-small-v2")
model = ORTModelForFeatureExtraction.from_pretrained(
    "intfloat/e5-small-v2",
    export=True,               # Auto-converts to ONNX
    provider="CPUExecutionProvider"
)

def encode(text: str) -> list[float]:
    inputs = tokenizer(f"query: {text}", return_tensors="pt", truncation=True)
    outputs = model(**inputs)
    embedding = outputs.last_hidden_state.mean(dim=1).squeeze().detach().numpy()
    return (embedding / np.linalg.norm(embedding)).tolist()
```

**Additional benefit**: Replacing `sentence-transformers` + `torch` with `optimum[onnxruntime]` removes **~2GB** from your Docker image.

**New requirements.txt lines**:
```
optimum[onnxruntime]
transformers
# Remove: sentence-transformers, torch
```

**Estimated Impact**: 
- **Cold start**: 10s → 2s (no PyTorch to load)
- **Per-embedding**: 20ms → 8ms
- **Docker image**: 3GB → ~800MB
- **RAM usage**: 500MB → 200MB

**Difficulty**: 🟡 Medium — requires changing `VectorService` and `GraphService` model loading code

---

##### 

For even lower latency (offload compute to cloud), consider a free embedding API:

| Provider | Model | Free Tier | Latency |
|----------|-------|-----------|---------|
| **Google AI Studio** | `text-embedding-004` | 1,500 req/min | ~30ms (network) |
| **Cohere** | `embed-v4.0` | 1,000 req/month | ~50ms (network) |
| **Jina AI** | `jina-embeddings-v3` | 1M tokens free | ~40ms (network) |

> [!IMPORTANT]
> Local ONNX embedding (8ms) beats cloud APIs (30-50ms) on latency. Use cloud APIs only as fallback when your server is resource-constrained or for batch operations.

---

#### 

##### 

**Problem**: Every DB call goes through the Supabase Python client → PostgREST HTTP API → PostgreSQL. This adds **30-100ms** per call from HTTP overhead. The wingman endpoint makes **10+ DB calls per request**.

**Solution**: Use `asyncpg` (native PostgreSQL async driver) for latency-critical paths, keep Supabase client for simple CRUD.

| Path | Current (PostgREST) | With asyncpg |
|------|---------------------|-------------|
| Single row read | ~50ms | ~5ms |
| Batch insert (10 rows) | ~150ms | ~15ms |
| Vector search (RPC) | ~80ms | ~20ms |

**Implementation strategy** (hybrid approach):
```python
# app/database.py — Add connection pool alongside Supabase client
import asyncpg

class Database:
    def __init__(self):
        self.pool: asyncpg.Pool | None = None
        self.supabase = None  # Keep existing client for simple operations
    
    async def connect(self):
        # Use Supabase direct connection string (port 5432)
        self.pool = await asyncpg.create_pool(
            dsn=settings.SUPABASE_DB_URL,  # postgresql://...@db.xxx.supabase.co:5432/postgres
            min_size=5,
            max_size=20,
            command_timeout=10,
            statement_cache_size=0  # Required for Supavisor compatibility
        )
    
    async def fetch(self, query: str, *args):
        async with self.pool.acquire() as conn:
            return await conn.fetch(query, *args)
```

**Use asyncpg for**: `session_logs` inserts, `match_memory` RPC, `knowledge_graphs` reads/writes, entity queries.
**Keep Supabase client for**: Simple CRUD (profiles, feedback), auth verification, operations using Supabase-specific features.

**New env var needed**:
```env
SUPABASE_DB_URL=postgresql://postgres:[password]@db.[project].supabase.co:5432/postgres
```

**Estimated Impact**: **5-10x faster** DB operations on hot paths. Wingman endpoint total DB time: ~500ms → ~50ms.

**Difficulty**: 🔴 Hard — requires rewriting DB queries from Supabase client builder syntax to raw SQL, and managing connection pooling.

---

##### 

**Problem**: The wingman endpoint currently does ~15 sequential DB operations (log message → fetch contexts → persist entities → save memory → update tokens → ...).

**Solution**: Group independent DB writes into batch operations using `asyncio.gather()` more aggressively.

**Current flow** (sequential where it shouldn't be):
```
1. Log incoming transcript        → DB WRITE
2. Fetch graph context            → DB READ  ┐
3. Fetch vector memory            → DB READ  ├─ Already parallel ✓
4. Fetch entity context           → DB READ  ┘
5. LLM wingman advice             → API CALL
6. Log LLM advice                 → DB WRITE
7. Update token usage             → DB WRITE
8. LLM unified extraction         → API CALL
9. Persist entities               → DB WRITE ┐
10. Update knowledge graph        → DB WRITE ├─ Should be parallel
11. Save conflicts/highlights     → DB WRITE │
12. Save events                   → DB WRITE │
13. Save tasks                    → DB WRITE │
14. Save to memory                → DB WRITE ┘
15. Rolling summarization         → DB R/W
```

**Optimized flow**:
```python
# Steps 6-7: Batch post-LLM writes
await asyncio.gather(
    session_svc.log_message(session_id, "llm", advice, ...),
    session_svc.update_session_token_usage(session_id, tokens_prompt, tokens_comp),
)

# Steps 9-14: Batch ALL persistence after extraction
await asyncio.gather(
    entity_svc.persist_extraction(user_id, extraction, session_id),
    graph_svc.save_graph(user_id),
    entity_svc.save_conflicts(user_id, conflicts, session_id),
    entity_svc.save_events(user_id, events, session_id),
    entity_svc.save_tasks(user_id, tasks, session_id),
    vector_svc.save_memory(user_id, transcript, session_id),
)
```

**Estimated Impact**: Wingman endpoint wall-clock time reduced by **200-400ms** (eliminating sequential waits on independent writes).

**Difficulty**: 🟢 Easy — pure code restructuring, no new dependencies

---

##### 

**Problem**: Default pgvector index settings may not be optimal for your data size and query patterns.

**Solution**: Tune the HNSW index on the `memory` table for your use case.

```sql
-- Current (likely default or IVFFlat)
-- Upgrade to HNSW with tuned parameters

-- Drop existing index if any
DROP INDEX IF EXISTS memory_embedding_idx;

-- Create optimized HNSW index
CREATE INDEX memory_embedding_hnsw_idx ON memory 
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Set search parameters for speed (lower = faster, less accurate)
SET hnsw.ef_search = 20;  -- Default is 40. 20 is fine for top-3 results.

-- Use halfvec for 50% memory savings (if pgvector >= 0.7)
-- ALTER TABLE memory ALTER COLUMN embedding TYPE halfvec(384);
```

**Estimated Impact**: Vector search latency: ~50ms → ~10ms for collections under 100K vectors.

**Difficulty**: 🟢 Easy — single SQL migration

---

#### 

##### 

**Problem**: Graph context and entity context are fetched from DB on every single wingman call, even if the data hasn't changed in the last 30 seconds.

**Solution**: Add short-TTL caches for frequently accessed, slowly-changing data.

```python
from functools import lru_cache
from cachetools import TTLCache
import asyncio

# Cache knowledge graph context (per-user, 60s TTL)
_graph_cache = TTLCache(maxsize=100, ttl=60)

async def find_context_cached(user_id: str, text: str, top_k: int = 5) -> str:
    cache_key = f"{user_id}:{hash(text)}"
    if cache_key in _graph_cache:
        return _graph_cache[cache_key]
    result = await self.find_context(user_id, text, top_k)
    _graph_cache[cache_key] = result
    return result
```

**What to cache** (with recommended TTLs):

| Data | TTL | Reason |
|------|-----|--------|
| Graph context | 60s | Rarely changes mid-session |
| Entity context | 60s | Updated per extraction, but queried per turn |
| Vector memory search | 30s | Memory rarely added mid-turn |
| Session metadata | 300s | Almost never changes after creation |
| Consultant history | 120s | Only changes when new Q&A is logged |

**New dependency**: `pip install cachetools` (lightweight, no external service needed)

**Estimated Impact**: Eliminates 3-5 DB calls per wingman request when data hasn't changed. Saves ~100-200ms per request.

**Difficulty**: 🟢 Easy — add `cachetools.TTLCache` around existing service methods

---

##### 

**Problem**: Self-hosted Redis requires running a container. In production, you need to manage persistence, memory limits, and availability.

**Solution**: Use [Upstash](https://upstash.com) — serverless Redis with a generous free tier.

| Feature | Self-Hosted Redis | Upstash Free Tier |
|---------|------------------|-------------------|
| **Setup** | Docker container required | Zero-ops, cloud-hosted |
| **Free Limit** | N/A (you pay for hosting) | 500K commands/month, 256MB |
| **Latency** | ~1ms (local) | ~5-10ms (regional) |
| **Persistence** | Manually configured | Automatic |
| **Global** | Single region | Multi-region available |

**For FYP**: The free tier (500K commands/month) is more than sufficient. Your session store operations are lightweight (~50 commands per session).

**Implementation**: Drop-in replacement — same Redis protocol. Just change `REDIS_URL`:
```env
REDIS_URL=rediss://default:xxx@global-xxx.upstash.io:6379
```

**Difficulty**: 🟢 Easy — just change the connection URL

---

#### 

##### 

**Problem**: The consultant streaming endpoint (`/v1/ask_consultant_stream`) may buffer tokens if behind a reverse proxy.

**Solution**: Apply these optimizations:

```python
# 1. Disable response buffering headers
from starlette.responses import StreamingResponse

async def stream_consultant():
    async def generate():
        async for chunk in llm_stream:
            yield f"data: {json.dumps({'token': chunk})}\n\n"
        yield f"data: {json.dumps({'done': True})}\n\n"
    
    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",       # Nginx: disable buffering
            "Transfer-Encoding": "chunked",   # Force chunked transfer
        }
    )

# 2. Nginx config (if using reverse proxy)
# location /v1/ask_consultant_stream {
#     proxy_buffering off;
#     proxy_read_timeout 300;
#     proxy_set_header Connection '';
#     chunked_transfer_encoding on;
# }
```

**Estimated Impact**: Eliminates buffering-induced delays (tokens appear instantly instead of in batches).

**Difficulty**: 🟢 Easy — header changes + proxy config

---

##### 

**Problem**: The wingman uses HTTP POST per speech chunk. Each request has TCP/TLS handshake overhead (~50-100ms).

**Solution**: Consider upgrading the wingman to use **WebSockets** for persistent connection during a session.

```python
# Server side
@router.websocket("/v1/ws/wingman/{session_id}")
async def wingman_ws(websocket: WebSocket, session_id: str):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_json()
            advice = await process_wingman(data)
            await websocket.send_json({"advice": advice})
    except WebSocketDisconnect:
        pass
```

**Benefits**:
- Eliminates per-request TCP/TLS overhead
- Persistent connection = ~0ms handshake after initial connect
- Natural bidirectional communication for real-time features
- Simpler client-side logic (no polling)

> [!WARNING]
> This requires Flutter client changes (`web_socket_channel` package). Only implement if you're already modifying the Flutter client for other reasons. The HTTP POST approach works fine for FYP demos.

**Estimated Impact**: Saves ~50-100ms per wingman request (TCP overhead elimination).

**Difficulty**: 🟡 Medium — requires both server and Flutter client changes

---

#### 

##### 

**Problem**: The `save_session` endpoint makes **2 separate LLM calls**: `extract_all_from_transcript()` AND `extract_highlights()`. The wingman already does extraction per chunk.

**Solution**: 
1. Merge highlight extraction into `extract_all_from_transcript()` (already partially done — the extraction prompt can return highlights too)
2. For `save_session`: Skip extraction if the session was a live wingman session (entities were already extracted per-chunk)

```python
# In save_session route
if session_type == "wingman":
    # Entities/events/tasks already extracted per-chunk during the live session
    # Only generate summary + save memory
    summary = await brain_svc.generate_summary(transcript)
else:
    # Batch upload — need full extraction
    extraction = await brain_svc.extract_all_from_transcript(transcript, graph_context)
    highlights = extraction.get("highlights", [])  # Include in unified extraction
```

**Estimated Impact**: Saves 1 LLM call (~200-500ms) per session save. Reduces Groq token usage by ~30%.

**Difficulty**: 🟢 Easy — conditional logic in route handler

---

##### 

**Problem**: First request after server start has a massive cold-start penalty (loading embedding model, establishing DB connections).

**Solution**: Warm everything up in the FastAPI `lifespan` event:

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # === Startup warm-up ===
    # 1. Load embedding model (blocks until ready)
    vector_svc.model  # Triggers lazy load
    
    # 2. Warm-up embedding model with a dummy encode
    _ = vector_svc.encode("warmup query")
    
    # 3. Pre-establish DB connection pool
    await database.connect()
    
    # 4. Verify LLM connectivity (fast ping)
    await brain_svc.aclient.chat.completions.create(
        model="llama-3.1-8b-instant",
        messages=[{"role": "user", "content": "ping"}],
        max_tokens=1
    )
    
    print("🚀 All services warmed up and ready")
    yield
    
    # === Shutdown ===
    await database.disconnect()

app = FastAPI(lifespan=lifespan)
```

**Estimated Impact**: First request latency: ~10s → ~200ms (eliminates cold-start).

**Difficulty**: 🟢 Easy — add to `main.py`

---

##### 

**Problem**: Creating a new `AsyncGroq` client per request (or even per service instance) wastes connections.

**Solution**: Use `httpx.AsyncClient` with connection pooling as the transport for all HTTP-based services:

```python
import httpx

# Shared across all LLM calls — reuses TCP connections
_http_pool = httpx.AsyncClient(
    limits=httpx.Limits(max_connections=20, max_keepalive_connections=10),
    timeout=httpx.Timeout(30.0, connect=5.0),
)

# Pass to Groq client
aclient = AsyncGroq(
    api_key=settings.GROQ_API_KEY,
    http_client=_http_pool,
)
```

**Estimated Impact**: Saves ~20-50ms per LLM call (TCP connection reuse).

**Difficulty**: 🟢 Easy — pass `http_client` parameter to existing client constructors

---

#### 

##### 

For an FYP, you need reliable, free hosting where your server stays warm enough for demos.

| Platform | Free Tier | Cold Start | RAM | Best For |
|----------|-----------|------------|-----|----------|
| **Render** | ✅ Persistent | 30-60s sleep | 512MB | Simple demos (with sleep tolerance) |
| **Koyeb** | ✅ Persistent | 60s sleep | 512MB | Small web services |
| **Railway** | ❌ $5/month | No sleep | 8GB | Best DX, production-ready |
| **Fly.io** | ❌ Trial only | No sleep | Configurable | Global edge deployment |

> [!IMPORTANT]
> **For an FYP demo, Render's free tier is sufficient** — but you need to hit your server with a health check every 14 minutes to prevent spin-down. Use [UptimeRobot](https://uptimerobot.com) (free, 5-min interval) or a cron job.

**Anti-cold-start trick** (for Render free tier):
```python
# In main.py — self-ping to prevent spin-down
import httpx
import asyncio

async def self_ping():
    """Ping own health endpoint every 10 minutes to prevent Render spin-down."""
    await asyncio.sleep(60)  # Wait for startup
    async with httpx.AsyncClient() as client:
        while True:
            try:
                await client.get(f"{settings.SELF_URL}/health", timeout=5)
            except Exception:
                pass
            await asyncio.sleep(600)  # Every 10 minutes
```

> [!TIP]
> **Railway at $5/month** is the strongest recommendation if your FYP budget allows it. No cold starts, 8GB RAM, excellent logs/debugging, and one-click Docker deployment.

---

##### 

**Problem**: Current Docker image is likely 3-4GB due to PyTorch + sentence-transformers.

**Solution**: Multi-stage build with ONNX Runtime instead of PyTorch.

```dockerfile
# Stage 1: Build dependencies
FROM python:3.11-slim AS builder
RUN pip install --no-cache-dir --target=/deps \
    fastapi uvicorn pydantic groq supabase \
    optimum[onnxruntime] transformers \
    networkx slowapi httpx python-dotenv \
    python-multipart redis cachetools litellm asyncpg

# Stage 2: Runtime
FROM python:3.11-slim
COPY --from=builder /deps /usr/local/lib/python3.11/site-packages
COPY ./app /app
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
```

**Image Size Impact**:
| Build | Size |
|-------|------|
| Current (PyTorch + sentence-transformers) | ~3.5GB |
| **Optimized (ONNX Runtime)** | **~800MB** |

**Why this matters**: Smaller images = faster deploys, faster cold starts, lower hosting costs.

**Difficulty**: 🟡 Medium — requires testing ONNX model compatibility

---

#### 

##### 

**Problem**: The wingman pipeline is: `Log → Fetch Contexts → LLM Advice → LLM Extraction → Persist`. The user waits for the entire pipeline.

**Solution**: Return advice to the user IMMEDIATELY after step 3, then do extraction + persistence in the background.

```python
@router.post("/v1/process_transcript_wingman")
async def process_wingman(req: WingmanRequest, user: VerifiedUser = Depends(get_verified_user)):
    # 1. Log + fetch contexts (parallel)
    log_task = asyncio.create_task(session_svc.log_message(...))
    graph_ctx, vector_ctx, entity_ctx = await asyncio.gather(
        graph_svc.find_context(user.user_id, req.transcript),
        vector_svc.search_memory(user.user_id, req.transcript),
        entity_svc.get_entity_context(user.user_id, req.target_entity_id),
    )
    
    # 2. Get advice (user-facing — must be fast)
    advice_result = await brain_svc.get_wingman_advice(...)
    
    # 3. IMMEDIATELY return advice to user
    # Background: extraction + persistence (user doesn't wait for this)
    asyncio.create_task(_background_persistence(user.user_id, req, advice_result))
    
    return {"advice": advice_result["answer"]}

async def _background_persistence(user_id, req, advice_result):
    """Fire-and-forget: extraction, entity persistence, graph update, memory save."""
    try:
        extraction = await brain_svc.extract_all_from_transcript(req.transcript, ...)
        await asyncio.gather(
            entity_svc.persist_extraction(user_id, extraction, req.session_id),
            graph_svc.save_graph(user_id),
            vector_svc.save_memory(user_id, req.transcript, req.session_id),
            # ... save events, tasks, highlights
        )
    except Exception as e:
        print(f"Background persistence failed: {e}")
```

**Estimated Impact**: **User-perceived latency drops by 60-70%** (from ~2-3s to ~500-800ms). The user sees advice almost immediately. Extraction happens invisibly in the background.

**Difficulty**: 🟡 Medium — need to handle edge cases (server shutdown during background work, error logging)

---

##### 

**Problem**: Every wingman turn triggers a full LLM extraction (entities, relations, events, tasks, conflicts). Most turns don't contain extractable data.

**Solution**: Only run extraction when the transcript is "interesting" enough:

```python
def _should_extract(transcript: str) -> bool:
    """Skip extraction for short, simple turns."""
    words = transcript.split()
    if len(words) < 15:
        return False  # Too short to contain entities
    
    # Check for entity-rich signals
    has_names = any(w[0].isupper() and w.isalpha() for w in words[1:])  # Capitalized words
    has_dates = any(kw in transcript.lower() for kw in ["tomorrow", "monday", "next week", "january"])
    has_tasks = any(kw in transcript.lower() for kw in ["need to", "should", "must", "have to", "remind me"])
    
    return has_names or has_dates or has_tasks
```

**Estimated Impact**: Skips ~50-70% of extraction calls → saves ~200-500ms per turn + reduces LLM token usage.

**Difficulty**: 🟢 Easy — add a guard clause before extraction

---

##### 

**Problem**: All requests travel to a single server region, adding network latency for distant users.

**Solution**: While you can't easily CDN-ify dynamic API calls, you CAN optimize static responses:

1. **Cache health checks**: Return `Cache-Control: public, max-age=60` on `/health`
2. **Use Cloudflare (free tier)** as a DNS proxy for DDoS protection + edge TLS termination
3. **Deploy server in the same region as Supabase** to minimize DB latency

| Optimization | Impact | Cost |
|-------------|--------|------|
| Cloudflare DNS proxy | -10-20ms (edge TLS) | Free |
| Co-locate server + DB | -20-50ms (network) | Free (choose same region) |
| Cache static responses | -varies | Free |

**Difficulty**: 🟢 Easy — DNS configuration

---

#### 

| # | Recommendation | Latency Impact | Difficulty | Cost | Priority |
|---|---------------|---------------|-----------|------|----------|
| 1 | LiteLLM Multi-Provider Gateway | Eliminates rate-limit failures | 🟢 Easy | Free | 🔴 Critical |
| 2 | Cerebras for Wingman | 2-4x faster responses | 🟢 Easy | Free | 🔴 Critical |
| 3 | Gemini Flash for Consultant | Better quality, no truncation | 🟢 Easy | Free | 🔴 Critical |
| 4 | e5-small + ONNX Runtime | 2-3x faster embeddings, 4x smaller image | 🟡 Medium | Free | 🟡 High |
| 6 | asyncpg Direct Connection | 5-10x faster DB operations | 🔴 Hard | Free | 🟡 High |
| 7 | Batch DB Operations | -200-400ms per wingman request | 🟢 Easy | Free | 🔴 Critical |
| 8 | pgvector HNSW Tuning | 5x faster vector search | 🟢 Easy | Free | 🟡 High |
| 9 | In-Memory TTL Cache | -100-200ms per request | 🟢 Easy | Free | 🟡 High |
| 10 | Upstash Redis | Zero-ops Redis | 🟢 Easy | Free | 🟢 Nice |
| 11 | SSE Streaming Headers | Eliminates buffering delay | 🟢 Easy | Free | 🟡 High |
| 13 | Eliminate Redundant LLM Calls | -200-500ms per save | 🟢 Easy | Free | 🟡 High |
| 14 | Startup Warm-Up | Eliminates cold start | 🟢 Easy | Free | 🔴 Critical |
| 15 | HTTP Connection Pooling | -20-50ms per LLM call | 🟢 Easy | Free | 🟡 High |
| 17 | Docker Image Optimization | Faster deploys, lower RAM | 🟡 Medium | Free | 🟡 High |
| 18 | Speculative Execution (Wingman) | **-60-70% user-perceived latency** | 🟡 Medium | Free | 🔴 Critical |
| 19 | Lazy Extraction Strategy | -200-500ms on 50%+ turns | 🟢 Easy | Free | 🟡 High |

---

#### 

> [!TIP]
> **Start with the free, easy wins** that give the largest latency reduction. Save the hard architectural changes for later.

**Phase 1 — Quick Wins (Week 1)** 🟢
1. ✅ Startup warm-up (Rec #14)
2. ✅ HTTP connection pooling (Rec #15)
3. ✅ Batch DB operations (Rec #7)
4. ✅ SSE streaming headers (Rec #11)
5. ✅ In-memory TTL cache (Rec #9)
6. ✅ Lazy extraction guard (Rec #19)
7. ✅ Eliminate redundant LLM calls (Rec #13)

**Phase 2 — Provider Optimization (Week 2)** 🟢
1. ✅ Set up Cerebras + Google AI Studio API keys
2. ✅ Install LiteLLM and configure fallback chains (Rec #1, #2, #3)
3. ✅ pgvector HNSW tuning (Rec #8)
4. ✅ Upstash Redis migration (Rec #10)

**Phase 3 — Architecture (Week 3)** 🟡
1. ✅ Speculative execution for wingman (Rec #18)
2. ✅ Upgrade to e5-small + ONNX Runtime (Rec #4)
3. ✅ Docker image optimization (Rec #17)

**Phase 4 — Advanced (Optional)** 🔴
1. ⬜ asyncpg direct connection (Rec #6)
2. ⬜ WebSocket upgrade for wingman (Rec #12)
3. ⬜ Cloud embedding API fallback (Rec #5)
4. ⬜ Cloudflare edge deployment (Rec #20)

---

## 11. Migration, Testing & Deployment

### 

1. **Pre-deployment**: Run gamification tables SQL (§14.8) in Supabase SQL Editor — additive, non-breaking
2. **Pre-deployment**: Verify HNSW index on `memory` table (§13.8) — run `CREATE INDEX IF NOT EXISTS`
3. **Pre-deployment**: Update `match_memory` RPC to filter `AND NOT is_archived` (§5.5)
4. **Deployment**: Deploy new server with blue-green strategy
5. **Post-deployment**: Switch Flutter client to new endpoint URL
6. **Post-deployment**: Monitor health endpoint + structured logs for 24h

### 

| Data | Migration Needed? | Notes |
|---|---|---|
| Sessions, session_logs | ❌ No | Schema is fully compatible |
| Consultant logs | ❌ No | Both `query/response` and `question/answer` columns exist |
| Entities, attributes, relations | ❌ No | Same schema |
| Knowledge graphs | ⚠️ Verify | `graph_data` JSON must match NetworkX `node_link_data()` format |
| Memory (vectors) | ⚠️ Verify | If switching embedding model (e5 vs MiniLM), vectors are **incompatible** — requires re-embedding ALL memories |
| Voice enrollments | ⚠️ Verify | ECAPA-TDNN 192-dim embeddings — verify model version matches |
| Gamification tables | ✅ New | No existing data, clean start for all users |

> [!WARNING]
> **Embedding model change is a breaking migration**: If you switch from `all-MiniLM-L6-v2` (384-dim) to `e5-small-v2` (384-dim), the dimensions match but the **vector space is different**. Old memories will return irrelevant search results. You must either (a) re-embed all existing memories, or (b) accept degraded search quality for old memories.

### 

```markdown
# Pre-Deployment
- [ ] All env vars set (§2) — including CEREBRAS_API_KEY, GEMINI_API_KEY
- [ ] SUPABASE_DB_URL obtained from Supabase Dashboard (use port 6543 pooler)
- [ ] REDIS_URL is the native Redis URL (rediss://...), NOT the REST URL
- [ ] Gamification SQL migration run (§14.8)
- [ ] HNSW index verified (§13.8)
- [ ] match_memory RPC updated with `AND NOT is_archived` filter (§5.5)
- [ ] Achievements seed data inserted (§14.7.2)
- [ ] Quest definitions seed data inserted (§14.7.4)

# Deployment Verification
- [ ] Health endpoint returns 200 with all checks green
- [ ] Health check validates at least ONE LiteLLM provider per model group
- [ ] Embedding model loads successfully (check startup logs)
- [ ] LLM ping succeeds (check startup warm-up logs)
- [ ] Rate limits tested (hit /v1/start_session 11 times, expect 429 on 11th)
- [ ] Redis connection verified (or in-memory fallback confirmed)

# Post-Deployment
- [ ] Flutter client updated with new server URL
- [ ] Flutter client: remove dead `processAudioChunk()` method from ApiService
- [ ] Flutter client: add Idempotency-Key header to mutating endpoints (§3.4)
- [ ] UptimeRobot configured (if Render free tier)
- [ ] Monitor structured logs for 24h — check for P95 latency regressions
```

---

### 

#### 

```
server/
├── tests/
│   ├── conftest.py                  # Shared fixtures: mock DB, mock Groq, test user
│   ├── test_brain_service.py        # LLM prompt building, retry logic, token estimation
│   ├── test_session_service.py      # Session CRUD, sentiment analysis, token tracking
│   ├── test_entity_service.py       # Fuzzy matching, deduplication, extraction persistence
│   ├── test_gamification_service.py # XP calculation, streak logic, quest assignment, anti-abuse
│   ├── test_vector_service.py       # Embedding generation, memory search/save
│   ├── test_routes_sessions.py      # Endpoint integration tests (start, wingman, end)
│   ├── test_routes_consultant.py    # Blocking + streaming consultant
│   ├── test_routes_gamification.py  # Profile + quest endpoints
│   ├── test_auth_guard.py           # JWT verification, debug mode bypass
│   ├── test_text_sanitizer.py       # Injection pattern detection
│   └── test_error_handling.py       # Standard error responses, degradation behavior
```

#### 

**Unit Tests** (mock DB + mock LLM):
- `BrainService`: Verify prompt building, retry count, token estimation accuracy
- `SessionService`: Inline sentiment analysis (word lists), token cost calculation
- `EntityService`: Fuzzy match threshold (0.85), entity type validation
- `GamificationService`: Level formula (`50 × N × (N-1)`), streak logic (yesterday/freeze/reset), anti-duplicate XP
- `TextSanitizer`: All injection patterns, 5000-char cap

**Integration Tests** (test Supabase project or Docker Postgres):
- Full wingman pipeline: start → process → end → verify session_logs + entities + memory
- Consultant pipeline: ask → verify consultant_logs + session_logs + memory
- Gamification integration: complete session → verify XP + streak + quest progress

**Load Tests** (k6 or locust):
```javascript
// k6 script skeleton — validate latency SLAs (§11.8)
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  vus: 10,
  duration: '60s',
  thresholds: {
    'http_req_duration{endpoint:wingman}': ['p(50)<800', 'p(95)<1500'],
    'http_req_duration{endpoint:consultant}': ['p(50)<3000', 'p(95)<6000'],
    'http_req_duration{endpoint:health}': ['p(50)<50', 'p(95)<200'],
  },
};
```

**LLM Output Tests** (golden-file tests):
- Feed known transcripts into `extract_all_from_transcript()`, verify JSON structure matches expected schema
- Feed edge cases: empty transcript, single word, 50K chars, non-English text
- Verify `WAITING` response for benign transcripts

#### 

```bash
# Unit tests
pytest tests/ -v --tb=short

# Integration tests (requires test DB)
APP_ENV=testing pytest tests/ -v -m integration

# Coverage report
pytest tests/ --cov=app --cov-report=html

# Load test (requires running server)
k6 run tests/load/wingman_load.js
```

#### 

```yaml
# .github/workflows/test.yml
name: Server Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.11' }
      - run: pip install -r server/requirements.txt
      - run: pip install pytest pytest-asyncio pytest-cov
      - run: cd server && pytest tests/ -v --tb=short
```

---

> **End of Core Blueprint** — This document covers every file, every DB interaction, every data flow, every API contract, technology optimization recommendations, error handling, observability, security hardening, reliability patterns, migration strategy, and testing approach for the Bubbles AI server.

---

## 12. Appendix

### 

1. [Project Context & Architecture](#1-project-context--architecture)
2. [Technology Stack & Dependencies](#2-technology-stack--dependencies)
3. [Proposed Directory Structure](#3-proposed-directory-structure)
4. [Infrastructure Layer](#4-infrastructure-layer)
5. [Service Layer — Detailed Specifications](#5-service-layer--detailed-specifications)
6. [Route Layer — API Endpoints](#6-route-layer--api-endpoints)
7. [Utility Layer](#7-utility-layer)
8. [Pydantic Request/Response Models](#8-pydantic-requestresponse-models)
9. [Database Table Interaction Matrix](#9-database-table-interaction-matrix)
10. [Complete Data Flow Diagrams](#10-complete-data-flow-diagrams)
11. [Cross-Cutting Concerns](#11-cross-cutting-concerns)
12. [Flutter Client API Contract](#12-flutter-client-api-contract)
13. [Technology Recommendations — Latency Reduction & FYP Optimization](#13-technology-recommendations--latency-reduction--fyp-optimization)
14. [Gamification & Quests System](#14-gamification--quests-system)
15. [Error Handling & Degradation](#15-error-handling--degradation)
16. [Observability & Debugging](#16-observability--debugging)
17. [Security Hardening](#17-security-hardening)
18. [Reliability Patterns](#18-reliability-patterns)
19. [Migration & Deployment Strategy](#19-migration--deployment-strategy)
20. [Testing Strategy](#20-testing-strategy)
21. [Intelligent Features & Advanced Endpoints](#14-intelligent-features--advanced-endpoints) *(§14, Addendum)*

---

### 

### 

> [!NOTE]
> This section consolidates all error handling patterns. See §8 for the standardized `ErrorResponse` Pydantic model, §11.6 for the graceful degradation matrix, and §11.7 for timeout configuration.

### 

### 

### 

---

## 13. Pre-Implementation Review Addendum

> Added: 2026-04-08 — Cross-referenced against live codebase, Flutter client, and environment configuration.

### 13.1 Additional Dependencies

| Package | Purpose | Replaces |
|---------|---------|----------|
| `pydantic-settings` | Type-safe config with `.env` loading | Manual `os.getenv()` + `python-dotenv` |
| `structlog` | Production-grade structured logging | Custom `StructuredLogger` class from §9.3 |
| `cachetools` | In-memory TTL caches | — (new, for §10.3.3) |
| `litellm` | Multi-provider LLM gateway | Direct `groq` client |

### 13.2 Non-Atomic Persistence Warning

The `persist_extraction` method (§6.1.3) inserts into `entities`, `entity_attributes`, `entity_relations`, `events`, `tasks`, `highlights` across 3-6 separate Supabase calls. The Supabase PostgREST client **does not support database transactions**.

- The documented rollback (DELETE on failure) is **best-effort**, not atomic.
- If the server crashes mid-persistence, orphaned entities/relations will remain.
- If you adopt `asyncpg` (§10.3.1), wrap multi-table writes in `async with conn.transaction()`.
- For the Supabase client path: accept this as a known limitation and add a periodic cleanup job.

### 13.3 API Version Header Middleware

Add this middleware in `main.py` to implement the versioning policy from §3.3:

```python
@app.middleware("http")
async def add_api_version(request: Request, call_next):
    client_version = request.headers.get("X-API-Version", "1")
    response = await call_next(request)
    response.headers["X-API-Version"] = "1"
    return response
```

### 13.4 Redis-Backed Rate Limiting

SlowAPI stores rate limits in memory by default. On Render/Railway free tier, every deploy or sleep cycle resets all counters. Use Redis-backed storage:

```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(
    key_func=get_remote_address,
    storage_uri=settings.REDIS_URL if settings.REDIS_URL else "memory://"
)
```

### 13.5 Health Check Updates for LiteLLM

After adopting LiteLLM (§10.1.1), update the `/health` endpoint to check provider availability:

```python
async def check_llm_health() -> dict:
    """Verify at least one provider per model group is reachable."""
    checks = {}
    for model_group in ["wingman", "consultant"]:
        try:
            response = await litellm.acompletion(
                model=model_group,
                messages=[{"role": "user", "content": "ping"}],
                max_tokens=1,
                timeout=3
            )
            checks[model_group] = {"status": "ok", "provider": response.model}
        except Exception as e:
            checks[model_group] = {"status": "degraded", "error": str(e)}
    return checks
```

### 13.6 Flutter Client Cleanup

These changes are needed in the Flutter `ApiService` but are NOT blocking for the server rewrite:

| Item | File | Action |
|------|------|--------|
| Remove `processAudioChunk()` | `api_service.dart:L161-187` | Delete — dead code, zero callers |
| Add `Idempotency-Key` header | `api_service.dart` — mutating calls | Add header generation per §3.4 |
| Handle `ErrorResponse` contract | `api_service.dart` — all error paths | Parse structured errors per §4.1.1 |
| Add new API methods | `api_service.dart` | `getDigest()`, `getCommunicationTrends()`, `getEntityTimeline()`, `getSessionReplay()` |
| Fix XP progress bar | `quests_screen.dart:L99-102` | Use `xp_current_level` and `xp_next_level` from server response instead of `(level-1) * 100` |

---

## 14. Intelligent Features & Advanced Endpoints

> Added: 2026-04-08 — Features identified from codebase cross-reference to maximize FYP impact.
> These features use EXISTING data and services in novel ways — no new ML models or external dependencies required.

---

### 14.1 Weekly Digest

**File**: Add to `routes/analytics.py`

**Context**: The Flutter `settings_provider.dart` already has a `pushWeeklyDigest` toggle (L22), but no server endpoint exists to generate the digest.

| Endpoint | Method | Auth | Rate Limit | Purpose |
|----------|--------|------|------------|---------|
| `/v1/digest/{user_id}` | GET | ✅ | 5/min | Aggregated activity summary |

**Query Params**: `?period=week` (default) or `?period=month`

**Response**:
```json
{
  "period": "2026-03-31 to 2026-04-06",
  "summary": "You had 8 conversations this week, mostly about work projects...",
  "stats": {
    "sessions_count": 8,
    "total_duration_minutes": 47,
    "consultant_questions": 5,
    "new_entities_discovered": 12,
    "tasks_created": 4,
    "tasks_completed": 2,
    "xp_earned": 340,
    "levels_gained": 1,
    "streak_days": 5,
    "quests_completed": 9
  },
  "top_entities": [
    {"name": "Sarah", "mentions": 14, "sentiment_avg": 0.7},
    {"name": "Project Alpha", "mentions": 8}
  ],
  "sentiment_trend": [
    {"date": "2026-03-31", "avg_score": 0.5},
    {"date": "2026-04-01", "avg_score": 0.6}
  ],
  "highlights": [
    {"type": "insight", "text": "You asked 5 consultant questions about team leadership"},
    {"type": "achievement", "text": "Unlocked 'Week Warrior' badge 🔥"}
  ],
  "pending_tasks": [
    {"title": "Send Q3 report", "due": "Tomorrow", "from_session": "Monday standup"}
  ]
}
```

**Server Logic**:
```python
async def generate_digest(user_id: str, period_days: int = 7) -> dict:
    cutoff = datetime.now(timezone.utc) - timedelta(days=period_days)
    cutoff_iso = cutoff.isoformat()
    
    # Parallel aggregation queries
    sessions, entities, xp, tasks, achievements = await asyncio.gather(
        asyncio.to_thread(lambda: db.table("sessions").select("id, created_at, summary, sentiment_score, mode")
            .eq("user_id", user_id).gte("created_at", cutoff_iso).execute()),
        asyncio.to_thread(lambda: db.table("entities").select("display_name, mention_count")
            .eq("user_id", user_id).gte("created_at", cutoff_iso).execute()),
        asyncio.to_thread(lambda: db.table("xp_transactions").select("amount, source_type")
            .eq("user_id", user_id).gte("created_at", cutoff_iso).execute()),
        asyncio.to_thread(lambda: db.table("tasks").select("title, status, due_date")
            .eq("user_id", user_id).eq("status", "pending").execute()),
        asyncio.to_thread(lambda: db.table("user_achievements").select("achievement_id, awarded_at")
            .eq("user_id", user_id).gte("awarded_at", cutoff_iso).execute()),
    )
    
    # Assemble digest from raw data — no LLM needed
    return {
        "period": f"{cutoff.strftime('%Y-%m-%d')} to {datetime.now(timezone.utc).strftime('%Y-%m-%d')}",
        "stats": {
            "sessions_count": len(sessions.data),
            "new_entities_discovered": len(entities.data),
            "xp_earned": sum(x["amount"] for x in xp.data),
            # ...
        },
        "top_entities": sorted(entities.data, key=lambda e: e["mention_count"], reverse=True)[:5],
        "pending_tasks": tasks.data[:10],
        # ...
    }
```

**DB Tables Read**: `sessions`, `entities`, `xp_transactions`, `tasks`, `user_achievements`, `consultant_logs`, `sentiment_logs`
**No new tables needed.**
**Difficulty**: 🟢 Easy — pure aggregation queries

---

### 14.2 Communication Improvement Tracker

**Context**: Bubbles calls itself a "conversation coaching" app, but it doesn't actually track whether users are *improving* over time. Session analytics exist per-session, but there's no cross-session trend.

#### New DB Table

```sql
CREATE TABLE IF NOT EXISTS user_communication_stats (
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    week_start      DATE NOT NULL,
    avg_talk_ratio  REAL,           -- % of time user talked (target: 40-60%)
    avg_sentiment   REAL,           -- average sentiment across sessions
    filler_rate     REAL,           -- filler words per 100 words (lower = better)
    avg_session_turns INTEGER,      -- engagement depth
    sessions_count  INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, week_start)
);
```

> [!IMPORTANT]
> Add this to the gamification SQL migration (§6.2.2) — run in Supabase SQL Editor alongside the gamification tables.

#### Endpoint

| Endpoint | Method | Auth | Rate Limit | Purpose |
|----------|--------|------|------------|---------|
| `/v1/communication_trends/{user_id}` | GET | ✅ | 10/min | Cross-session improvement tracking |

**Query Params**: `?weeks=8` (default, max 52)

**Response**:
```json
{
  "trends": [
    {
      "week": "2026-03-03",
      "talk_ratio": 0.72,
      "sentiment": 0.45,
      "filler_rate": 4.2,
      "sessions": 3
    },
    {
      "week": "2026-03-10",
      "talk_ratio": 0.58,
      "sentiment": 0.62,
      "filler_rate": 3.1,
      "sessions": 5
    }
  ],
  "improvements": [
    "🎯 Your talk-to-listen ratio improved from 72% to 58% — closer to the ideal 50/50",
    "💬 Filler word usage dropped 26% over the past month",
    "📈 Overall conversation sentiment trending upward"
  ],
  "coaching_insights": {
    "strongest_area": "sentiment",
    "weakest_area": "filler_rate",
    "recommendation": "Try pausing before responding to reduce filler words."
  }
}
```

#### Trigger: Compute Weekly Stats

**When**: As a background task after every `end_session` and `save_session`, compute the current week's stats and upsert.

```python
async def update_weekly_communication_stats(user_id: str, session_id: str):
    """Called after session ends. Aggregates this week's stats and upserts."""
    try:
        week_start = datetime.now(timezone.utc).date()
        week_start = week_start - timedelta(days=week_start.weekday())  # Monday
        week_iso = week_start.isoformat()
        
        # Get all sessions this week
        sessions = await asyncio.to_thread(
            lambda: db.table("session_analytics")
                .select("user_talk_pct, user_filler_count, total_turns")
                .eq("user_id", user_id)
                .gte("created_at", week_iso)
                .execute()
        )
        
        sentiments = await asyncio.to_thread(
            lambda: db.table("sentiment_logs")
                .select("sentiment_score")
                .eq("user_id", user_id)
                .gte("created_at", week_iso)
                .execute()
        )
        
        if not sessions.data:
            return
        
        # Aggregate
        avg_talk = sum(s.get("user_talk_pct", 0.5) for s in sessions.data) / len(sessions.data)
        avg_sentiment = sum(s.get("sentiment_score", 0) for s in sentiments.data) / max(len(sentiments.data), 1)
        total_fillers = sum(s.get("user_filler_count", 0) for s in sessions.data)
        total_turns = sum(s.get("total_turns", 0) for s in sessions.data)
        filler_rate = (total_fillers / max(total_turns, 1)) * 100  # per 100 turns
        
        await asyncio.to_thread(
            lambda: db.table("user_communication_stats")
                .upsert({
                    "user_id": user_id,
                    "week_start": week_iso,
                    "avg_talk_ratio": round(avg_talk, 3),
                    "avg_sentiment": round(avg_sentiment, 3),
                    "filler_rate": round(filler_rate, 2),
                    "avg_session_turns": total_turns // len(sessions.data),
                    "sessions_count": len(sessions.data),
                }).execute()
        )
    except Exception as e:
        print(f"Communication stats update failed: {e}")
```

**Integration point**: Add `fire_and_forget(update_weekly_communication_stats(user_id, session_id))` to `end_session` and `save_session` routes.

**DB Tables Written**: `user_communication_stats` (W)
**DB Tables Read**: `session_analytics` (R), `sentiment_logs` (R)
**Difficulty**: 🟡 Medium — new table, aggregation logic, trend calculation

---

### 14.3 Conversation Similarity Detection

**Context**: The vector memory exists but is only used reactively. This enhancement uses it *proactively* to alert the wingman when the user is revisiting a topic.

**Implementation** (modification to `process_transcript_wingman` pipeline, step 2):

```python
# Add alongside the existing context fetches (asyncio.gather):
similar_ctx = await vector_svc.search_memory(
    user_id, transcript, match_threshold=0.8, match_count=1
)

# If high-similarity match found, inject it into the wingman system prompt:
if similar_ctx and similar_ctx != "No relevant past memories.":
    context_block += (
        f"\n\n⚠️ CONTEXT: The user has discussed a very similar topic before:\n"
        f"{similar_ctx}\n"
        f"You can reference this tactfully if relevant, e.g., "
        f"'You mentioned something similar before about...'"
    )
```

**Response Enhancement** (optional, for Flutter UI):
```json
{
  "advice": "...",
  "similar_past_topic": true,
  "similar_topic_snippet": "3 days ago you discussed project timelines with Sarah..."
}
```

> [!TIP]
> The Flutter client can display a subtle toast or badge: "💡 You've discussed this topic before" — enhancing the sense that Bubbles truly remembers.

**No new tables, no new endpoints.** Pure logic enhancement.
**Difficulty**: 🟢 Easy — one additional `search_memory` call with a higher threshold

---

### 14.4 Adaptive Wingman from Feedback

**Context**: Users submit feedback (thumbs up/down per wingman response), stored in the `feedback` table. Currently this data is **never used** — it's a pure data sink.

**Implementation** (add method to `brain_service.py`):

```python
# brain_service.py
async def _get_user_feedback_hints(self, user_id: str) -> str:
    """Analyze recent feedback to adapt wingman advice style.
    Returns a prompt hint string or empty string if no data."""
    try:
        feedback = await asyncio.to_thread(
            lambda: db.table("feedback")
                .select("value, comment")
                .eq("user_id", user_id)
                .eq("feedback_type", "wingman")
                .order("created_at", desc=True)
                .limit(20)
                .execute()
        )
        if not feedback.data or len(feedback.data) < 5:
            return ""  # Not enough data to make judgment
        
        positive = sum(1 for f in feedback.data if (f.get("value") or 0) > 0)
        negative = sum(1 for f in feedback.data if (f.get("value") or 0) < 0)
        
        # Extract common negative feedback themes
        neg_comments = [f.get("comment", "") for f in feedback.data 
                       if (f.get("value") or 0) < 0 and f.get("comment")]
        
        if negative > positive * 2:
            return ("USER PREFERENCE NOTE: This user frequently marks advice as unhelpful. "
                    "Be more concise and actionable. Avoid generic platitudes. "
                    "Focus on specific, tactical suggestions.")
        elif positive > negative * 3:
            return ("USER PREFERENCE NOTE: This user responds well to your advice style. "
                    "Continue with detailed, warm, encouraging suggestions.")
        return ""
    except Exception:
        return ""  # Never block advice generation for feedback lookup
```

**Integration** (in `get_wingman_advice()`):
```python
# Before building the system prompt:
feedback_hint = await self._get_user_feedback_hints(user_id)
system_prompt = f"{base_system_prompt}\n\n{feedback_hint}" if feedback_hint else base_system_prompt
```

**Why this matters**: This closes the feedback loop. FYP evaluators will ask "what do you do with the feedback?" — this gives a concrete, intelligent answer.

**DB Tables Read**: `feedback` (R) — already cached via TTLCache (§10.3.3) recommended at 300s TTL
**No new tables or endpoints.**
**Difficulty**: 🟢 Easy — one DB read + prompt string modification

---

### 14.5 Entity Interaction Timeline

**File**: Add to `routes/entities.py`

| Endpoint | Method | Auth | Rate Limit | Purpose |
|----------|--------|------|------------|---------|
| `/v1/entity_timeline/{entity_id}` | GET | ✅ | 10/min | Chronological entity history |

**Query Params**: `?user_id=` (required, for ownership verification)

**Response**:
```json
{
  "entity_name": "Sarah",
  "entity_type": "person",
  "timeline": [
    {
      "date": "2026-03-15T10:30:00Z",
      "type": "discovery",
      "title": "First mentioned",
      "detail": "Appeared in session 'Team Meeting'"
    },
    {
      "date": "2026-03-20T14:00:00Z",
      "type": "attribute_update",
      "title": "New fact learned",
      "detail": "role = team lead"
    },
    {
      "date": "2026-04-01T09:15:00Z",
      "type": "task",
      "title": "Task created",
      "detail": "Send Q3 report to Sarah"
    },
    {
      "date": "2026-04-05T16:45:00Z",
      "type": "session",
      "title": "Conversation session",
      "detail": "Discussed project timeline — sentiment: positive"
    }
  ]
}
```

**Assembly Logic** (pure DB queries, no LLM):
```python
async def get_entity_timeline(user_id: str, entity_id: str) -> dict:
    # 1. Entity creation date
    entity = db.table("entities").select("*").eq("id", entity_id).eq("user_id", user_id).single().execute()
    
    # 2. Attribute change history
    attrs = db.table("entity_attributes").select("attribute_key, attribute_value, updated_at")
        .eq("entity_id", entity_id).order("updated_at").execute()
    
    # 3. Sessions where this entity was target
    sessions = db.table("sessions").select("id, title, created_at, sentiment_score, summary")
        .eq("user_id", user_id).eq("target_entity_id", entity_id).order("created_at").execute()
    
    # 4. Tasks mentioning this entity
    tasks = db.table("tasks").select("title, status, created_at")
        .eq("user_id", user_id).ilike("title", f"%{entity['display_name']}%").execute()
    
    # 5. Merge all into chronological timeline
    timeline = []
    timeline.append({"date": entity["created_at"], "type": "discovery", ...})
    for a in attrs.data:
        timeline.append({"date": a["updated_at"], "type": "attribute_update", ...})
    # ... merge and sort by date
    return {"entity_name": entity["display_name"], "timeline": sorted(timeline, key=lambda t: t["date"])}
```

**DB Tables Read**: `entities`, `entity_attributes`, `sessions`, `tasks`
**No new tables needed.**
**Difficulty**: 🟢 Easy — pure assembly from existing data

---

### 14.6 Session Replay with AI Annotations

**File**: Add to `routes/analytics.py`

| Endpoint | Method | Auth | Rate Limit | Purpose |
|----------|--------|------|------------|---------|
| `/v1/session_replay/{session_id}` | GET | ✅ | 5/min | Annotated session transcript |

**Response**:
```json
{
  "session_id": "uuid",
  "title": "Team Meeting",
  "duration_minutes": 12,
  "turns": [
    {
      "index": 1,
      "speaker": "user",
      "text": "Hey Sarah, about the Q3 report...",
      "sentiment_score": 0.6,
      "sentiment_label": "positive",
      "annotations": [
        {"type": "entity_mention", "value": "Sarah"},
        {"type": "topic_start", "value": "Q3 report"}
      ]
    },
    {
      "index": 5,
      "speaker": "user",
      "text": "Um, I was thinking, like, basically...",
      "sentiment_score": 0.3,
      "sentiment_label": "neutral",
      "annotations": [
        {"type": "filler_words", "count": 3, "words": ["um", "like", "basically"]},
        {"type": "coaching_note", "value": "High filler usage — sign of uncertainty. Try pausing instead."}
      ]
    },
    {
      "index": 8,
      "speaker": "llm",
      "text": "Try saying: 'I believe we should prioritize...'",
      "annotations": [
        {"type": "wingman_advice"}
      ]
    }
  ],
  "summary_stats": {
    "total_turns": 15,
    "user_turns": 8,
    "filler_count": 7,
    "avg_sentiment": 0.55,
    "entities_mentioned": ["Sarah", "Q3 Report", "Marketing Team"]
  }
}
```

**Server Logic** (post-processing, no LLM needed):
```python
async def get_session_replay(session_id: str, user_id: str) -> dict:
    # 1. Verify ownership
    session = db.table("sessions").select("*").eq("id", session_id).eq("user_id", user_id).single().execute()
    
    # 2. Fetch all turns
    logs = db.table("session_logs").select("*").eq("session_id", session_id)
        .order("turn_index").execute()
    
    # 3. Annotate each turn
    FILLER_WORDS = {"um", "uh", "like", "literally", "basically", "actually", "you know"}
    annotated_turns = []
    for log in logs.data:
        annotations = []
        text = log.get("content", "")
        words = text.lower().split()
        
        # Detect filler words
        fillers = [w for w in words if w in FILLER_WORDS]
        if len(fillers) >= 2:
            annotations.append({
                "type": "filler_words",
                "count": len(fillers),
                "words": fillers
            })
        
        # Detect entity mentions (from extracted entities)
        # ... match against user's entity names
        
        annotated_turns.append({
            "index": log["turn_index"],
            "speaker": log["role"],
            "text": text,
            "sentiment_score": log.get("sentiment_score"),
            "sentiment_label": log.get("sentiment_label"),
            "annotations": annotations,
        })
    
    return {"session_id": session_id, "turns": annotated_turns, ...}
```

**DB Tables Read**: `sessions`, `session_logs`, `entities`
**No new tables needed.**
**Difficulty**: 🟡 Medium — needs annotation logic, but uses only existing data

---

### 14.7 Smart Due Date Extraction

This is an enhancement to the existing `extract_all_from_transcript()` method (§6.1.1), NOT a new endpoint.

**Current**: Tasks are extracted with `priority` but `due_date` is always null.
**Enhanced**: The extraction prompt now includes temporal parsing instructions.

**Updated Extraction Prompt Addition**:
```
For each task, if a due date or deadline is mentioned, include it as an ISO date:
- "I need to do X by Friday" → due_date: "2026-04-11" (next Friday from today {current_date})
- "Need to send report tomorrow" → due_date: "2026-04-09" (tomorrow from today {current_date})
- "Should follow up next week" → due_date: "2026-04-14" (next Monday from today {current_date})
- No date mentioned → due_date: null

Today's date is: {datetime.now(timezone.utc).strftime('%Y-%m-%d')} ({datetime.now(timezone.utc).strftime('%A')})
```

**Implementation Change** (in `brain_service.py` → `extract_all_from_transcript()`):
```python
# Add current date context to the extraction system prompt
current_date = datetime.now(timezone.utc).strftime('%Y-%m-%d')
current_day = datetime.now(timezone.utc).strftime('%A')
system_prompt += f"\n\nToday is {current_day}, {current_date}. Resolve any relative dates (tomorrow, next week, Friday) to ISO format."
```

**Implementation Change** (in `entity_service.py` → `save_tasks()`):
```python
# Now populate the due_date column
for task in tasks:
    db.table("tasks").insert({
        "user_id": user_id,
        "title": task["title"],
        "status": "pending",
        "priority": task.get("priority", "medium"),
        "due_date": task.get("due_date"),  # NEW — now populated
        "source_session_id": session_id,
    }).execute()
```

**No new tables, no new endpoints.** Pure prompt engineering + DB column usage.
**Difficulty**: 🟢 Easy — prompt change + one field addition

---

### 14.8 Feature Summary & Build Integration

#### New Files

| File | Purpose |
|------|---------|
| *(None)* | All features integrate into existing route and service files |

#### Updated File List

| Existing File | New Additions |
|---|---|
| `routes/analytics.py` | `GET /digest/{user_id}`, `GET /communication_trends/{user_id}`, `GET /session_replay/{session_id}` |
| `routes/entities.py` | `GET /entity_timeline/{entity_id}` |
| `routes/sessions.py` | Briefing assembly in `start_session`, similarity detection in `process_wingman` |
| `services/brain_service.py` | `_get_user_feedback_hints()`, smart date context injection |
| `services/entity_service.py` | `due_date` population in `save_tasks()` |
| `services/gamification_service.py` | (no changes — `save_memory` triggers added to routes) |

#### New DB Table

| Table | SQL Location | Migration Notes |
|---|---|---|
| `user_communication_stats` | §14.2 | Add to gamification migration SQL; run alongside gamification tables |

#### Updated DB Interaction Matrix Additions

| DB Table | analytics.py (expanded) | entities.py (expanded) | sessions.py (expanded) |
|----------|:-----------:|:-------------:|:--------:|
| `user_communication_stats` | R/W | — | — |
| `feedback` | — | — | R (for adaptive wingman) |

#### Route-Gamification Integration Additions

| Existing Route | New Trigger | Quest Progress |
|---|---|---|
| `POST /process_transcript_wingman` | After memory save | `save_memory` +1 |
| `POST /end_session` | After summary memory save | `save_memory` +1 |
| `POST /save_session` | After memory save | `save_memory` +1 |
| `POST /ask_consultant` | After answer memory save | `save_memory` +1 |
| `POST /ask_consultant_stream` | After answer memory save | `save_memory` +1 |
| `POST /end_session` | After session analytics | Update `user_communication_stats` |
| `POST /save_session` | After session analytics | Update `user_communication_stats` |

---

> **Use this blueprint as the single source of truth for the rewrite.**
