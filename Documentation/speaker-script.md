# Bubbles-AI: Full 45-Minute Master Speaker Script

> **Presenters:** Muhammad Ahmad & Attique Rehman
> **Target Duration:** 45–50 minutes (approx. 45–60 seconds per slide)
> **Pacing Tip:** Speak clearly, pause for emphasis during technical deep dives, and use hand gestures when discussing architecture flows (like data moving from the client to the backend).

---

## SECTION 1: THE INCEPTION (Slides 1–6)
*Target Time: 5 Minutes*

**Slide 1: Title Slide**
"Good morning, respected evaluators and guests. We are incredibly proud to present our final year project: Bubbles. Bubbles is not just an application; it is an AI conversation co-pilot. It is designed to listen while you speak, whisper exactly what you need to say next in real-time, and perfectly remember the details so you can consult it later. Our goal today is to show you not only what Bubbles does, but the extensive engineering that makes it possible."

**Slide 2: The Engineering Split**
"To build a system this complex, we divided the engineering stack to allow for specialized focus. I am [Your Name], and I architected the Flutter client—handling the cross-platform UI, the state management via Riverpod, and the offline-first caching layer. My partner, [Partner Name], built the asynchronous FastAPI backend, the LLM routing engine, and the knowledge graph. This strict decoupling ensured that our frontend remains buttery smooth, while our backend scales to handle heavy AI workloads."

**Slide 3: What Exactly is Bubbles?**
"So, what is Bubbles in plain English? Think of a high-stakes moment—a job interview, a salary negotiation, or a difficult client call. You freeze, or you lose your train of thought. Bubbles fixes the timing problem of communication. It doesn't wait until the meeting is over to tell you what you did wrong. It acts as a calm, clever friend in your ear, giving you the perfect words exactly when you need them. It listens, it whispers, and it remembers."

**Slide 4: The Human Problem: Speaking vs Writing**
"Why did we build this? Look at how we communicate today. When we write an email or a report, we have an entire arsenal of tools. We have spell-check, Grammarly, autocorrect, and most importantly, the backspace key. But speech happens in real-time. If you use the wrong tone, or forget a crucial detail while talking, there is no undo button. The asymmetry between the tools we have for writing and the tools we have for speaking is the fundamental problem we are solving."

**Slide 5: The Market Gap**
"When we looked at the market, we found two distinct categories, both with fatal flaws for our use case. On one side, you have meeting notetakers like Otter.ai or Fathom. They are great, but they only give you a summary *after* the meeting ends. On the other side, you have general assistants like Siri or ChatGPT. They answer questions but have no continuous memory of who you are. Neither of these acts as a live, continuous coach."

**Slide 6: The Research Validation**
"Our formal literature review validated three critical gaps that Bubbles fills. Number one: No existing tool provides sub-second, real-time coaching while you speak. Number two: No tool maps conversational memory across months of interactions to understand the full context of your life. And number three: Existing enterprise tools are built to surveil employees for corporate compliance. Bubbles is built privacy-first, to coach the individual."

---

## SECTION 2: THE PRODUCT EXPERIENCE (Slides 7–13)
*Target Time: 6 Minutes*

**Slide 7: The Core Loop**
"Our entire product ecosystem hangs on four continuous verbs: Listen, Whisper, Remember, and Improve. We listen to the live audio stream, whisper the optimal response via the UI, remember the extracted entities in our database, and use your mistakes to help you improve. This loop turns passive conversation into active skill-building."

**Slide 8: The Onboarding Flow**
"The journey begins with onboarding. From the first launch, our AppBootstrap routing engine seamlessly guides the user into the Performa Wizard. This isn't just UI fluff. The wizard collects your industry, your goals, and your desired tone. We compress this into a strict JSON payload that actively dictates the system prompt our AI uses. If you say you want to be formal and persuasive, the AI adjusts its entire vocabulary for you."

**Slide 9: Mode 1 - Live Wingman**
"Mode 1 is our flagship feature: the Live Wingman. As you speak to someone, Bubbles is listening. In sub-second intervals, it processes the other speaker's words and pushes a short, highly readable tip to your screen. It doesn't give you a paragraph to read; it gives you the exact bullet point you need to keep the conversation flowing naturally."

