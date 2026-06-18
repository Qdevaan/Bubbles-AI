# Bubbles-AI — The Complete 60-Slide Master Build Sheet & Presenter Script

> **Purpose:** This document is the definitive, exhaustive blueprint for the Final Year Project presentation of **Bubbles — Smarter AI Assistant**. It scales the presentation up to 60 meticulous slides. Per recent feedback, **Sections 3 and 4 (Frontend and Backend Architecture) have been massively deepened** to rigorously detail the data flows, design patterns, network protocols, and exact class lifecycles used in the system.

---

## GLOBAL DESIGN SPECIFICATION
- **Theme:** "Editorial Calm" — Light, high-contrast, projector-proof.
- **Background:** Warm off-white `#FAF8F4` to reduce projector glare.
- **Primary Text:** Near-black `#1A1A1A`.
- **Accent Colors:** Calm blue-teal `#0E7C86` (brand) & amber `#F2A03D` (metrics/highlights).
- **Typography:** Manrope font (400 for body, 700/800 for headers).
- **Rule of Thumb:** Max 5 bullets or 1 diagram per slide. Let the script carry the detail.
- **Footer:** "Bubbles · FYP 2022–2026 · COMSATS Lahore | Slide {N}"

---

# SECTION 1: THE INCEPTION (Slides 1–6)

## Slide 1: Title Slide
**Visuals:** Centered Bubbles logo (`bubbles-ai-qr.png`), COMSATS University logo.
**Text:** 
- **Bubbles**
- Your AI conversation co-pilot — live coaching while you talk.
- Muhammad Ahmad (FA22-BCS-025) & Attique Rehman (FA22-BCS-164)
**Script:** "Good morning. We are here to present Bubbles. Bubbles is an AI that listens while you speak, whispers what to say next, and remembers everything so you can ask about it later. Welcome to our Final Year Project evaluation."

## Slide 2: The Engineering Split
**Visuals:** Two-column split with team avatars.
**Text:** 
- **Muhammad Ahmad:** Cross-platform Flutter Architecture, Caching (`BaseRepository`), State Management (`Riverpod`).
- **Attique Rehman:** Async FastAPI Backend, LLM Router, Knowledge Graph, Voice Pipeline.
**Script:** "This is a split-stack engineering build. Muhammad Ahmad owns the Flutter client, local caching, and UI performance. Attique Rehman owns the distributed async Python backend, the AI router, and our memory graph. This clean boundary allows us to scale independently."

## Slide 3: What Exactly is Bubbles?
**Visuals:** Three minimalist icons (Ear, Speech Bubble, Brain).
**Text:** 
- Listen (In-context transcription).
- Whisper (Live conversational nudges).
- Remember (Longitudinal memory graph).
**Script:** "Think of a time you were in an interview or negotiation. You froze. You lost your train of thought. Bubbles fixes the timing problem. It gives you the perfect words exactly when you need them—during the conversation, not after."

## Slide 4: The Human Problem: Speaking vs Writing
**Visuals:** Split screen: Left (typo in Word with red squiggly line) vs Right (person making a verbal mistake with zero feedback).
**Text:** 
- Writing has autocorrect, Grammarly, and backspace.
- **Speaking has no undo button.**
**Script:** "We have built dozens of tools to fix our writing—Grammarly, spell-check. But speech happens in real-time. If you use the wrong tone or forget a detail while talking, there's no backspace. That asymmetry is the core problem we are solving."

## Slide 5: The Market Gap
**Visuals:** "Meeting Notetakers" (Otter.ai, Fathom) vs "General Assistants" (Siri, ChatGPT).
**Text:** 
- **Notetakers:** Summarize *after* the fact.
- **Assistants:** Answer commands, but forget context.
**Script:** "Current solutions fall into two buckets. Notetakers like Otter summarize a meeting after it ends. General assistants like ChatGPT answer questions but forget who you are between sessions. Neither is a live, continuous coach."

## Slide 6: The Research Validation
**Visuals:** Three numbered gaps with red "X" marks.
**Text:** 
1. No real-time coaching.
2. No long-term conversational memory.
3. Not privacy-first.
**Script:** "Our literature review identified three explicit gaps in the current landscape: no tools provide sub-second real-time coaching, no tools map conversational memory across months of interactions, and enterprise tools prioritize company surveillance over personal privacy."

