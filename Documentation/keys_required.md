# Required API Keys for Bubbles AI Server (Optimized Architecture)

Based on the optimized implementation plan (which integrates LiteLLM, Cerebras, Google Gemini, and Upstash Redis), your backend environment now relies on the following API keys and connection secrets.

## 1. Supabase (Database, Auth & Vector Store)
Supabase handles your core `asyncpg` connections, authentication, and `pgvector` storage (optimized with HNSW tuning).
*   **`SUPABASE_URL`**: The URL of your Supabase project.
*   **`SUPABASE_KEY`**: The public anon key.
*   **`SUPABASE_SERVICE_KEY`**: The service-role key (used by the FastAPI server to bypass Row Level Security).

**How to get them:**
1. Go to [supabase.com](https://supabase.com) and access your project dashboard.
2. Navigate to **Settings** (gear icon on the left) > **API**.
3. Under "Project URL" and "Project API keys", copy your URL, `anon` key, and `service_role` secret.

---

## 2. Cerebras (Ultra-Fast Wingman LLM)
Used by the LiteLLM Multi-Provider Gateway to power the Wingman module. Cerebras provides massive speed improvements (2-4x faster responses), eliminating rate limit failures.
*   **`CEREBRAS_API_KEY`**: Your API key for Cerebras inference.

**How to get it:**
1. Go to [Cerebras Inference](https://inference.cerebras.ai).
2. Create an account and sign in.
3. Navigate to the **API Keys** section in your dashboard.
4. Click **Create API Key** and copy the generated secret.

---

## 3. Google Gemini (High-Quality Consultant LLM)
Used by the LiteLLM Gateway to power the Consultant queries and complex tasks like Coaching Reports. Gemini Flash provides better context window handling with no truncation issues.
*   **`GEMINI_API_KEY`**: Your API key for Google's Gemini models.

**How to get it:**
1. Go to [Google AI Studio](https://aistudio.google.com).
2. Sign in with your Google account.
3. Click on **Get API key** on the left-hand menu.
4. Click **Create API Key**, preferably linking it to a new or existing Google Cloud project.

---

## 4. Upstash Redis (High-Speed Cache)
Upstash provides a zero-ops, serverless Redis deployment used for your In-Memory TTL Cache and rate-limiting to save 100-200ms per request.
*   **`REDIS_URL`**: The Redis connection string (e.g., `rediss://default:<password>@<endpoint>:<port>`).

**How to get it:**
1. Go to the [Upstash Console](https://console.upstash.com/).
2. Create an account and click **Create Database** under the Redis section.
3. Choose a region closest to where you plan to host your FastAPI server.
4. Once deployed, scroll down to the "Connect" section on your database dashboard and copy the `REDIS_URL` (ensure it uses the password/secure connection).

---

## 5. Groq (LiteLLM Fallback) - *Optional but Recommended*
While Cerebras handles primary speed, keeping Groq configured in your LiteLLM Gateway adds reliability as a fallback provider.
*   **`GROQ_API_KEY`**: Your Groq inference API key.

**How to get it:**
1. Go to the [GroqCloud Console](https://console.groq.com).
2. Navigate to **API Keys** and generate a new key.

---

## 6. LiveKit (Real-time Voice/Audio)
Manages the actual real-time connection and rooms between the Flutter client and Server.
*   **`LIVEKIT_URL`**: Your Server WebSockets URL.
*   **`LIVEKIT_API_KEY`**: The key to manage LiveKit resources.
*   **`LIVEKIT_API_SECRET`**: The secret to sign and authenticate tokens.

**How to get them:**
1. Log into [LiveKit Cloud](https://cloud.livekit.io).
2. Open your LiveKit project.
3. Go to **Settings** > **Keys** to grab your Server URL and generate a new Key/Secret pair.

---

## 7. Deepgram (Speech-to-Text) - *Optional*
If you are doing manual transcription or fallback STT handling.
*   **`DEEPGRAM_KEY`**: Your API key for Deepgram transcription.

**How to get it:**
1. Go to the [Deepgram Console](https://console.deepgram.com).
2. Create an account, go to **API Keys** and click **Create a New API Key**.