**Slide 10: Mode 2 - The Consultant**
"Mode 2 is the Consultant. A conversation doesn't end when you hang up the phone. Days later, you might forget what you promised a client. Using the Consultant mode, you can simply ask the AI, 'What did I agree to do for Sarah last Tuesday?' The Consultant queries your historical transcripts and streams the exact answer back to you instantly."

**Slide 11: Mode 3 - Coaching & Analytics**
"Mode 3 is post-session analytics. We believe that what gets measured gets managed. We aggregate your performance data into comprehensive dashboards. You can track your metrics over time. The ultimate goal of Bubbles is proven right here: we want you to visually see your mistake counts trending down, and your conversational sentiment trending up."

**Slide 12: Mode 4 - Drills & Gamification**
"Mode 4 transforms those analytics into active practice. Every time you make a structural or grammatical mistake during a live session, Bubbles automatically converts it into a flashcard. We use the Leitner spaced-repetition system—the same cognitive science behind apps like Anki. You earn XP for completing drills, building daily streaks that turn communication growth into a habit."

**Slide 13: Privacy First**
"But with an app listening to your conversations, privacy is the elephant in the room. We don't just promise privacy in a terms of service document; we enforce it at the database level. Using Row-Level Security in Postgres, we mathematically guarantee that a user's JWT token can only access their specific rows. Your data stays yours, period."

---

## SECTION 3: IN-DEPTH FRONTEND ARCHITECTURE (Slides 14–26)
*Target Time: 10 Minutes*

**Slide 14: Section Divider - Frontend Architecture**
"Let's transition from what Bubbles does, to how it is built. We will start with a deep dive into our Flutter mobile client architecture."

**Slide 15: The Dependency Injection Tree**
"To maintain a clean codebase across 37 screens, we strictly layered our architecture using Provider. State flows in one direction. Our MultiProvider tree injects the ConnectionService into the ApiService. The ApiService is injected into our Repositories, which are finally consumed by the UI state controllers. This means our UI widgets never, ever make direct network calls."

**Slide 16: The Repository Pattern**
"This separation of concerns is handled by the Repository Pattern. If the UI needs a list of past sessions, it asks the SessionProvider, which asks the SessionsRepository. The repository is the brain of the client data layer. It alone decides whether to serve data instantly from the local SQLite cache, or to execute an HTTP request to the backend."

**Slide 17: Caching Layer: PersistentCacheService**
"Our primary persistence layer is the PersistentCacheService. We don't just dump raw JSON into SQLite. We wrap every piece of data in a structured CacheEntry object that includes a calculated Time-To-Live, or TTL. This allows the app to automatically invalidate stale data mathematically, ensuring the user never sees outdated information."

**Slide 18: Stale-While-Revalidate Algorithm**
"This caching layer powers our Stale-While-Revalidate algorithm. When you open a screen, you don't see a loading spinner. Our BaseRepository immediately yields the stale data from SQLite to render the UI on frame one. Silently, in the background, it fetches the fresh data from the API, updates SQLite, and triggers a seamless UI rebuild. The result is an app that feels instantaneous."

**Slide 19: The Hydration Service**
"Managing 11 different repository caches manually would cause race conditions. To solve this, we built the HydrationService. When a user logs in, or when the app wakes up, the HydrationService acts as an orchestrator. It triggers parallel, non-blocking refresh commands across all repositories simultaneously, pre-warming the app state so navigation is frictionless."

**Slide 20: Boot State Mirroring (0ms Routing)**
"We also eliminated the traditional splash screen delay. Waiting for async database checks at launch is a common Flutter anti-pattern. We built a BootStateService that synchronously mirrors the user's auth state. On the very first rendering frame, the AppBootstrap widget reads this synchronous mirror and routes the user directly to the Home screen in zero milliseconds."

**Slide 21: Realtime Subscriptions**
"For live updates, HTTP polling is inefficient and drains the battery. Instead, we utilize Supabase Realtime WebSocket channels. For example, when an asynchronous background worker finishes generating a coaching report on the server, it updates the database. The WebSocket instantly pushes that change to the Flutter UI, which reactively rebuilds without the user ever pulling to refresh."