---

# SECTION 2: THE PRODUCT EXPERIENCE (Slides 7–13)

## Slide 7: The Core Loop
**Visuals:** Four horizontal bubbles forming a cycle.
**Text:** Listen → Whisper → Remember → Improve.
**Script:** "Our entire product hangs on four verbs. We listen to the live audio, whisper the optimal response, remember the extracted entities, and use your mistakes to help you improve your speaking skills."

## Slide 8: The Onboarding Flow
**Visuals:** Mockup of `onboarding.png` and `performa-wizard.png`.
**Text:** 
- Fluid UI: `AppBootstrap` route decision tree.
- Performa Wizard: Persona, Goals, Tone.
**Script:** "From the first launch, the app gathers your persona via the Performa Wizard—your industry, goals, and tone. This strict data payload dictates the exact system prompt the AI will use to coach you."

## Slide 9: Mode 1 - Live Wingman
**Visuals:** Mockup of `new-session_1.png` showing live tips.
**Text:** 
- **Live Wingman**
- Sub-second live transcript analysis.
**Script:** "Mode 1 is the Live Wingman. It listens to the other speaker, processes what they say in milliseconds, and pushes a short, readable tip to your screen without breaking your flow."

## Slide 10: Mode 2 - The Consultant
**Visuals:** Mockup of `consultant_1.png`.
**Text:** 
- **Consultant Mode**
- Streaming Q&A against historical conversations.
**Script:** "Mode 2 is the Consultant. After a conversation, you can ask the AI questions. The Consultant streams the answer back instantly, drawing from your complete historical context."

## Slide 11: Mode 3 - Coaching & Analytics
**Visuals:** Mockup of `session_analytics_screen.dart` / `insights.png`.
**Text:** 
- Aggregate Metrics: Mistakes ↓, Sentiment ↑, Talk-time.
**Script:** "Mode 3 is post-session analytics. We aggregate your performance data into actionable insights, showing whether your mistake counts are trending down and your sentiment is trending up."

## Slide 12: Mode 4 - Drills & Gamification
**Visuals:** Mockups of `game-center.png` and `drills_screen.dart`.
**Text:** 
- **Leitner System** spaced repetition.
- Quests, Streaks, XP.
**Script:** "Mode 4 is active practice. Every mistake becomes a flashcard powered by the Leitner spaced-repetition algorithm. Completing these drills earns you XP, driving retention through gamified habit-building."

## Slide 13: Privacy First
**Visuals:** A shield icon over a lock.
**Text:** 
- Your data stays yours.
- Enforced via **Postgres Row-Level Security**.
**Script:** "All of this data is deeply personal. Privacy is guaranteed via Row-Level Security in Postgres. A user's JWT token can only access their specific rows at the database level."

---

# SECTION 3: IN-DEPTH FRONTEND ARCHITECTURE (Slides 14–26)

## Slide 14: Section Divider - Frontend Architecture
**Visuals:** Full-bleed teal background (`#0E7C86`).
**Text:** **Deep Dive: The Flutter Client Architecture**
**Script:** "We will now break down the structural architecture of the mobile client, moving from UI down to the network layer."

## Slide 15: The Dependency Injection Tree
**Visuals:** A tree diagram showing `MultiProvider` injecting `ConnectionService` → `ApiService` → `Repositories` → `State Providers`.
**Text:** 
- Strictly layered injection (`main.dart`).
- `ProxyProvider` for cascading dependencies.
**Script:** "Our entire Flutter app is wrapped in a strict MultiProvider tree. State flows in one direction. The `ConnectionService` feeds the `ApiService`, which is injected via `ProxyProvider` into the data Repositories, which are finally consumed by our UI State Providers."

## Slide 16: The Repository Pattern
**Visuals:** Flowchart: `UI` → `HomeProvider` → `HomeRepository` → `API`.
**Text:** 
- Abstracts all network and caching logic.
- UI never touches the API directly.
**Script:** "The UI layer is completely decoupled from the network. If the UI needs data, it asks a Provider, which asks a Repository. The Repository alone decides whether to fetch from the local SQLite cache or execute a network call."

