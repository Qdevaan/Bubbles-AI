# Bubbles-AI: The Exhaustive Project Guidebook & Master Manual

> **Purpose:** This document is the definitive, exhaustive blueprint for the Final Year Project presentation of **Bubbles — Smarter AI Assistant**. It combines the 60-slide architecture deep dive, the presenter's verbatim newbie script, and the senior coaching guide into a single master document. If you need to understand every single technical and product detail of this system, this is your source of truth.

---

## PART 1: GLOBAL DESIGN & PROJECT IDENTITY

### The Engineering Split
This is a split-stack engineering build, carefully decoupled to scale independently:
- **Muhammad Ahmad (FA22-BCS-025):** Owns the Cross-platform Flutter Architecture, Caching (`BaseRepository`), and State Management (`Riverpod`), ensuring UI performance.
- **Attique Rehman (FA22-BCS-164):** Owns the distributed Async FastAPI Backend, LLM Router, Knowledge Graph (GraphRAG), and Voice Pipeline.

### Global Design Specification (The Aesthetics)
- **Theme:** "Editorial Calm" — Light, high-contrast, projector-proof.
- **Background:** Warm off-white `#FAF8F4` to reduce projector glare.
- **Primary Text:** Near-black `#1A1A1A`.
- **Accent Colors:** Calm blue-teal `#0E7C86` (brand) & amber `#F2A03D` (metrics/highlights).
- **Typography:** Manrope font (400 for body, 700/800 for headers).

### The Human Problem & Market Gap
We have built dozens of tools to fix our writing (Grammarly, spell-check). But **speaking has no undo button**. If you use the wrong tone or forget a detail while talking, there's no backspace. 
Current solutions fall into two buckets:
1. **Notetakers (Otter.ai, Fathom):** Summarize *after* the fact.
2. **General Assistants (Siri, ChatGPT):** Answer commands, but forget who you are between sessions.

**The Research Validation (3 Gaps Solved by Bubbles):**
1. No sub-second real-time coaching exists.
2. No longitudinal conversational memory across months of interactions exists.
3. Enterprise tools prioritize company surveillance over personal privacy.

---

## PART 2: THE PRODUCT EXPERIENCE (THE 4 MODES)

The entire product hangs on four verbs: **Listen → Whisper → Remember → Improve**. 
From the first launch, the `AppBootstrap` route decision tree gathers your persona via the **Performa Wizard** (industry, goals, tone) to dictate the exact system prompt.

### Mode 1: Live Wingman
Bubbles listens to the other speaker, processes what they say in milliseconds, and pushes a short, readable tip to your screen without breaking your flow. This is sub-second live transcript analysis.

### Mode 2: The Consultant
After a conversation, you can ask the AI questions. The Consultant streams the answer back instantly, drawing from your complete historical context. 

### Mode 3: Coaching & Analytics
Mode 3 aggregates performance data into actionable insights (`session_analytics_screen.dart`), showing whether your mistake counts are trending down, your sentiment is trending up, and analyzing your talk-time.

### Mode 4: Drills & Gamification
Every mistake becomes a flashcard powered by the **Leitner spaced-repetition algorithm** (`drills_screen.dart`). Completing these drills earns you XP, Quests, and Streaks, driving retention through gamified habit-building.

### Privacy First
All this data is deeply personal. Privacy is guaranteed via **Row-Level Security (RLS) in Postgres**. A user's JWT token can only access their specific rows at the database level.

---

## PART 3: IN-DEPTH FRONTEND ARCHITECTURE (FLUTTER)

The client is built for a strict 60 FPS experience with zero loading spinners, moving from UI down to the network layer.

### 1. The Dependency Injection Tree
Our Flutter app is wrapped in a strict `MultiProvider` tree. State flows in one direction: The `ConnectionService` feeds the `ApiService`, which is injected via `ProxyProvider` into the data **Repositories**, which are finally consumed by our UI **State Providers**.

### 2. The Repository Pattern & Caching
The UI layer is completely decoupled from the network. The UI asks a Provider, which asks a Repository (`HomeProvider` → `HomeRepository` → `API`). 
- **PersistentCacheService:** Backed by SQLite (`sqflite` + `SharedPreferences`), it stores data wrapped in a `CacheEntry` object with calculated TTLs (Time-to-Live).

### 3. Stale-While-Revalidate Algorithm
To ensure zero loading spinners on boot, every repository extends `BaseRepository`. When you open a screen, it yields stale SQLite data instantly, silently fetches fresh data via API, and then rebuilds the UI.
```dart
// Flow inside BaseRepository.fetch()
if (policy == CachePolicy.staleWhileRevalidate) {
  final cached = await localDb.get(key);
  if (cached != null) yield cached; // Render immediately
  final remote = await api.get(); 
  await localDb.save(key, remote);
  yield remote; // Rebuild UI invisibly
}
```