**Slide 22: Live Voice Architecture**
"Capturing live audio is resource-intensive. We optimized this by moving wake-word detection to the edge. Our WakeWordService uses Picovoice Porcupine to listen for 'Hey Bubbles' entirely on the device, requiring no internet. Only when the wake word is detected does our VoiceAssistantService open a websocket stream to the backend, drastically saving battery life and preserving privacy."

**Slide 23: Global Voice Overlay Stack**
"Because a conversation doesn't pause when you navigate an app, we couldn't tie our microphone UI to a specific screen. We engineered a global VoiceOverlay that sits at the absolute root of the Flutter widget tree, above the Navigator stack. This guarantees that the Wingman HUD remains persistent and active, even if you are swiping through your settings or analytics."

**Slide 24: Device Performance Tiering**
"We know Android hardware varies wildly. To ensure a smooth 60 frames per second on all devices, we wrote a DevicePerfTier service. During initialization, it profiles the device's memory and CPU. If it detects a low-end phone, it automatically degrades the UI—disabling expensive BackdropFilter blurs and complex particle animations—prioritizing fluid performance over eye candy."

**Slide 25: Authentic Typography & UI**
"Even our typography is engineered for performance. We bundled the entire Manrope font family locally into our assets and explicitly disabled Google Fonts runtime fetching. This means text renders instantly, even in airplane mode, completely eliminating layout shifts and network-dependent UI jitters."

**Slide 26: Cross-Platform Unification**
"Ultimately, this architecture allowed us to build one codebase that compiles perfectly to iOS, Android, Web, and Desktop. Because our business logic is entirely decoupled from the UI, we use Flutter's LayoutBuilders to fluidly adapt our screens from a mobile viewport to a multi-column desktop layout, without writing a single duplicate line of logic."

---

## SECTION 4: IN-DEPTH BACKEND ARCHITECTURE (Slides 27–41)
*Target Time: 12 Minutes*

**Slide 27: Section Divider - Backend Architecture**
"We now move from the mobile client to the backend: Bubbles Brain v5. This is where the heavy computational lifting happens."

**Slide 28: Server Topology**
"Our API runs on an ASGI server topology using Python 3.12 and FastAPI. Gunicorn acts as our process manager, spinning up multiple Uvicorn worker processes. Because FastAPI natively utilizes Python's asyncio event loop, a single worker can concurrently await hundreds of LLM calls or database queries without ever blocking the main execution thread."

**Slide 29: Request Lifecycle & Strict Contracts**
"Every incoming payload is subjected to rigorous validation. We use Pydantic v2 to define strict schemas. If a client sends a string instead of an integer, or misses a required field, Pydantic intercepts it at the middleware layer and throws a 422 Unprocessable Entity error. Malformed data is physically incapable of reaching our controllers or our database."

**Slide 30: Wingman Request Flow**
"Let's trace a real-time Wingman request. The Flutter app sends an audio chunk to the `/process_audio` endpoint. We await the Groq Whisper STT to transcribe it. The transcript hits our LLM Router, which generates advice. Finally, we stream the payload back to Flutter using Server-Sent Events (SSE). This entire lifecycle happens in roughly 300 milliseconds."

**Slide 31: The LLM Routing Engine**
"The crown jewel of our backend is our custom LLM Routing Engine. We realized early on that relying on a single AI provider was a bottleneck. Our router acts as a dynamic orchestrator. It allows us to route fast, live advice to Llama 3 running on Groq LPUs, while routing deep, analytical Consultant queries to Google Gemini's advanced reasoning models."

**Slide 32: TaskChains**
"We control this via 'TaskChains'. In our codebase, every endpoint requests a specific TaskChain. For instance, the `wingman.json` chain prioritizes Groq, sets a low temperature of 0.2 to prevent hallucinations, and caps tokens at 600 for speed. The router reads this configuration and executes the exact LLM call tailored for that specific feature."

**Slide 33: Circuit Breaker State Machine**
"To guarantee high availability, the router implements a Circuit Breaker state machine. If Groq experiences an outage and times out, our breaker transitions to an 'Open' state. It instantly stops routing to Groq, falling back to OpenRouter or Gemini. In the background, it transitions to 'Half-Open' to periodically test if Groq is back online. This prevents cascading vendor failures from taking down our app."