## Slide 17: Caching Layer: `PersistentCacheService`
**Visuals:** Diagram showing SQLite DB mapping to `CacheEntry` models.
**Text:** 
- `sqflite` + `SharedPreferences`.
- Structured `CacheEntry` with TTLs (Time-to-Live).
**Script:** "Our primary persistence layer is the `PersistentCacheService`, backed by SQLite. It doesn't just store raw JSON; it wraps data in a `CacheEntry` object with a calculated Time-to-Live (TTL), invalidating data mathematically when it expires."

## Slide 18: Stale-While-Revalidate Algorithm
**Visuals:** Sequence diagram: Flutter asks for data → Cache returns stale data instantly (Frame 1) → Network fetch begins → UI updates with fresh data (Frame N).
**Text:** 
- Immediate UI rendering via cached payloads.
- Background mutation via `BaseRepository`.
**Code Snippet:**
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
**Script:** "To ensure zero loading spinners on boot, every repository extends `BaseRepository` to implement Stale-While-Revalidate. When you open a screen, it yields the stale SQLite data instantly to render the UI, silently fetches the fresh data via API, and then seamlessly rebuilds the UI."

## Slide 19: The Hydration Service
**Visuals:** Gear icon showing multiple Repositories syncing.
**Text:** 
- `HydrationService` (`lib/services/hydration_service.dart`).
- Triggered on Auth/Boot.
**Script:** "Managing all these caches manually would cause race conditions. The `HydrationService` acts as a master orchestrator. Upon user login or a warm boot, it triggers parallel, non-blocking refresh commands across all repositories simultaneously."

## Slide 20: Boot State Mirroring (0ms Routing)
**Visuals:** Diagram of `SharedPreferences` instantly resolving the `/` route in `AppBootstrap`.
**Text:** 
- `BootStateService.instance.init()`.
- Synchronous UI routing on frame 1.
**Script:** "Waiting for async database checks at launch causes splash screen jitter. We built a `BootStateService` that maintains a synchronous mirror of the user's auth state in `SharedPreferences`. On launch, the `AppBootstrap` widget routes the user on frame 1, entirely bypassing the splash screen."

## Slide 21: Realtime Subscriptions
**Visuals:** WebSocket icon syncing Supabase to Flutter UI.
**Text:** 
- `supabase_flutter` realtime channel listeners.
- Pushes UI updates without manual polling.
**Script:** "For live updates—like when a background worker finishes processing a session—we do not use HTTP polling. We subscribe to Supabase Realtime WebSocket channels. When a row changes in the cloud, the Flutter UI reactively rebuilds."

## Slide 22: Live Voice Architecture
**Visuals:** Device Microphone → `WakeWordService` (Porcupine) → `VoiceAssistantService`.
**Text:** 
- On-device edge processing for "Hey Bubbles".
- Minimizes battery drain and privacy risk.
**Script:** "Our live audio capture is highly optimized. We do not stream audio 24/7. The `WakeWordService` uses Picovoice Porcupine to process audio locally on the edge. Only when the wake word is detected does the `VoiceAssistantService` open a stream to the backend."

## Slide 23: Global Voice Overlay `Stack`
**Visuals:** Flutter Widget Tree: `MaterialApp` → `_VoiceOverlayWrapper` (Stack) → `Navigator` + `VoiceOverlay`.
**Text:** 
- Decoupled from the routing navigator.
- Persistent across all screen transitions.
**Script:** "Because a conversation shouldn't be interrupted when you tap a button, we built the `VoiceOverlay` outside the standard Flutter Navigator. It sits at the absolute root of the widget tree in a `Stack`, guaranteeing the microphone HUD remains persistent no matter what screen you open."

## Slide 24: Device Performance Tiering
**Visuals:** Graphic of a speedometer.
**Text:** 
- `DevicePerfTier.instance.detect()`.
- Dynamic UI degradation (blurs, animations).
**Script:** "Android hardware varies wildly. During `main.dart` initialization, we calculate a `DevicePerfTier`. If we detect a low-memory device, the app automatically disables heavy `BackdropFilter` blurs and complex particle animations to maintain a strict 60 FPS."