### 4. Boot State & Hydration
- **HydrationService:** Triggered on Auth/Boot (`lib/services/hydration_service.dart`), acting as a master orchestrator to run parallel, non-blocking cache refreshes across all repositories simultaneously.
- **BootStateService:** Synchronously mirrors the user's auth state in `SharedPreferences`. On launch, the `AppBootstrap` routes the user on frame 1, entirely bypassing the splash screen jitter.

### 5. Live Voice Architecture & Overlays
- **WakeWordService:** Uses **Picovoice Porcupine** to process audio locally on the edge, minimizing battery drain. Only upon "Hey Bubbles" does the `VoiceAssistantService` open a stream.
- **VoiceOverlay Stack:** Built outside the standard Flutter Navigator (`_VoiceOverlayWrapper`). It sits at the absolute root of the widget tree in a `Stack`, guaranteeing the microphone HUD remains persistent across screen transitions.

### 6. Subscriptions & Performance
- **Supabase Realtime WebSockets:** Pushes UI updates instantly without manual HTTP polling.
- **DevicePerfTier:** Calculates hardware capabilities at launch. Low-memory devices disable heavy `BackdropFilter` blurs and complex particle animations.
- **Authentic Typography:** Manrope fonts are bundled locally. `GoogleFonts.config.allowRuntimeFetching = false;` is set to prevent CDN network delays and layout shifts.
- **Cross-Platform:** Responsive `LayoutBuilder` allows the same codebase to run identically on mobile, desktop, and web.

---

## PART 4: IN-DEPTH BACKEND ARCHITECTURE (FASTAPI & ASYNC)

The backend is a highly optimized, asynchronous engine running Python 3.12 + FastAPI.

### 1. Server Topology & Strict Contracts
- **Topology:** Nginx/Caddy → Gunicorn Master → Uvicorn Async Workers → FastAPI. A single worker process can await hundreds of LLM calls without blocking the thread.
- **Pydantic v2:** Every incoming payload passes through strict Type Coercion schemas. Malformed data throws a 422 immediately and physically cannot reach the database controllers.

### 2. Wingman Request Flow & LLM Router
Flutter sends audio → `/v1/process_audio` → Groq STT → LLM Router → Streaming SSE Payload → Flutter.
- **LLM Routing Engine (`router.py`):** Dynamically orchestrates multi-provider AI. Speed-critical tasks (Wingman) go to Llama 3 on Groq LPUs. Deep reasoning tasks (Consultant) go to Google Gemini.

### 3. TaskChains & Circuit Breakers
- **TaskChains:** Granular control over temperature and tokens. 
```python
TaskChain(
    "wingman.json", 
    ("groq", "openrouter", "gemini"), 
    temperature=0.2, 
    max_tokens=600
)
```
- **Circuit Breaker:** If Groq times out, the `bubbles.core.circuit` transitions to an "Open" state, rerouting to OpenRouter. It shifts to "Half-Open" to test recovery, preventing cascading upstream failures.

### 4. Audio Processing
- **Diarization Engine:** The `speaker.py` script parses word-level timestamps from STT output and uses speaker enrollment profiles to strictly separate "User" vs "Other" tracks, ensuring the AI does not coach the user on their own sentences.

### 5. Background Workers & Resiliency (ARQ/Redis)
- **ARQ Queue Topology:** Heavy tasks (Graph extraction, gamification) are enqueued to Redis (`server/src/bubbles/workers/`) and executed asynchronously so HTTP responses aren't blocked.
- **Idempotent Design:** Every worker checks a unique transaction key before executing, guaranteeing a user is never rewarded twice due to a network retry.
- **Resiliency:** Outbound calls are wrapped in `Tenacity` (exponential backoff). Inbound calls are protected by a Redis-backed Token-Bucket rate limiter.

### 6. Database Concurrency
- **State:** In-RAM session dictionaries bridge stateless HTTP, constantly committing checkpoints to Postgres.
- **SQLAlchemy 2.0 & asyncpg:** Fully async connection. Uses `PgBouncer` for connection pooling.
- **Alembic Versioning:** 7 migration scripts allow reproducible database environments.

---

## PART 5: HYBRID MEMORY & GraphRAG

Standard AI assistants use pure vector databases, which match semantics, not facts (e.g., confusing "Bob" with "Rob"), leading to hallucinations. 

### Fused Querying
- **The Knowledge Graph:** The `extraction.py` module parses transcripts, identifies exact entities, and maps rigid relationships using Python's `NetworkX`, storing these edges securely in Postgres Link Tables.
- **GraphRAG:** When fetching memories, we pull thematic context from vector embeddings (`text-embedding-004`) AND absolute facts from an ego-graph search via SQL recursive joins.
- **Visual Explorer:** Users can physically explore their own memory map using `force_directed_graphview` in Flutter.
- **Privacy Barrier:** A hard Postgres Row-Level Security barrier strictly enforces the user `UUID`.

---

## PART 6: OBSERVABILITY, DEVOPS, & SCOPE