**Slide 34: Diarization Engine**
"A unique challenge we solved was Diarization. When two people speak into one phone microphone, the AI must not advise the user on their own sentences—that creates a feedback loop. We parse precise word-level timestamps from the STT output. Using pre-enrolled speaker profiles, we strictly separate the dialogue tracks into 'User' and 'Other', ensuring Wingman only reacts to the external speaker."

**Slide 35: Background Queue Topology (ARQ)**
"We cannot afford to run heavy computations on the HTTP request thread. Tasks like Knowledge Graph extraction, generating embeddings, and calculating gamification XP are offloaded. We push these tasks to a Redis instance, where standalone asynchronous ARQ worker processes pop them off the queue and execute them in the background, keeping the API lightning fast."

**Slide 36: Idempotent Worker Design**
"In distributed systems, workers can crash, and network retries happen. We designed every single ARQ background worker to be strictly idempotent. Before a job grants a user 50 XP for completing a session, it checks a unique transaction key in the database. This guarantees that even if a job executes twice due to a retry, the user's data is never duplicated or corrupted."

**Slide 37: In-RAM Session State**
"HTTP is a stateless protocol, but a conversation is highly stateful. To solve this, we maintain an in-RAM session state dictionary on the server. When audio chunks arrive milliseconds apart, the API instantly retrieves the conversational context from RAM, while continuously committing checkpoints to Postgres in the background for durability."

**Slide 38: Outbound Resiliency**
"Network calls to AI providers are inherently unreliable. We wrap all outbound LLM calls using the Tenacity library. If a transient network error occurs, the code automatically retries the request using an exponential backoff curve. This absorbs temporary network blips without the user ever seeing an error screen."

**Slide 39: Inbound Rate Limiting**
"To protect our own infrastructure from accidental loops or malicious DDoS attacks, we implemented a robust inbound defense. Every endpoint is protected by a Redis-backed token-bucket rate limiter. This strictly throttles the requests-per-minute on a per-user basis, ensuring server stability under load."

**Slide 40: Database Concurrency**
"Our database connection relies on SQLAlchemy 2.0 with the `asyncpg` driver, allowing fully asynchronous queries. To handle the load of hundreds of concurrent Uvicorn and ARQ workers, we route all connections through PgBouncer. This connection pooling drastically reduces the TCP overhead of establishing database connections, speeding up read/write latency."

**Slide 41: Alembic Schema Versioning**
"Finally, we treat our database schema as code. We never make manual alterations to Postgres. We use Alembic to maintain versioned, reversible migration scripts. With 7 current migrations, we can spin up an exact, flawless replica of our production database for testing, or safely rollback a bad deployment without losing data."

---

## SECTION 5: HYBRID MEMORY & GraphRAG (Slides 42–47)
*Target Time: 5 Minutes*

**Slide 42: Section Divider - Memory**
"We now move to Section 5: The Hybrid Memory Engine. This is the science behind how Bubbles remembers your life."

**Slide 43: The Hallucination Problem in Pure RAG**
"Most AI tools use Retrieval-Augmented Generation, or RAG, backed purely by vector databases. Vectors are great for semantic matching, but terrible at hard facts. If you ask a vector DB about a coworker named Bob, it might return transcripts about a client named Rob, because their semantic distance is similar. This causes massive AI hallucination."

**Slide 44: The Knowledge Graph (NetworkX)**
"We solved this by engineering a concrete Knowledge Graph. As you speak, our extraction module parses the transcripts, identifies exact entities, and maps the rigid relationships between them using Python's NetworkX library. It learns that 'Bob' 'is a manager at' 'Company X'. We store these exact edges securely in Postgres link tables."

**Slide 45: Fused Querying (GraphRAG)**
"When you ask the Consultant a question, we execute a fused GraphRAG query. We pull thematic context from the vector embeddings, and simultaneously execute an ego-graph search around the specific entities you mentioned via SQL recursive joins. We fuse both results. The AI receives a context payload that is both semantically rich and factually flawless."

**Slide 46: Privacy Enforced by Postgres (RLS)**
"Because memory is deeply personal, application-level security wasn't enough. We implemented Row-Level Security directly inside Postgres. Every query passes through a database policy that verifies the user's UUID from their JWT token. Even if we accidentally wrote a bug in our Python API that queried all sessions, the Postgres engine itself would block the data leak."