## Slide 25: Authentic Typography & UI
**Visuals:** Code snippet showing Google Fonts disabled fetching.
**Text:** 
- Offline-first typography.
**Code Snippet:**
```dart
// Prevent CDN network delays
GoogleFonts.config.allowRuntimeFetching = false;
```
**Script:** "Even typography is engineered for performance. We bundled the entire Manrope font family into our assets and explicitly disabled runtime fetching. Text renders instantly even on airplane mode, eliminating layout shifts."

## Slide 26: Cross-Platform Unification
**Visuals:** Flutter icons for iOS, Android, Linux, Web.
**Text:** 
- Responsive Layout Builders.
- One codebase, identical behavior.
**Script:** "Because of our strict separation of state and UI, we write UI once. Using Flutter's `LayoutBuilder`, screens fluidly adapt from a mobile viewport to a multi-column desktop layout without modifying the underlying business logic."

---

# SECTION 4: IN-DEPTH BACKEND ARCHITECTURE (Slides 27–41)

## Slide 27: Section Divider - Backend Architecture
**Visuals:** Full-bleed amber background (`#F2A03D`).
**Text:** **Deep Dive: FastAPI Brain & Async Orchestration**
**Script:** "Now we transition to the backend. We will cover the specific data flows, the LLM routing logic, and the asynchronous worker topology."

## Slide 28: Server Topology
**Visuals:** Diagram: Nginx/Caddy → Gunicorn Master → Uvicorn Async Workers → FastAPI App.
**Text:** 
- Python 3.12 + FastAPI.
- 100% Async I/O Event Loop.
**Script:** "Our API runs on an ASGI server topology. Gunicorn manages multiple Uvicorn worker processes. Because FastAPI uses Python's `asyncio` event loop, a single worker process can concurrently await hundreds of LLM calls or database queries without blocking the thread."

## Slide 29: Request Lifecycle & Strict Contracts
**Visuals:** User Payload → FastAPI Middleware → Pydantic Schema Validation → Controller.
**Text:** 
- `Pydantic v2` Type Coercion.
- Zero malformed data ingress.
**Script:** "Every incoming payload must pass through Pydantic v2 models. If a client sends a string instead of an integer for an ID, Pydantic throws a strict 422 Unprocessable Entity error immediately. Malformed data is physically incapable of reaching our database controllers."

## Slide 30: Wingman Request Flow
**Visuals:** Sequence Diagram: Flutter (Audio) → `/v1/process_audio` → Groq STT → LLM Router → SSE Payload → Flutter.
**Text:** 
- End-to-end processing pipeline.
- Streaming payloads via Server-Sent Events (SSE).
**Script:** "Let's trace a Wingman request: Flutter sends audio. The `/process_audio` endpoint awaits the Groq Whisper STT. The resulting text is passed to the LLM Router. The advice is then streamed back to Flutter via Server-Sent Events, achieving sub-300ms latency."

## Slide 31: The LLM Routing Engine
**Visuals:** Router box deciding between Gemini, Cerebras, and Groq.
**Text:** 
- `server/src/bubbles/ai/router.py`.
- Dynamic multi-provider orchestration.
**Script:** "We don't rely on a monolithic AI provider. We built an `LLMRouter` that intelligently assigns tasks. This architecture ensures we get the speed of Llama 3 on Groq LPUs for live advice, while retaining the deep reasoning of Gemini for Consultant queries."

## Slide 32: TaskChains
**Visuals:** Code snippet showing a tuple of task fallback definitions.
**Text:** 
- Granular control over temperature and max tokens per task.
**Code Snippet:**
```python
TaskChain(
    "wingman.json", 
    ("groq", "openrouter", "gemini"), 
    temperature=0.2, 
    max_tokens=600
)
```
**Script:** "Each endpoint requests a specific `TaskChain`. As shown in our exact codebase, the `wingman.json` task is configured to prioritize Groq first, with a low temperature of 0.2 to prevent hallucinations, strictly capped at 600 tokens for speed."