### Infra & Tracing
- **Tracing the Stack:** OpenTelemetry tracing creates a span for every request, visualized in Grafana, Prometheus, and Sentry.
- **Logging:** `structlog` produces strict JSON objects injected with the `session_id`.
- **Docker:** Multi-stage `Dockerfile` compiles isolated containers (`api-runtime` vs `worker-runtime`).
- **Keys:** Database primary keys use ULIDs (Universally Unique Lexicographically Sortable Identifiers) to eliminate distributed collisions.
- **CI/CD Quality Gates:** Pushed code must pass `mypy --strict`, `Ruff` linting, `pytest`, `flutter analyze`, and `flutter test`.

### Evaluation Metrics
- **Transcription (WER):** Target ≥85% accuracy.
- **Latency:** ~300ms glass-to-glass (Audio to UI).
- **Context Accuracy:** ~80% correctly grounded answers via GraphRAG.

### Future Scope
1. **Offline Fallback:** Small local LLMs & STT based on the current ONNX implementations.
2. **Multilingual (Urdu):** Expand parsing logic and prompts.
3. **Tone-Aware Coaching:** Real-time vocal prosody analysis (pitch and pacing).

---

## PART 7: THE PRESENTER's MASTER SCRIPT & COACHING GUIDE

### 1. The Opening Hook (Memorize Word-for-Word)
> *(Walk to the center. Plant your feet. Do not look at the screen. Wait 2 seconds before speaking.)*
> 
> **You:** "Have you ever walked out of a high-stakes job interview, a salary negotiation, or a crucial client meeting... and ten minutes later, the absolute *perfect* response finally popped into your head?" 
> 
> *(Pause for 1 second. Smile slightly.)* 
> 
> **You:** "We all have. As an industry, we have built an entire arsenal of tools to fix our writing—spell check, Grammarly, autocorrect. But speech happens in real-time. There is no 'backspace' for a live conversation. If you freeze, or if you use the wrong tone, that moment is gone. Until today.
> 
> Good morning, my name is `[Your Name]`, and today I am proud to present **Bubbles**. Bubbles is an AI conversation co-pilot. It listens while you speak, whispers exactly what you need to say next in real-time, and remembers the details so you never drop the ball. Let me show you how we solved the timing problem of human communication."

### 2. Sounding Like a Senior Architect (The Tech Script)
When presenting technical features, speak deliberately and with authority:
- **On Caching:** "On the frontend, our biggest enemy was loading screens. We implemented a custom `Stale-While-Revalidate` algorithm. The app instantly renders cached SQLite data, completely eliminating loading spinners, while silently fetching fresh data in the background."
- **On The LLM Router:** "Different tasks require different models. For deep questions, we use Google Gemini. But for the Live Wingman—where speed is everything—the router bypasses Gemini and sends audio to Llama 3 on Groq's LPU hardware. This dropped our inference time from 5 seconds down to an incredible 300 milliseconds."
- **On GraphRAG:** "Standard vectors hallucinate facts. If you ask about Bob, it might return Rob. We engineered a Knowledge Graph. As you speak, we extract hard entities and relationships as edges in Postgres. We fuse semantic vectors with these hard facts to create a hallucination-proof memory system."

### 3. Coaching: Mindset, Choreography & Body Language
- **Don't Read the Slides:** Look at the evaluators. Use the "Story" voice for the problem, and a crisp "Tech" voice for architecture.
- **The Hand-Off:** Do not say "Now [Partner] will speak." Instead, say: *"That is how we guarantee a fluid 60fps client experience. But a fast client is useless without a powerful brain. I'll hand it over to Attique to show you how our async backend handles the heavy lifting."*
- **The "300ms" Punch:** Speed is your killer feature. Say *"Five seconds of dead air is an eternity in a conversation."* Snap your fingers. *"We brought it down to 300 milliseconds."*

### 4. Defending the Q&A
- **Why Flutter instead of Native/React Native?** *"We evaluated React Native, but the JS bridge introduced too much latency for real-time audio streams. Flutter’s compiled Dart code gave us near-native performance while allowing deployment to six platforms."*
- **How do you handle privacy?** *"We don't just rely on application logic. We enforce it at the database level using Postgres Row-Level Security. A user's token is mathematically restricted to fetching only their own rows."*
- **What if the internet goes down?** *"Currently, state-of-the-art LLMs require cloud compute. But our architecture is prepared. We already run ONNX embeddings locally, and our future scope includes quantized on-device STT and LLMs for offline fallback."*
- **Handling Aggressive Evaluators:** Do not get defensive. Say: *"I apologize, I might not have explained the [feature] clearly enough. Let me clarify..."* Never lie or guess. If you don't know, state what you *do* know.

### 5. Demo Contingency Plan (The Danger Zone)
1. Tell them exactly what you are going to do before doing it.
2. Ensure the laptop speaker doesn't feed into the microphone (ruins diarization).
3. **If the Network Fails:** DO NOT PANIC. Do not debug on stage. Say: *"It appears the university Wi-Fi is blocking our WebSocket ports. As engineers, we plan for failure. Let me switch to our high-res fallbacks to show you exactly how this looks."* Open `Documentation/Screenshots/`.

---
*End of Guidebook*