**Slide 47: Exploring the Graph Visually**
"We didn't want this memory to be a black box. We expose the knowledge graph directly to the user. Using a force-directed graph view in the Flutter app, users can pan and zoom through a physical map of their own memories, tapping on a node—like a person or a project—to instantly jump to the exact session where it was discussed."

---

## SECTION 6: OBSERVABILITY & DEVOPS (Slides 48–53)
*Target Time: 4 Minutes*

**Slide 48: Section Divider - Infra**
"For Section 6, we will briefly cover our Infrastructure and DevOps practices, proving this is a production-ready deployment."

**Slide 49: Tracing the Stack**
"We built OpenTelemetry tracing into the API from the very beginning. Every HTTP request creates a trace span. We export these metrics to Prometheus and visualize them in Grafana. This allows us to look at a 400-millisecond request and see exactly how many milliseconds were spent on STT, the LLM, and the database write."

**Slide 50: Context-Injected Logging**
"Standard print statements are useless in a concurrent async server because logs overlap. We implemented `structlog`. Every log output is a strictly formatted JSON object, automatically injected with the current `session_id`. When an error occurs, we can instantly filter our logs to trace the precise lifecycle of that specific user's session."

**Slide 51: Multi-Stage Containerization**
"Our entire backend is containerized. We wrote a multi-stage Dockerfile that compiles a single, highly optimized, lightweight image. From this single image, Docker Compose spins up completely isolated containers for the web server API, the ARQ background workers, and the Redis cache instance."

**Slide 52: Distributed Primary Keys**
"We made a critical architectural decision regarding database primary keys. We do not use auto-incrementing integers, which expose usage metrics and block distributed scaling. We use ULIDs—Universally Unique Lexicographically Sortable Identifiers. They sort chronologically like standard IDs, but are globally unique, eliminating collision issues."

**Slide 53: Continuous Integration Quality Gates**
"We enforce rigorous CI/CD quality gates on our repository. Any code pushed to GitHub must pass strict type-checking with mypy, syntax linting with Ruff, and our backend pytest suite. On the frontend, it must pass flutter analyze. This strict discipline ensures our main branch remains completely stable at all times."

---

## SECTION 7: EVALUATION & SCOPE (Slides 54–60)
*Target Time: 3 Minutes*

**Slide 54: Evaluating the AI (Metrics)**
"As an engineering project, we evaluate our success against strict metrics. Our transcription Word Error Rate (WER) targets 85% accuracy in moderate noise. Our glass-to-glass latency for live advice is consistently around 300 milliseconds. And in over 30 live trial sessions, our GraphRAG pipeline delivered context-accurate answers 80% of the time, proving the architecture works."

**Slide 55: Honest Project Boundaries**
"We want to be entirely transparent about the boundaries of this FYP release. The current build is English-only. Furthermore, it strictly requires an internet connection due to our thin-client design. These are deliberate architectural choices made to guarantee maximum performance and iteration speed, not technical limitations."

**Slide 56: Future Scope - Offline Fallback**
"Looking to the future, we plan to implement a true offline fallback. We already successfully run ONNX embeddings locally on the device. Our next step is to expand this to include a small quantized STT model and an on-device LLM, allowing basic Wingman functionality even when the user loses internet connection."

**Slide 57: Future Scope - Multilingual & Urdu**
"The next major frontier is breaking the English-only barrier. Because Flutter natively supports robust localization, and our STT engine Whisper is already capable of processing multiple languages, our immediate milestone is adapting our backend system prompts to fully support Urdu conversations."

**Slide 58: Future Scope - Tone-Aware Coaching**
"Currently, Bubbles analyzes the *words* you speak. In the future, we plan to analyze the vocal prosody itself. By measuring your pitch, volume, and pacing in real-time, the app will provide live tone nudges—telling you if you sound too aggressive or too timid, coaching *how* you speak, not just *what* you say."

**Slide 59: Project Management & Live Demo**
"We executed this project using a highly iterative Research & Development lifecycle. We built and tested the hardest modules first—like the LLM router and the Knowledge graph—before integrating them. We will now transition to a live demonstration, showcasing sub-second Wingman advice and Consultant memory retrieval."

**Slide 60: Q&A**
"Thank you for your time, your attention, and the opportunity to share our work. Bubbles was built to help people get better at talking, one conversation at a time. We now open the floor and welcome any questions you may have."