## Slide 33: Circuit Breaker State Machine
**Visuals:** Diagram showing Circuit Breaker states: Closed (Green) → Open (Red) → Half-Open (Yellow).
**Text:** 
- Distributed fault tolerance (`bubbles.core.circuit`).
- Prevents cascading upstream failures.
**Script:** "If the Groq API times out, our Circuit Breaker transitions to an 'Open' state, instantly skipping Groq and hitting OpenRouter instead for the next 30 seconds. In the background, it shifts to 'Half-Open' to test recovery, preventing our API from locking up due to upstream vendor outages."

## Slide 34: Diarization Engine
**Visuals:** Two overlapping waveforms being split into two distinct tracks.
**Text:** 
- `speaker.py` Word-Level Timestamp Parsing.
- Isolating "User" vs "Other".
**Script:** "A massive challenge is Diarization. When two people speak into one mic, the AI must not advise the user on their own sentences. We parse precise word-level timestamps from the STT output, utilizing speaker enrollment profiles to strictly separate the dialogue tracks."

## Slide 35: Background Queue Topology (ARQ)
**Visuals:** Diagram: Main FastAPI Thread (Push to Queue) → Redis → ARQ Worker Process (Pop from Queue).
**Text:** 
- `server/src/bubbles/workers/`.
- Decoupling heavy computation from HTTP responses.
**Script:** "We cannot afford to run heavy computations on the HTTP request thread. Tasks like Knowledge Graph extraction, generating embeddings, and updating gamification stats are enqueued to a Redis instance and executed by standalone asynchronous ARQ worker processes."

## Slide 36: Idempotent Worker Design
**Visuals:** Flowchart: Check DB for Job ID → Execute if Missing → Skip if Present.
**Text:** 
- Safe, resilient retry logic.
- Prevents duplicate database mutations.
**Script:** "In distributed systems, workers can crash and retry jobs. We designed every ARQ worker to be idempotent. Before a job executes—say, granting 50 XP for a session—it checks a unique transaction key. This guarantees a user is never rewarded twice due to a network retry."

## Slide 37: In-RAM Session State
**Visuals:** Fast RAM icon flushing to a persistent Postgres icon.
**Text:** 
- Bridging stateless HTTP.
- Fast local state, durable remote persistence.
**Script:** "Because HTTP is stateless, the AI must remember the immediate context of a live conversation between requests. We maintain an in-RAM session state dictionary for instant context retrieval, continuously committing checkpoints to Postgres for durability."

## Slide 38: Outbound Resiliency
**Visuals:** Shield icon wrapping a network request.
**Text:** 
- `Tenacity` Python decorators.
- Exponential backoff.
**Script:** "Network calls to AI providers are inherently unreliable. We wrap all outbound calls using the `Tenacity` library. If a transient error occurs, the code automatically retries with an exponential backoff curve, absorbing network blips without the user ever noticing."

## Slide 39: Inbound Rate Limiting
**Visuals:** A leaky bucket algorithm graphic.
**Text:** 
- Redis-backed Token-Bucket algorithm.
- Preventing API abuse.
**Script:** "To protect our infrastructure from DDoS attacks or accidental infinite loops from the client, we implemented a Redis-backed token-bucket rate limiter. Every endpoint strictly limits the requests-per-minute per user."

## Slide 40: Database Concurrency
**Visuals:** Postgres icon with multiple incoming arrows.
**Text:** 
- `SQLAlchemy` 2.0 with `asyncpg` driver.
- Connection pooling via `PgBouncer`.
**Script:** "Our connection to Postgres is fully async using `asyncpg`. To handle hundreds of concurrent workers, we utilize `PgBouncer` to pool database connections, drastically reducing connection overhead and latency on DB writes."

## Slide 41: Alembic Schema Versioning
**Visuals:** Terminal showing migration scripts (`version_001`, `version_002`).
**Text:** 
- 7 versioned schema migrations.
- Instantly reproducible database environments.
**Script:** "Our database schema is treated as code. We use `Alembic` to track structural changes. With 7 current migration scripts, we can spin up an exact replica of our production database for testing, or safely rollback schema changes without data loss."

---

# SECTION 5: HYBRID MEMORY & GraphRAG (Slides 42–47)

## Slide 42: Section Divider - Memory
**Visuals:** Full-bleed teal background.
**Text:** **The Hybrid Memory Engine.**
**Script:** "Let's explore the data structures that allow Bubbles to remember your life."

## Slide 43: The Hallucination Problem in Pure RAG
**Visuals:** Graphic showing "Bob" matching "Rob" incorrectly in vector space.
**Text:** 
- Standard vectors match *semantics*, not *facts*.
**Script:** "Standard AI assistants use pure vector databases. Vectors are excellent for matching themes, but terrible at facts. If you ask about 'Bob', it might return 'Rob' because their semantic distance is close. This is why AI hallucinates."

## Slide 44: The Knowledge Graph (`NetworkX`)
**Visuals:** Network diagram showing Nodes (Person, Task) and Edges (Knows, Assigned-to).
**Text:** 
- `server/src/bubbles/ai/extraction.py`.
- Entity Extraction mapping to Postgres Link Tables.
**Script:** "We fixed this by generating a concrete Knowledge Graph. Our `extraction.py` module parses transcripts, identifies exact entities, and maps rigid relationships between them using Python's `NetworkX`, storing these edges securely in Postgres."

## Slide 45: Fused Querying (GraphRAG)
**Visuals:** Vector DB + Postgres Graph DB → Fused Context → LLM.
**Text:** 
- **Semantic Vector Recall:** `text-embedding-004`.
- **Factual Ego-Graph Recall:** SQL recursive joins.
**Script:** "When the Consultant fetches memories, we execute a fused query. We pull thematic context from the vector embeddings, and we pull absolute facts from an ego-graph search around the entities mentioned. The AI receives a combined, hallucination-proof context payload."

## Slide 46: Privacy Enforced by Postgres (RLS)
**Visuals:** A lock over the specific row of a user.
**Text:** 
- Row-Level Security (RLS).
- Hard database barrier per user `UUID`.
**Script:** "Memory is inherently private. We leverage Supabase's Row-Level Security. Every single query passes through a Postgres policy that verifies the JWT token. Even a catastrophic bug in our API cannot accidentally fetch another user's transcripts or entities."

## Slide 47: Exploring the Graph visually
**Visuals:** Mockup of `graph-explorer.png` from the mobile app.
**Text:** 
- `force_directed_graphview` in Flutter.
**Script:** "We made this memory tangible. Using a force-directed graph view in Flutter, users can physically explore their own memory map, tapping a node to immediately jump to the session where the topic was discussed."

---

# SECTION 6: OBSERVABILITY & DEVOPS (Slides 48–53)

## Slide 48: Section Divider - Infra
**Visuals:** Full-bleed amber background.
**Text:** **Infrastructure & DevOps.**
**Script:** "Let's look at the infrastructure tools used to deploy and monitor this system."

## Slide 49: Tracing the Stack
**Visuals:** Logos of Sentry, Prometheus, OpenTelemetry, Grafana.
**Text:** 
- Deep stack visibility.
**Script:** "We built OpenTelemetry tracing into the API from day one. Every request creates a span, allowing us to pinpoint exactly which function in the pipeline—from STT to LLM to DB write—is causing a bottleneck, visualized via Grafana."

## Slide 50: Context-Injected Logging
**Visuals:** A JSON log block showing `event`, `task`, `elapsed_ms`.
**Text:** 
- `structlog` implementation.
**Script:** "We abandoned standard print statements in favor of `structlog`. Every log output is a strictly formatted JSON object injected with the `session_id`. When an error occurs, we can instantly filter logs to trace the specific lifecycle of that exact user session."

## Slide 51: Multi-Stage Containerization
**Visuals:** Docker logo.
**Text:** 
- Target layers: `api-runtime` vs `worker-runtime`.
**Script:** "Our backend is fully containerized. A multi-stage `Dockerfile` compiles a single lightweight image, which we use to spin up independent isolated containers for the web server, the background workers, and the Redis cache."

## Slide 52: Distributed Primary Keys
**Visuals:** Text showing a ULID vs a standard integer.
**Text:** 
- **ULIDs (Universally Unique Lexicographically Sortable Identifiers).**
**Script:** "We use ULIDs instead of standard auto-incrementing integers for database primary keys. They are chronologically sortable like standard IDs, but completely globally unique, eliminating database collision issues in distributed systems."

## Slide 53: Continuous Integration Quality Gates
**Visuals:** Green checkmarks on a CI pipeline.
**Text:** 
- Backend: `mypy --strict`, `Ruff`, `pytest`.
- Frontend: `flutter analyze`, `flutter test`.
**Script:** "We enforce rigorous CI/CD quality gates. Any code pushed must pass strict type-checking with mypy, syntax linting with Ruff, and our pytest suite. This discipline ensures the main branch remains stable at all times."

---

# SECTION 7: EVALUATION & SCOPE (Slides 54–60)

## Slide 54: Evaluating the AI (Metrics)
**Visuals:** 4 Metric tiles. The number "80%" highlighted in amber.
**Text:** 
- **Transcription (WER):** Target ≥85% accuracy.
- **Latency:** ~300ms glass-to-glass.
- **Context Accuracy:** ~80% correctly grounded answers.
**Script:** "How do we prove it works? Our Word Error Rate targets 85% accuracy. Across 30 live trial sessions, our GraphRAG pipeline delivered context-accurate answers 80% of the time, dramatically reducing LLM hallucinations."

## Slide 55: Honest Project Boundaries
**Visuals:** A bounding box indicating what's inside.
**Text:** 
- English-only.
- Cloud-connected (Internet required).
- Thin client by design.
**Script:** "We want to be transparent about the boundaries of this FYP. The current build is English-only and strictly requires an internet connection due to the thin-client architecture. These are deliberate choices, not limitations."

## Slide 56: Future Scope - Offline Fallback
**Visuals:** Graphic of local device inference.
**Text:** 
- Small Local LLMs & STT.
**Script:** "Looking to the future, we plan to implement a true offline fallback. We already run ONNX embeddings locally on the device; expanding this to a small on-device STT and LLM will allow basic Wingman functionality without internet."

## Slide 57: Future Scope - Multilingual & Urdu
**Visuals:** Globe icon.
**Text:** 
- Expand parsing logic for multi-language.
**Script:** "The next frontier is breaking the English-only barrier. Because Flutter supports robust localization and Whisper processes multiple languages, adapting our backend prompts to support Urdu is our next immediate milestone."

## Slide 58: Future Scope - Tone-Aware Coaching
**Visuals:** Soundwave turning into a smiley face.
**Text:** 
- Real-time vocal prosody analysis.
**Script:** "Currently, we analyze the words spoken. In the future, we plan to analyze the vocal tone itself—measuring pitch and pacing—to provide live coaching not just on *what* you say, but *how* you say it."

## Slide 59: Project Management & Live Demo
**Visuals:** WBS tree: Research → Design → Dev → Testing.
**Text:** 
- Iterative R&D SDLC.
- Live Demonstration.
**Script:** "We executed this project using an iterative lifecycle, integrating complex modules one by one. We will now transition to a live demonstration of the app, showcasing sub-second advice and Consultant memory retrieval."

## Slide 60: Q&A
**Visuals:** Logo and clean typography (`bubbles-ai-qr.png`).
**Text:** 
- **Bubbles** — Get better at talking, one conversation at a time.
- Github: [github.com/Qdevaan/Bubbles-AI]
- Thank you. Questions?
**Script:** "Thank you for your time and attention. Bubbles helps you get better at talking, one conversation at a time. We open the floor to your questions."

---

## 🛠 DEMO CONTINGENCY PLAN (For the Presenters)
1. **Network Failure:** If the API cannot be reached, immediately switch to the high-res fallback screenshots stored in `Documentation/Screenshots/`. Do not spend time debugging the network on stage.
2. **Audio Feedback Loop:** Ensure the presentation microphone is not picking up the laptop speaker, which confuses the diarization module.
3. **Walkthrough Flow:**
   - Open App → Show Dashboard metrics.
   - Start New Session → Speak a clear sentence → Wait 300ms for Wingman tip to appear.
   - End Session → Open Consultant → Ask "What did I just say about X?" → Show AI response.
   - Open Graph Explorer → Show the generated entity node.
