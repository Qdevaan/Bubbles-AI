# Live Session Overhaul + Performa Profile — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make live wingman hints sub-500ms, add confidence-gated speaker detection with manual override, make the teleprompter resizable, and add a full Performa profile that the AI reads during sessions and auto-extends after sessions.

**Architecture:** Context pre-cached at session start (zero per-turn fetch latency). Confidence score from Deepgram gating wingman calls. Performa stored in Supabase `performa` table, loaded at session start, injected into wingman prompt. Teleprompter extracted to its own widget file with drag/snap behaviour.

**Tech Stack:** Flutter + Dart (Provider), FastAPI + asyncio, Supabase (Postgres + RLS), Deepgram WebSocket, Cerebras/Groq LLM, `pdf` Flutter package (new dep).

**Spec:** `docs/superpowers/specs/2026-05-04-live-session-performa-design.md`

---

## Phase 1 — Performance & Bug Validation

### Task 1: Verify speaker detection + reduce timeouts

**Files:**
- Verify: `lib/providers/session_provider.dart`
- Modify: `lib/services/api_service.dart:284`
- Modify: `lib/providers/session_provider.dart:159`

- [ ] **Step 1: Confirm current speaker wiring is correct**

  In `lib/providers/session_provider.dart`, lines 95–106 should read:
  ```dart
  String serverSpeaker = deepgram.currentSpeaker == "user" ? "User" : "Other";
  String finalSpeaker = serverSpeaker;
  if (_swapSpeakers)
    finalSpeaker = serverSpeaker == "User" ? "Other" : "User";
  ...
  if (finalSpeaker == "Other") {
  ```
  And in `lib/screens/new_session_screen.dart` line 861:
  ```dart
  bool isMe = msg['speaker'] == "User";
  ```
  Both sides match. No code change needed here. ✓

- [ ] **Step 2: Reduce wingman HTTP timeout — `lib/services/api_service.dart` line 284**

  Change:
  ```dart
  .timeout(const Duration(seconds: 15)); // tighter timeout for real-time
  ```
  To:
  ```dart
  .timeout(const Duration(seconds: 4)); // fail fast — live coaching must be instant
  ```

- [ ] **Step 3: Reduce Realtime fallback timeout — `lib/providers/session_provider.dart` line 159**

  Change:
  ```dart
  _realtimeTimeoutTimer = Timer(const Duration(seconds: 30), () {
  ```
  To:
  ```dart
  _realtimeTimeoutTimer = Timer(const Duration(seconds: 8), () {
  ```

- [ ] **Step 4: Commit**
  ```bash
  git add lib/services/api_service.dart lib/providers/session_provider.dart
  git commit -m "perf: reduce wingman timeouts to 4s HTTP / 8s realtime"
  ```

---

### Task 2: DeepgramService — expose confidence per transcript

**Files:**
- Modify: `lib/services/deepgram_service.dart`

- [ ] **Step 1: Add confidence state**

  In `lib/services/deepgram_service.dart`, after line 23 (`String get currentSpeaker`), add:
  ```dart
  double _currentConfidence = 1.0;
  double get currentConfidence => _currentConfidence;
  ```

- [ ] **Step 2: Compute average word confidence in `_handleMessage`**

  Inside the `if (words != null && words.isNotEmpty)` block (currently line 137), after extracting `speakerId`, add confidence averaging:
  ```dart
  // Compute average word confidence for threshold gating
  double totalConf = 0;
  for (final w in words) {
    totalConf += ((w as Map)['confidence'] as num?)?.toDouble() ?? 1.0;
  }
  _currentConfidence = totalConf / words.length;
  ```
  In the `else` branch (when words null/empty), reset confidence:
  ```dart
  _currentConfidence = 0.5; // low confidence when no word data
  ```

- [ ] **Step 3: Commit**
  ```bash
  git add lib/services/deepgram_service.dart
  git commit -m "feat: expose per-transcript confidence score from Deepgram word data"
  ```

---

### Task 3: SessionProvider — confidence gating + _adviceHistory cap

**Files:**
- Modify: `lib/providers/session_provider.dart`

- [ ] **Step 1: Add confidence threshold constant + isUncertain to session logs**

  At the top of the `SessionProvider` class body (after the class declaration, before first field), add:
  ```dart
  static const double _kConfidenceThreshold = 0.75;
  ```

- [ ] **Step 2: Update `onTranscriptReceived` to gate on confidence**

  Replace the entire `onTranscriptReceived` method body with:
  ```dart
  void onTranscriptReceived(DeepgramService deepgram, ApiService api) {
    if (deepgram.currentTranscript.isEmpty) return;
    if (_sessionLogs.isNotEmpty &&
        _sessionLogs.last['text'] == deepgram.currentTranscript) return;

    final double confidence = deepgram.currentConfidence;
    final bool isUncertain = confidence < _kConfidenceThreshold;

    String serverSpeaker = deepgram.currentSpeaker == "user" ? "User" : "Other";
    String finalSpeaker = serverSpeaker;
    if (_swapSpeakers)
      finalSpeaker = serverSpeaker == "User" ? "Other" : "User";

    _sessionLogs.add({
      "speaker": finalSpeaker,
      "text": deepgram.currentTranscript,
      "isUncertain": isUncertain,
      "confidence": confidence,
    });
    notifyListeners();

    if (isUncertain) return; // skip wingman on uncertain speaker attribution

    if (finalSpeaker == "Other") {
      if (!_wingmanInFlight) {
        _askWingman(deepgram.currentTranscript, api);
      }
    } else if (_sessionId != null) {
      _logUserTurn(deepgram.currentTranscript, api);
    }
  }
  ```

- [ ] **Step 3: Cap `_adviceHistory` at 20 entries**

  In the `_setAdvice` method (around line 71), after `_adviceHistory.add(advice)`:
  ```dart
  if (_adviceHistory.length > 20) {
    _adviceHistory.removeAt(0);
  }
  ```

- [ ] **Step 4: Commit**
  ```bash
  git add lib/providers/session_provider.dart
  git commit -m "feat: confidence-gated wingman, cap advice history at 20"
  ```

---

## Phase 2 — Backend Performance

### Task 4: session_store — add context cache methods

**Files:**
- Modify: `server_v2/app/utils/session_store.py`

- [ ] **Step 1: Add context cache to `_InMemoryStore`**

  In `_InMemoryStore.__init__`, add:
  ```python
  self._ctx_cache: Dict[str, dict] = {}  # session_id → {graph, vector, performa}
  ```

  Add two methods to `_InMemoryStore`:
  ```python
  async def set_context_cache(self, session_id: str, cache: dict) -> None:
      self._ctx_cache[session_id] = cache

  async def get_context_cache(self, session_id: str) -> dict:
      return self._ctx_cache.get(session_id, {})
  ```

- [ ] **Step 2: Add same methods to the Redis-backed store class**

  Find the Redis-backed class in the same file. Add:
  ```python
  async def set_context_cache(self, session_id: str, cache: dict) -> None:
      key = f"{_REDIS_KEY_PREFIX}ctx:{session_id}"
      try:
          await self._redis.setex(key, _SESSION_TTL_SECONDS, json.dumps(cache))
      except Exception:
          self._fallback._ctx_cache[session_id] = cache

  async def get_context_cache(self, session_id: str) -> dict:
      key = f"{_REDIS_KEY_PREFIX}ctx:{session_id}"
      try:
          raw = await self._redis.get(key)
          return json.loads(raw) if raw else {}
      except Exception:
          return self._fallback._ctx_cache.get(session_id, {})
  ```

- [ ] **Step 3: Also clear context cache on `delete_session`**

  In both classes, inside `delete_session`, add:
  ```python
  self._ctx_cache.pop(session_id, None)
  ```

- [ ] **Step 4: Commit**
  ```bash
  git add server_v2/app/utils/session_store.py
  git commit -m "feat: add context cache methods to session store"
  ```

---

### Task 5: start_session pre-cache + 200ms hard timeout in wingman

**Files:**
- Modify: `server_v2/app/routes/sessions.py`

- [ ] **Step 1: Add imports at top of sessions.py** (if not already present)

  Ensure these are imported:
  ```python
  import asyncio
  from app.services import graph_svc, vector_svc
  ```

- [ ] **Step 2: Add `_warm_context_cache` async helper** (before `start_session_endpoint`)

  ```python
  async def _warm_context_cache(user_id: str, session_id: str) -> None:
      """Load graph + vector context at session start. Stored for zero-latency per-turn use."""
      def _graph():
          graph_svc.load_graph(user_id)
          return graph_svc.find_context(user_id, "")  # broad pre-load with empty query

      def _vector():
          return vector_svc.search_memory(user_id, "")

      try:
          g_ctx, v_ctx = await asyncio.wait_for(
              asyncio.gather(
                  asyncio.to_thread(_graph),
                  asyncio.to_thread(_vector),
              ),
              timeout=2.0,  # 2s budget at session start (user not waiting for a hint yet)
          )
          await session_store.set_context_cache(session_id, {
              "graph": g_ctx or "",
              "vector": v_ctx or "",
              "performa": "",  # filled in Task 10 once performa service exists
          })
      except asyncio.TimeoutError:
          await session_store.set_context_cache(session_id, {"graph": "", "vector": "", "performa": ""})
  ```

- [ ] **Step 3: Fire `_warm_context_cache` in `start_session_endpoint`**

  At the end of `start_session_endpoint`, just before `return {"session_id": session_id}`, add:
  ```python
  asyncio.create_task(_warm_context_cache(req.user_id, session_id))
  ```

- [ ] **Step 4: Update `process_transcript_wingman` to use cache first**

  In `process_transcript_wingman`, replace the `asyncio.gather(...)` block (the "1. Load contexts in parallel" section) with:
  ```python
  # 1. Load contexts — try cache first, hard-timeout fallback on miss
  cached = await session_store.get_context_cache(session_id) if session_id else {}
  if cached:
      g_ctx = cached.get("graph", "")
      v_ctx = cached.get("vector", "")
  else:
      def _graph_ctx():
          graph_svc.load_graph(user_id)
          return graph_svc.find_context(user_id, transcript)
      def _entity_ctx():
          if target_entity_id:
              return entity_svc.get_entity_context(user_id, str(target_entity_id))
          return ""
      try:
          g_ctx, v_ctx, e_ctx = await asyncio.wait_for(
              asyncio.gather(
                  asyncio.to_thread(_graph_ctx),
                  asyncio.to_thread(vector_svc.search_memory, user_id, transcript),
                  asyncio.to_thread(_entity_ctx),
              ),
              timeout=0.2,  # 200ms hard cap on cache miss
          )
      except asyncio.TimeoutError:
          g_ctx, v_ctx, e_ctx = "", "", ""

  if e_ctx:
      g_ctx = f"ROLEPLAY TARGET ENTITY CONTEXT:\n{e_ctx}\n\n" + g_ctx
  ```

  Note: move `target_entity_id = meta.get("target_entity_id") if session_id else None` and `_entity_ctx` definition before this block.

- [ ] **Step 5: Commit**
  ```bash
  git add server_v2/app/routes/sessions.py
  git commit -m "perf: pre-cache session context at start, 200ms hard timeout on miss"
  ```

---

### Task 6: Reduce wingman LLM max_tokens

**Files:**
- Modify: `server_v2/app/services/brain_service.py`

- [ ] **Step 1: Find and reduce max_tokens in `get_wingman_advice`**

  In `brain_service.py`, inside `get_wingman_advice`, find both the Cerebras and Groq call sites where `max_tokens=60` appears and change to `max_tokens=45`:
  ```python
  # Change everywhere in get_wingman_advice:
  max_tokens=45,  # was 60 — saves ~80ms latency
  ```

- [ ] **Step 2: Commit**
  ```bash
  git add server_v2/app/services/brain_service.py
  git commit -m "perf: reduce wingman max_tokens 60→45 for faster inference"
  ```

---

## Phase 3 — Backend Performa

### Task 7: Database — performa table migration

**Files:**
- Create: `server_v2/migrations/create_performa_table.sql`

- [ ] **Step 1: Write migration file**

  ```sql
  -- Migration: create performa table
  -- Run once against your Supabase project via the SQL editor or CLI.

  CREATE TABLE IF NOT EXISTS performa (
    user_id   UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    manual_data  JSONB NOT NULL DEFAULT '{}',
    ai_data      JSONB NOT NULL DEFAULT '{}',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );

  -- Auto-update updated_at on every row write
  CREATE OR REPLACE FUNCTION update_performa_updated_at()
  RETURNS TRIGGER AS $$
  BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;

  CREATE TRIGGER trg_performa_updated_at
    BEFORE UPDATE ON performa
    FOR EACH ROW EXECUTE FUNCTION update_performa_updated_at();

  -- RLS: each user reads and writes only their own row
  ALTER TABLE performa ENABLE ROW LEVEL SECURITY;

  CREATE POLICY "Users manage own performa"
    ON performa FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
  ```

- [ ] **Step 2: Run the migration in Supabase SQL editor**

  Copy the contents of `create_performa_table.sql` and execute in Supabase → SQL Editor. Verify table appears in Table Editor.

- [ ] **Step 3: Commit**
  ```bash
  git add server_v2/migrations/create_performa_table.sql
  git commit -m "db: add performa table with RLS"
  ```

---

### Task 8: performa_service.py — CRUD + AI insight analysis

**Files:**
- Create: `server_v2/app/services/performa_service.py`

- [ ] **Step 1: Write the service**

  ```python
  """Performa service — user context profile CRUD and AI-driven insight extraction."""

  import asyncio
  import json
  import logging
  from datetime import datetime, timezone
  from typing import Any, Dict, List, Optional

  from app.config import settings
  from app.utils.supabase_client import supabase  # same client used throughout the project

  logger = logging.getLogger(__name__)

  _TABLE = "performa"


  # ── CRUD ──────────────────────────────────────────────────────────────────────

  def get_performa(user_id: str) -> Dict[str, Any]:
      """Return the user's performa row (manual_data + ai_data). Creates empty row if absent."""
      resp = supabase.table(_TABLE).select("*").eq("user_id", user_id).maybe_single().execute()
      if resp.data:
          return resp.data
      # First access — upsert empty row
      supabase.table(_TABLE).upsert({"user_id": user_id}).execute()
      return {"user_id": user_id, "manual_data": {}, "ai_data": {}}


  def update_manual_data(user_id: str, manual_data: Dict[str, Any]) -> None:
      supabase.table(_TABLE).upsert({
          "user_id": user_id,
          "manual_data": manual_data,
      }).execute()


  def get_pending_insights(user_id: str) -> List[Dict[str, Any]]:
      """Return AI insights awaiting approval (approved=False)."""
      row = get_performa(user_id)
      ai_data = row.get("ai_data", {})
      insights = ai_data.get("aiInsights", [])
      return [i for i in insights if not i.get("approved", True)]


  def approve_insight(user_id: str, insight_id: str, approved: bool) -> None:
      """Approve or permanently reject a pending insight."""
      row = get_performa(user_id)
      ai_data = row.get("ai_data", {})
      insights = ai_data.get("aiInsights", [])
      if approved:
          for i in insights:
              if i.get("id") == insight_id:
                  i["approved"] = True
                  break
      else:
          insights = [i for i in insights if i.get("id") != insight_id]
      ai_data["aiInsights"] = insights
      supabase.table(_TABLE).update({"ai_data": ai_data}).eq("user_id", user_id).execute()


  def _add_insight(user_id: str, text: str, source_session: str, confidence: float, approved: bool) -> None:
      row = get_performa(user_id)
      ai_data = row.get("ai_data", {})
      insights: List[Dict] = ai_data.get("aiInsights", [])
      # De-duplicate: skip if very similar insight already exists
      for existing in insights:
          if existing.get("text", "").lower() == text.lower():
              return
      import uuid
      insights.append({
          "id": str(uuid.uuid4()),
          "text": text,
          "source": source_session,
          "confidence": confidence,
          "addedAt": datetime.now(timezone.utc).isoformat(),
          "approved": approved,
      })
      ai_data["aiInsights"] = insights[-50:]  # cap at 50 total insights
      supabase.table(_TABLE).update({"ai_data": ai_data}).eq("user_id", user_id).execute()


  # ── AI Extension ─────────────────────────────────────────────────────────────

  async def analyze_session_for_insights(
      user_id: str,
      session_id: str,
      transcript_text: str,  # full session transcript as plain text
      llm_client,            # Groq or Cerebras client (passed in to avoid circular import)
      model: str,
  ) -> None:
      """
      Post-session: scan transcript for user patterns. Silent-add minor findings;
      mark significant findings as pending approval (approved=False).
      """
      if not transcript_text.strip():
          return

      prompt = (
          "Analyze this conversation transcript. Extract insights about the FIRST speaker (the user).\n\n"
          "Return a JSON array. Each item: {\"text\": \"...\", \"type\": \"minor|significant\", \"confidence\": 0.0-1.0}\n\n"
          "MINOR: contact name mentioned, repeated keyword/topic, industry jargon used\n"
          "SIGNIFICANT: new communication goal detected, weakness pattern across multiple turns, "
          "role or industry change signal, recurring challenge\n\n"
          "Rules:\n"
          "- Max 5 insights per session\n"
          "- Only insights about the USER, not the other speaker\n"
          "- Be specific: 'Frequently uses filler words when asked about pricing' not 'needs improvement'\n"
          "- Return [] if nothing notable found\n\n"
          f"Transcript:\n{transcript_text[:3000]}"
      )

      try:
          resp = await asyncio.to_thread(
              lambda: llm_client.chat.completions.create(
                  model=model,
                  messages=[{"role": "user", "content": prompt}],
                  max_tokens=300,
                  temperature=0.3,
              )
          )
          raw = resp.choices[0].message.content.strip()
          # Extract JSON array from response
          start, end = raw.find("["), raw.rfind("]")
          if start == -1 or end == -1:
              return
          insights = json.loads(raw[start:end + 1])
      except Exception as e:
          logger.warning(f"Performa insight extraction failed for {user_id}: {e}")
          return

      for item in insights:
          text = item.get("text", "").strip()
          kind = item.get("type", "minor")
          conf = float(item.get("confidence", 0.7))
          if not text:
              continue
          approved = kind == "minor"  # minor → silent; significant → needs approval
          await asyncio.to_thread(_add_insight, user_id, text, session_id, conf, approved)


  # ── Context for Wingman ───────────────────────────────────────────────────────

  def build_context_block(user_id: str, max_tokens: int = 80) -> str:
      """Return the ABOUT YOU block injected into wingman system prompt."""
      try:
          row = get_performa(user_id)
          m = row.get("manual_data", {})
          parts = []
          if m.get("role"):
              company = m.get("company", "")
              parts.append(f"Role: {m['role']}" + (f" at {company}" if company else ""))
          if m.get("industry"):
              parts.append(f"Industry: {m['industry']}")
          goals = m.get("goals", [])
          if goals:
              parts.append(f"Goals: {', '.join(goals[:3])}")
          keywords = m.get("customKeywords", [])
          if keywords:
              parts.append(f"Watch for: {', '.join(keywords[:5])}")
          style = m.get("communicationStyle", "")
          if style:
              parts.append(f"Style: {style}")
          if not parts:
              return ""
          block = "ABOUT YOU:\n" + "\n".join(parts)
          # Rough token cap: 4 chars ≈ 1 token
          return block[:max_tokens * 4]
      except Exception:
          return ""
  ```

- [ ] **Step 2: Commit**
  ```bash
  git add server_v2/app/services/performa_service.py
  git commit -m "feat: performa service — CRUD, AI insight extraction, context builder"
  ```

---

### Task 9: performa router + register in main.py

**Files:**
- Create: `server_v2/app/routes/performa.py`
- Modify: `server_v2/app/main.py`

- [ ] **Step 1: Write the router**

  ```python
  """Performa routes — user context profile."""

  from fastapi import APIRouter, Depends, Request

  from app.auth import VerifiedUser, get_verified_user
  from app.utils.rate_limit import limiter
  import app.services.performa_service as performa_svc
  from pydantic import BaseModel
  from typing import Any, Dict, List, Optional

  router = APIRouter(tags=["performa"])


  class UpdatePerformaRequest(BaseModel):
      user_id: str
      manual_data: Dict[str, Any]


  class ApproveInsightRequest(BaseModel):
      user_id: str
      insight_id: str
      approved: bool


  @router.get("/performa/{user_id}")
  @limiter.limit("30/minute")
  async def get_performa(
      request: Request,
      user_id: str,
      user: VerifiedUser = Depends(get_verified_user),
  ):
      import asyncio
      return await asyncio.to_thread(performa_svc.get_performa, user_id)


  @router.put("/performa/{user_id}")
  @limiter.limit("20/minute")
  async def update_performa(
      request: Request,
      user_id: str,
      req: UpdatePerformaRequest,
      user: VerifiedUser = Depends(get_verified_user),
  ):
      import asyncio
      await asyncio.to_thread(performa_svc.update_manual_data, user_id, req.manual_data)
      return {"ok": True}


  @router.get("/performa/{user_id}/pending_insights")
  @limiter.limit("30/minute")
  async def get_pending_insights(
      request: Request,
      user_id: str,
      user: VerifiedUser = Depends(get_verified_user),
  ):
      import asyncio
      insights = await asyncio.to_thread(performa_svc.get_pending_insights, user_id)
      return {"insights": insights}


  @router.post("/performa/{user_id}/approve_insight")
  @limiter.limit("30/minute")
  async def approve_insight(
      request: Request,
      user_id: str,
      req: ApproveInsightRequest,
      user: VerifiedUser = Depends(get_verified_user),
  ):
      import asyncio
      await asyncio.to_thread(performa_svc.approve_insight, user_id, req.insight_id, req.approved)
      return {"ok": True}
  ```

- [ ] **Step 2: Register router in `server_v2/app/main.py`**

  In `main.py`, update the import line:
  ```python
  from app.routes import health, sessions, consultant, voice, analytics, entities, gamification, stt, performance, performa
  ```

  After the existing `v1.include_router(performance.router)` line, add:
  ```python
  v1.include_router(performa.router)
  ```

- [ ] **Step 3: Commit**
  ```bash
  git add server_v2/app/routes/performa.py server_v2/app/main.py
  git commit -m "feat: add /v1/performa CRUD and insight approval endpoints"
  ```

---

### Task 10: Inject performa into session context cache + wingman prompt

**Files:**
- Modify: `server_v2/app/routes/sessions.py`
- Modify: `server_v2/app/services/brain_service.py`

- [ ] **Step 1: Add performa fetch to `_warm_context_cache` in sessions.py**

  Update the helper from Task 5 to also load performa context:
  ```python
  async def _warm_context_cache(user_id: str, session_id: str) -> None:
      import app.services.performa_service as performa_svc  # avoid circular at module level

      def _graph():
          graph_svc.load_graph(user_id)
          return graph_svc.find_context(user_id, "")

      def _vector():
          return vector_svc.search_memory(user_id, "")

      def _performa():
          return performa_svc.build_context_block(user_id)

      try:
          g_ctx, v_ctx, p_ctx = await asyncio.wait_for(
              asyncio.gather(
                  asyncio.to_thread(_graph),
                  asyncio.to_thread(_vector),
                  asyncio.to_thread(_performa),
              ),
              timeout=2.0,
          )
          await session_store.set_context_cache(session_id, {
              "graph": g_ctx or "",
              "vector": v_ctx or "",
              "performa": p_ctx or "",
          })
      except asyncio.TimeoutError:
          await session_store.set_context_cache(session_id, {"graph": "", "vector": "", "performa": ""})
  ```

- [ ] **Step 2: Pass performa context to `get_wingman_advice`**

  In `process_transcript_wingman`, after loading from cache, extract performa:
  ```python
  p_ctx = cached.get("performa", "") if cached else ""
  ```

  Then update the `get_wingman_advice` call:
  ```python
  result = await brain_svc.get_wingman_advice(
      user_id, transcript, g_ctx, v_ctx, req.mode, req.persona,
      performa_context=p_ctx,
  )
  ```

- [ ] **Step 3: Accept + inject performa context in `brain_service.get_wingman_advice`**

  Update the method signature:
  ```python
  async def get_wingman_advice(
      self,
      user_id: str,
      transcript: str,
      graph_context: str,
      vector_context: str,
      mode: str = "casual",
      persona: str = "casual",
      performa_context: str = "",  # NEW
  ) -> Dict[str, Any]:
  ```

  In the `else` branch (non-roleplay system prompt), find the line that starts with `"You are Bubbles, a sharp real-time"`. Just before the `known_facts_block` injection, add:
  ```python
  about_you_block = (
      f"\n\n{performa_context}"
  ) if performa_context.strip() else ""
  ```

  Then inside the system_prompt string, after `known_facts_block`, append `about_you_block`:
  ```python
  f"{known_facts_block}"
  f"{about_you_block}"
  ```

- [ ] **Step 4: Hook post-session analysis in `end_session` endpoint**

  In `sessions.py`, in the `end_session` endpoint, after saving the session, add a fire-and-forget insight extraction. First add the import at top of sessions.py:
  ```python
  import app.services.performa_service as performa_svc
  ```

  Then in `end_session`, after `fire_and_forget(gamification_svc.update_streak(...))`:
  ```python
  # Build plain-text transcript for performa analysis
  async def _run_performa_analysis():
      try:
          import app.services.performa_service as _ps
          logs = session_svc.get_session_logs(session_id)  # existing method
          text = "\n".join(
              f"{'You' if l['role'] == 'user' else 'Other'}: {l['content']}"
              for l in (logs or []) if l.get('content')
          )
          if text:
              await _ps.analyze_session_for_insights(
                  req.user_id, session_id, text,
                  llm_client=brain_svc._groq_client,  # use Groq (cheap) for analysis
                  model=settings.WINGMAN_MODEL,
              )
      except Exception as e:
          logger.warning(f"Performa post-session analysis error: {e}")

  asyncio.create_task(_run_performa_analysis())
  ```

- [ ] **Step 5: Commit**
  ```bash
  git add server_v2/app/routes/sessions.py server_v2/app/services/brain_service.py
  git commit -m "feat: inject performa context into session cache and wingman prompt"
  ```

---

## Phase 4 — Flutter Performa

### Task 11: Performa data model

**Files:**
- Create: `lib/models/performa.dart`

- [ ] **Step 1: Write the model**

  ```dart
  class PerformaContact {
    final String name;
    final String relationship;
    final String notes;
    final DateTime? lastSeenAt;

    const PerformaContact({
      required this.name,
      required this.relationship,
      this.notes = '',
      this.lastSeenAt,
    });

    Map<String, dynamic> toJson() => {
      'name': name,
      'relationship': relationship,
      'notes': notes,
      if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toIso8601String(),
    };

    factory PerformaContact.fromJson(Map<String, dynamic> j) => PerformaContact(
      name: j['name'] as String? ?? '',
      relationship: j['relationship'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
      lastSeenAt: j['lastSeenAt'] != null ? DateTime.tryParse(j['lastSeenAt'] as String) : null,
    );

    PerformaContact copyWith({String? name, String? relationship, String? notes}) =>
        PerformaContact(
          name: name ?? this.name,
          relationship: relationship ?? this.relationship,
          notes: notes ?? this.notes,
          lastSeenAt: lastSeenAt,
        );
  }

  class PerformaInsight {
    final String id;
    final String text;
    final String source; // session_id
    final double confidence;
    final DateTime addedAt;
    final bool approved;

    const PerformaInsight({
      required this.id,
      required this.text,
      required this.source,
      required this.confidence,
      required this.addedAt,
      required this.approved,
    });

    Map<String, dynamic> toJson() => {
      'id': id,
      'text': text,
      'source': source,
      'confidence': confidence,
      'addedAt': addedAt.toIso8601String(),
      'approved': approved,
    };

    factory PerformaInsight.fromJson(Map<String, dynamic> j) => PerformaInsight(
      id: j['id'] as String? ?? '',
      text: j['text'] as String? ?? '',
      source: j['source'] as String? ?? '',
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0.7,
      addedAt: j['addedAt'] != null
          ? (DateTime.tryParse(j['addedAt'] as String) ?? DateTime.now())
          : DateTime.now(),
      approved: j['approved'] as bool? ?? false,
    );

    PerformaInsight copyWith({String? text, bool? approved}) => PerformaInsight(
      id: id,
      text: text ?? this.text,
      source: source,
      confidence: confidence,
      addedAt: addedAt,
      approved: approved ?? this.approved,
    );
  }

  class Performa {
    final String userId;

    // Manual fields
    final String fullName;
    final String role;
    final String industry;
    final String company;
    final List<String> goals;
    final List<String> conversationScenarios;
    final List<String> languages;
    final String communicationStyle;
    final List<PerformaContact> recurringContacts;
    final List<String> customKeywords;
    final String background;

    // AI-extended fields
    final List<PerformaInsight> aiInsights;
    final List<String> inferredStrengths;
    final List<String> inferredWeaknesses;
    final List<String> notablePatterns;

    const Performa({
      required this.userId,
      this.fullName = '',
      this.role = '',
      this.industry = '',
      this.company = '',
      this.goals = const [],
      this.conversationScenarios = const [],
      this.languages = const [],
      this.communicationStyle = '',
      this.recurringContacts = const [],
      this.customKeywords = const [],
      this.background = '',
      this.aiInsights = const [],
      this.inferredStrengths = const [],
      this.inferredWeaknesses = const [],
      this.notablePatterns = const [],
    });

    List<PerformaInsight> get pendingInsights =>
        aiInsights.where((i) => !i.approved).toList();

    Map<String, dynamic> toManualJson() => {
      'fullName': fullName,
      'role': role,
      'industry': industry,
      'company': company,
      'goals': goals,
      'conversationScenarios': conversationScenarios,
      'languages': languages,
      'communicationStyle': communicationStyle,
      'recurringContacts': recurringContacts.map((c) => c.toJson()).toList(),
      'customKeywords': customKeywords,
      'background': background,
    };

    factory Performa.fromSupabaseRow(Map<String, dynamic> row) {
      final m = (row['manual_data'] as Map<String, dynamic>?) ?? {};
      final a = (row['ai_data'] as Map<String, dynamic>?) ?? {};

      List<T> _list<T>(dynamic raw, T Function(dynamic) parse) =>
          (raw as List?)?.map(parse).toList() ?? [];

      return Performa(
        userId: row['user_id'] as String? ?? '',
        fullName: m['fullName'] as String? ?? '',
        role: m['role'] as String? ?? '',
        industry: m['industry'] as String? ?? '',
        company: m['company'] as String? ?? '',
        goals: _list(m['goals'], (e) => e as String),
        conversationScenarios: _list(m['conversationScenarios'], (e) => e as String),
        languages: _list(m['languages'], (e) => e as String),
        communicationStyle: m['communicationStyle'] as String? ?? '',
        recurringContacts: _list(m['recurringContacts'], (e) => PerformaContact.fromJson(e as Map<String, dynamic>)),
        customKeywords: _list(m['customKeywords'], (e) => e as String),
        background: m['background'] as String? ?? '',
        aiInsights: _list(a['aiInsights'], (e) => PerformaInsight.fromJson(e as Map<String, dynamic>)),
        inferredStrengths: _list(a['inferredStrengths'], (e) => e as String),
        inferredWeaknesses: _list(a['inferredWeaknesses'], (e) => e as String),
        notablePatterns: _list(a['notablePatterns'], (e) => e as String),
      );
    }

    Performa copyWith({
      String? fullName, String? role, String? industry, String? company,
      List<String>? goals, List<String>? conversationScenarios,
      List<String>? languages, String? communicationStyle,
      List<PerformaContact>? recurringContacts, List<String>? customKeywords,
      String? background, List<PerformaInsight>? aiInsights,
    }) => Performa(
      userId: userId,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      industry: industry ?? this.industry,
      company: company ?? this.company,
      goals: goals ?? this.goals,
      conversationScenarios: conversationScenarios ?? this.conversationScenarios,
      languages: languages ?? this.languages,
      communicationStyle: communicationStyle ?? this.communicationStyle,
      recurringContacts: recurringContacts ?? this.recurringContacts,
      customKeywords: customKeywords ?? this.customKeywords,
      background: background ?? this.background,
      aiInsights: aiInsights ?? this.aiInsights,
      inferredStrengths: inferredStrengths,
      inferredWeaknesses: inferredWeaknesses,
      notablePatterns: notablePatterns,
    );
  }
  ```

- [ ] **Step 2: Commit**
  ```bash
  git add lib/models/performa.dart
  git commit -m "feat: Performa data model"
  ```

---

### Task 12: PerformaRepository — Supabase CRUD + export

**Files:**
- Create: `lib/repositories/performa_repository.dart`
- Modify: `pubspec.yaml` (add `pdf` dependency)

- [ ] **Step 1: Add `pdf` package to pubspec.yaml**

  In `pubspec.yaml`, under `dependencies:`, add:
  ```yaml
  pdf: ^3.11.1
  ```

  Run:
  ```bash
  flutter pub get
  ```

- [ ] **Step 2: Write the repository**

  ```dart
  import 'dart:convert';
  import 'dart:io';
  import 'package:path_provider/path_provider.dart';
  import 'package:pdf/pdf.dart';
  import 'package:pdf/widgets.dart' as pw;
  import 'package:supabase_flutter/supabase_flutter.dart';
  import '../models/performa.dart';
  import '../services/api_service.dart';

  class PerformaRepository {
    final ApiService _api;
    Performa? _cache;

    PerformaRepository(this._api);

    // ── CRUD ────────────────────────────────────────────────────────────────

    Future<Performa> fetch(String userId) async {
      final data = await _api.getPerforma(userId);
      if (data == null) return Performa(userId: userId);
      _cache = Performa.fromSupabaseRow(data);
      return _cache!;
    }

    Future<void> save(String userId, Performa performa) async {
      await _api.updatePerforma(userId, performa.toManualJson());
      _cache = performa;
    }

    Future<void> approveInsight(String userId, String insightId, bool approved) async {
      await _api.approvePerformaInsight(userId, insightId, approved);
      if (_cache != null) {
        final updated = _cache!.aiInsights.map((i) {
          if (i.id == insightId) return i.copyWith(approved: approved);
          return i;
        }).where((i) => approved || i.id != insightId).toList();
        _cache = _cache!.copyWith(aiInsights: updated);
      }
    }

    Future<List<Map<String, dynamic>>> fetchPendingInsights(String userId) async {
      return await _api.getPerformaPendingInsights(userId) ?? [];
    }

    // ── Export ───────────────────────────────────────────────────────────────

    Future<File> exportJson(Performa performa) async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/performa_${performa.userId}.json');
      final map = {
        ...performa.toManualJson(),
        'aiInsights': performa.aiInsights.where((i) => i.approved).map((i) => i.toJson()).toList(),
        'inferredStrengths': performa.inferredStrengths,
        'inferredWeaknesses': performa.inferredWeaknesses,
        'notablePatterns': performa.notablePatterns,
        'exportedAt': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(map));
      return file;
    }

    Future<File> exportMarkdown(Performa performa) async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/performa_${performa.userId}.md');
      final buf = StringBuffer();
      buf.writeln('# My Performa Profile\n');
      buf.writeln('## About Me');
      if (performa.fullName.isNotEmpty) buf.writeln('**Name:** ${performa.fullName}');
      if (performa.role.isNotEmpty) buf.writeln('**Role:** ${performa.role}${performa.company.isNotEmpty ? " at ${performa.company}" : ""}');
      if (performa.industry.isNotEmpty) buf.writeln('**Industry:** ${performa.industry}');
      if (performa.communicationStyle.isNotEmpty) buf.writeln('**Communication Style:** ${performa.communicationStyle}');
      if (performa.background.isNotEmpty) buf.writeln('\n${performa.background}');
      if (performa.goals.isNotEmpty) {
        buf.writeln('\n## Goals');
        for (final g in performa.goals) buf.writeln('- $g');
      }
      if (performa.conversationScenarios.isNotEmpty) {
        buf.writeln('\n## Conversation Scenarios');
        for (final s in performa.conversationScenarios) buf.writeln('- $s');
      }
      if (performa.recurringContacts.isNotEmpty) {
        buf.writeln('\n## Key People');
        for (final c in performa.recurringContacts) {
          buf.writeln('- **${c.name}** (${c.relationship})${c.notes.isNotEmpty ? ": ${c.notes}" : ""}');
        }
      }
      if (performa.customKeywords.isNotEmpty) {
        buf.writeln('\n## Watch Keywords');
        buf.writeln(performa.customKeywords.join(', '));
      }
      final approved = performa.aiInsights.where((i) => i.approved).toList();
      if (approved.isNotEmpty) {
        buf.writeln('\n## AI Insights');
        for (final i in approved) buf.writeln('- ${i.text}');
      }
      await file.writeAsString(buf.toString());
      return file;
    }

    Future<File> exportPdf(Performa performa) async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/performa_${performa.userId}.pdf');
      final pdf = pw.Document();

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.Header(level: 0, child: pw.Text('Performa Profile', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 16),
          _pdfSection(ctx, 'About Me', [
            if (performa.fullName.isNotEmpty) 'Name: ${performa.fullName}',
            if (performa.role.isNotEmpty) 'Role: ${performa.role}${performa.company.isNotEmpty ? " at ${performa.company}" : ""}',
            if (performa.industry.isNotEmpty) 'Industry: ${performa.industry}',
            if (performa.communicationStyle.isNotEmpty) 'Style: ${performa.communicationStyle}',
          ]),
          if (performa.goals.isNotEmpty) _pdfSection(ctx, 'Goals', performa.goals),
          if (performa.conversationScenarios.isNotEmpty) _pdfSection(ctx, 'Scenarios', performa.conversationScenarios),
          if (performa.recurringContacts.isNotEmpty) _pdfSection(ctx, 'Key People',
            performa.recurringContacts.map((c) => '${c.name} (${c.relationship})').toList()),
          if (performa.customKeywords.isNotEmpty) _pdfSection(ctx, 'Watch Keywords', [performa.customKeywords.join(', ')]),
          if (performa.background.isNotEmpty) _pdfSection(ctx, 'Background', [performa.background]),
          _pdfInsightsTable(performa.aiInsights.where((i) => i.approved).toList()),
        ],
      ));

      await file.writeAsBytes(await pdf.save());
      return file;
    }

    pw.Widget _pdfSection(pw.Context ctx, String title, List<String> items) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        ...items.map((i) => pw.Text('• $i', style: const pw.TextStyle(fontSize: 11))),
        pw.SizedBox(height: 12),
      ],
    );

    pw.Widget _pdfInsightsTable(List<PerformaInsight> insights) {
      if (insights.isEmpty) return pw.SizedBox();
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('AI Insights', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              pw.TableRow(children: [
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Insight', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Confidence', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
              ]),
              ...insights.map((i) => pw.TableRow(children: [
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(i.text, style: const pw.TextStyle(fontSize: 10))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${(i.confidence * 100).round()}%', style: const pw.TextStyle(fontSize: 10))),
              ])),
            ],
          ),
        ],
      );
    }
  }
  ```

- [ ] **Step 3: Commit**
  ```bash
  git add lib/repositories/performa_repository.dart pubspec.yaml pubspec.lock
  git commit -m "feat: PerformaRepository with CRUD and JSON/Markdown/PDF export"
  ```

---

### Task 13: PerformaProvider

**Files:**
- Create: `lib/providers/performa_provider.dart`

- [ ] **Step 1: Write the provider**

  ```dart
  import 'package:flutter/foundation.dart';
  import '../models/performa.dart';
  import '../repositories/performa_repository.dart';

  class PerformaProvider extends ChangeNotifier {
    final PerformaRepository _repo;

    Performa? _performa;
    bool _isLoading = false;
    String? _error;

    Performa? get performa => _performa;
    bool get isLoading => _isLoading;
    String? get error => _error;
    bool get hasPendingInsights => _performa?.pendingInsights.isNotEmpty ?? false;

    PerformaProvider(this._repo);

    Future<void> load(String userId) async {
      _isLoading = true;
      _error = null;
      notifyListeners();
      try {
        _performa = await _repo.fetch(userId);
      } catch (e) {
        _error = e.toString();
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    Future<void> save(String userId, Performa updated) async {
      await _repo.save(userId, updated);
      _performa = updated;
      notifyListeners();
    }

    Future<void> approveInsight(String userId, String insightId) async {
      await _repo.approveInsight(userId, insightId, true);
      notifyListeners();
    }

    Future<void> rejectInsight(String userId, String insightId) async {
      await _repo.approveInsight(userId, insightId, false);
      if (_performa != null) {
        final updated = _performa!.aiInsights.where((i) => i.id != insightId).toList();
        _performa = _performa!.copyWith(aiInsights: updated);
      }
      notifyListeners();
    }
  }
  ```

- [ ] **Step 2: Register `PerformaProvider` in the app's provider tree**

  Find where `MultiProvider` is declared (typically `lib/main.dart` or `lib/app.dart`). Add:
  ```dart
  ChangeNotifierProvider(
    create: (ctx) => PerformaProvider(
      PerformaRepository(ctx.read<ApiService>()),
    ),
  ),
  ```

- [ ] **Step 3: Commit**
  ```bash
  git add lib/providers/performa_provider.dart lib/main.dart
  git commit -m "feat: PerformaProvider"
  ```

---

### Task 14: Performa screen — 4 tabs

**Files:**
- Create: `lib/screens/performa_screen.dart`

- [ ] **Step 1: Write the screen**

  ```dart
  import 'package:flutter/material.dart';
  import 'package:provider/provider.dart';
  import 'package:share_plus/share_plus.dart';
  import '../models/performa.dart';
  import '../providers/performa_provider.dart';
  import '../services/api_service.dart';

  class PerformaScreen extends StatefulWidget {
    const PerformaScreen({super.key});

    @override
    State<PerformaScreen> createState() => _PerformaScreenState();
  }

  class _PerformaScreenState extends State<PerformaScreen>
      with SingleTickerProviderStateMixin {
    late TabController _tabs;

    @override
    void initState() {
      super.initState();
      _tabs = TabController(length: 4, vsync: this);
    }

    @override
    void dispose() {
      _tabs.dispose();
      super.dispose();
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Performa'),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'About'),
              Tab(text: 'People'),
              Tab(text: 'AI Insights'),
              Tab(text: 'Export'),
            ],
          ),
        ),
        body: Consumer<PerformaProvider>(
          builder: (ctx, prov, _) {
            if (prov.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final p = prov.performa ?? Performa(userId: '');
            return TabBarView(
              controller: _tabs,
              children: [
                _AboutTab(performa: p, onSave: (updated) => _save(ctx, updated)),
                _PeopleTab(performa: p, onSave: (updated) => _save(ctx, updated)),
                _InsightsTab(performa: p),
                _ExportTab(performa: p),
              ],
            );
          },
        ),
      );
    }

    Future<void> _save(BuildContext ctx, Performa updated) async {
      final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
      await ctx.read<PerformaProvider>().save(userId, updated);
    }
  }

  // ── Tab 1: About ─────────────────────────────────────────────────────────────

  class _AboutTab extends StatefulWidget {
    final Performa performa;
    final void Function(Performa) onSave;
    const _AboutTab({required this.performa, required this.onSave});
    @override
    State<_AboutTab> createState() => _AboutTabState();
  }

  class _AboutTabState extends State<_AboutTab> {
    late TextEditingController _name, _role, _industry, _company, _bg;
    String _style = '';
    late List<String> _goals, _scenarios, _languages;

    @override
    void initState() {
      super.initState();
      final p = widget.performa;
      _name = TextEditingController(text: p.fullName);
      _role = TextEditingController(text: p.role);
      _industry = TextEditingController(text: p.industry);
      _company = TextEditingController(text: p.company);
      _bg = TextEditingController(text: p.background);
      _style = p.communicationStyle;
      _goals = List.from(p.goals);
      _scenarios = List.from(p.conversationScenarios);
      _languages = List.from(p.languages);
    }

    @override
    void dispose() {
      _name.dispose(); _role.dispose(); _industry.dispose();
      _company.dispose(); _bg.dispose();
      super.dispose();
    }

    Performa _build() => widget.performa.copyWith(
      fullName: _name.text.trim(),
      role: _role.text.trim(),
      industry: _industry.text.trim(),
      company: _company.text.trim(),
      background: _bg.text.trim(),
      communicationStyle: _style,
      goals: _goals,
      conversationScenarios: _scenarios,
      languages: _languages,
    );

    @override
    Widget build(BuildContext context) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _field(_name, 'Full name'),
          _field(_role, 'Role / Title'),
          _field(_industry, 'Industry'),
          _field(_company, 'Company'),
          const SizedBox(height: 8),
          _styleDropdown(),
          const SizedBox(height: 16),
          _chipSection('Goals', _goals, (v) => setState(() => _goals = v)),
          _chipSection('Scenarios', _scenarios, (v) => setState(() => _scenarios = v)),
          _chipSection('Languages', _languages, (v) => setState(() => _languages = v)),
          const SizedBox(height: 8),
          TextField(
            controller: _bg,
            decoration: const InputDecoration(labelText: 'Background (free text)'),
            maxLines: 4,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => widget.onSave(_build()),
            child: const Text('Save'),
          ),
        ]),
      );
    }

    Widget _field(TextEditingController c, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(controller: c, decoration: InputDecoration(labelText: label)),
    );

    Widget _styleDropdown() => DropdownButtonFormField<String>(
      value: _style.isEmpty ? null : _style,
      decoration: const InputDecoration(labelText: 'Communication Style'),
      items: ['direct', 'diplomatic', 'analytical']
          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
          .toList(),
      onChanged: (v) => setState(() => _style = v ?? ''),
    );

    Widget _chipSection(String label, List<String> items, void Function(List<String>) onChanged) {
      final controller = TextEditingController();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        Wrap(
          spacing: 8,
          children: [
            ...items.map((s) => Chip(
              label: Text(s),
              onDeleted: () => onChanged(items.where((x) => x != s).toList()),
            )),
            ActionChip(
              label: const Text('+'),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text('Add $label'),
                  content: TextField(controller: controller, autofocus: true),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    FilledButton(
                      onPressed: () {
                        final v = controller.text.trim();
                        if (v.isNotEmpty) onChanged([...items, v]);
                        Navigator.pop(context);
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ]);
    }
  }

  // ── Tab 2: People ─────────────────────────────────────────────────────────────

  class _PeopleTab extends StatefulWidget {
    final Performa performa;
    final void Function(Performa) onSave;
    const _PeopleTab({required this.performa, required this.onSave});
    @override
    State<_PeopleTab> createState() => _PeopleTabState();
  }

  class _PeopleTabState extends State<_PeopleTab> {
    late List<PerformaContact> _contacts;
    late List<String> _keywords;

    @override
    void initState() {
      super.initState();
      _contacts = List.from(widget.performa.recurringContacts);
      _keywords = List.from(widget.performa.customKeywords);
    }

    @override
    Widget build(BuildContext context) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Key People', style: Theme.of(context).textTheme.titleMedium),
            IconButton(icon: const Icon(Icons.person_add), onPressed: _addContact),
          ]),
          ..._contacts.asMap().entries.map((e) => _contactCard(e.key, e.value)),
          const Divider(height: 32),
          Text('Watch Keywords', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ..._keywords.map((k) => Chip(
                label: Text(k),
                onDeleted: () => setState(() {
                  _keywords.remove(k);
                  _save();
                }),
              )),
              ActionChip(
                label: const Text('+'),
                onPressed: _addKeyword,
              ),
            ],
          ),
        ]),
      );
    }

    Widget _contactCard(int idx, PerformaContact c) => Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(c.name),
        subtitle: Text('${c.relationship}${c.notes.isNotEmpty ? " · ${c.notes}" : ""}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editContact(idx, c)),
          IconButton(icon: const Icon(Icons.delete, size: 18), onPressed: () => setState(() {
            _contacts.removeAt(idx);
            _save();
          })),
        ]),
      ),
    );

    void _addContact() => _editContact(null, null);

    void _editContact(int? idx, PerformaContact? existing) {
      final namec = TextEditingController(text: existing?.name ?? '');
      final relc = TextEditingController(text: existing?.relationship ?? '');
      final notec = TextEditingController(text: existing?.notes ?? '');
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(existing == null ? 'Add Contact' : 'Edit Contact'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: namec, decoration: const InputDecoration(labelText: 'Name'), autofocus: true),
            TextField(controller: relc, decoration: const InputDecoration(labelText: 'Relationship')),
            TextField(controller: notec, decoration: const InputDecoration(labelText: 'Notes')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final contact = PerformaContact(
                  name: namec.text.trim(),
                  relationship: relc.text.trim(),
                  notes: notec.text.trim(),
                );
                setState(() {
                  if (idx != null) _contacts[idx] = contact;
                  else _contacts.add(contact);
                });
                _save();
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    }

    void _addKeyword() {
      final c = TextEditingController();
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Add Keyword'),
          content: TextField(controller: c, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final v = c.text.trim();
                if (v.isNotEmpty) setState(() { _keywords.add(v); _save(); });
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      );
    }

    void _save() => widget.onSave(widget.performa.copyWith(
      recurringContacts: _contacts,
      customKeywords: _keywords,
    ));
  }

  // ── Tab 3: AI Insights ────────────────────────────────────────────────────────

  class _InsightsTab extends StatelessWidget {
    final Performa performa;
    const _InsightsTab({required this.performa});

    @override
    Widget build(BuildContext context) {
      final insights = performa.aiInsights.where((i) => i.approved).toList();
      if (insights.isEmpty) {
        return const Center(child: Text('No AI insights yet. Complete a few sessions to see patterns.'));
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: insights.length,
        itemBuilder: (ctx, i) {
          final insight = insights[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(insight.text, style: Theme.of(ctx).textTheme.bodyMedium),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: insight.confidence, minHeight: 3),
                const SizedBox(height: 4),
                Text('${(insight.confidence * 100).round()}% confidence',
                    style: Theme.of(ctx).textTheme.labelSmall),
              ]),
            ),
          );
        },
      );
    }
  }

  // ── Tab 4: Export ─────────────────────────────────────────────────────────────

  class _ExportTab extends StatelessWidget {
    final Performa performa;
    const _ExportTab({required this.performa});

    @override
    Widget build(BuildContext context) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Export your Performa profile', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 24),
          _exportButton(context, Icons.code, 'Export JSON', _doJson),
          const SizedBox(height: 12),
          _exportButton(context, Icons.description, 'Export Markdown', _doMarkdown),
          const SizedBox(height: 12),
          _exportButton(context, Icons.picture_as_pdf, 'Export PDF', _doPdf),
        ]),
      );
    }

    Widget _exportButton(BuildContext ctx, IconData icon, String label,
        Future<void> Function(BuildContext) action) => FilledButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: () => action(ctx),
      style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
    );

    Future<void> _doJson(BuildContext ctx) async {
      try {
        final repo = ctx.read<PerformaRepository>();
        final file = await repo.exportJson(performa);
        await ShareXFiles([XFile(file.path)]);
      } catch (e) {
        _showError(ctx, e);
      }
    }

    Future<void> _doMarkdown(BuildContext ctx) async {
      try {
        final repo = ctx.read<PerformaRepository>();
        final file = await repo.exportMarkdown(performa);
        await ShareXFiles([XFile(file.path)]);
      } catch (e) {
        _showError(ctx, e);
      }
    }

    Future<void> _doPdf(BuildContext ctx) async {
      try {
        final repo = ctx.read<PerformaRepository>();
        final file = await repo.exportPdf(performa);
        await ShareXFiles([XFile(file.path)]);
      } catch (e) {
        _showError(ctx, e);
      }
    }

    void _showError(BuildContext ctx, Object e) =>
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
  ```

  Note: `PerformaRepository` needs to be accessible via `context.read<PerformaRepository>()`. Register it in the provider tree alongside `PerformaProvider` in Task 13:
  ```dart
  Provider(create: (ctx) => PerformaRepository(ctx.read<ApiService>())),
  ```

- [ ] **Step 2: Add API methods for performa to `api_service.dart`**

  In `lib/services/api_service.dart`, add:
  ```dart
  Future<Map<String, dynamic>?> getPerforma(String userId) async {
    try {
      final uri = Uri.parse("$_baseUrl/v1/performa/$userId");
      final response = await http.get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) { debugPrint("getPerforma error: $e"); }
    return null;
  }

  Future<void> updatePerforma(String userId, Map<String, dynamic> manualData) async {
    try {
      final uri = Uri.parse("$_baseUrl/v1/performa/$userId");
      await http.put(uri, headers: await _authHeaders(),
          body: jsonEncode({"user_id": userId, "manual_data": manualData}))
          .timeout(const Duration(seconds: 10));
    } catch (e) { debugPrint("updatePerforma error: $e"); }
  }

  Future<List<Map<String, dynamic>>?> getPerformaPendingInsights(String userId) async {
    try {
      final uri = Uri.parse("$_baseUrl/v1/performa/$userId/pending_insights");
      final response = await http.get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['insights'] as List).cast<Map<String, dynamic>>();
      }
    } catch (e) { debugPrint("getPendingInsights error: $e"); }
    return null;
  }

  Future<void> approvePerformaInsight(String userId, String insightId, bool approved) async {
    try {
      final uri = Uri.parse("$_baseUrl/v1/performa/$userId/approve_insight");
      await http.post(uri, headers: await _authHeaders(),
          body: jsonEncode({"user_id": userId, "insight_id": insightId, "approved": approved}))
          .timeout(const Duration(seconds: 10));
    } catch (e) { debugPrint("approveInsight error: $e"); }
  }
  ```

- [ ] **Step 3: Commit**
  ```bash
  git add lib/screens/performa_screen.dart lib/services/api_service.dart
  git commit -m "feat: Performa screen with 4 tabs (About, People, AI Insights, Export)"
  ```

---

### Task 15: Approval card bottom sheet

**Files:**
- Create: `lib/widgets/performa_approval_sheet.dart`

- [ ] **Step 1: Write the bottom sheet widget**

  ```dart
  import 'package:flutter/material.dart';
  import 'package:provider/provider.dart';
  import 'package:supabase_flutter/supabase_flutter.dart';
  import '../models/performa.dart';
  import '../providers/performa_provider.dart';

  class PerformaApprovalSheet extends StatelessWidget {
    final List<PerformaInsight> insights;
    const PerformaApprovalSheet({super.key, required this.insights});

    static Future<void> showIfNeeded(BuildContext context) async {
      final prov = context.read<PerformaProvider>();
      final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
      if (userId.isEmpty) return;

      await prov.load(userId);
      final pending = prov.performa?.pendingInsights ?? [];
      if (pending.isEmpty) return;

      if (context.mounted) {
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => PerformaApprovalSheet(insights: pending),
        );
      }
    }

    @override
    Widget build(BuildContext context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 16),
            Text('We learned a few things about you',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Approve or dismiss each insight',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                controller: scroll,
                itemCount: insights.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _InsightRow(insight: insights[i]),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              child: const Text('Done'),
            ),
          ]),
        ),
      );
    }
  }

  class _InsightRow extends StatelessWidget {
    final PerformaInsight insight;
    const _InsightRow({required this.insight});

    @override
    Widget build(BuildContext context) {
      final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(child: Text(insight.text, style: Theme.of(context).textTheme.bodyMedium)),
            IconButton(
              icon: const Icon(Icons.check_circle_outline, color: Colors.green),
              onPressed: () => context.read<PerformaProvider>().approveInsight(userId, insight.id),
            ),
            IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Colors.red),
              onPressed: () => context.read<PerformaProvider>().rejectInsight(userId, insight.id),
            ),
          ]),
        ),
      );
    }
  }
  ```

- [ ] **Step 2: Call `PerformaApprovalSheet.showIfNeeded` on app open**

  Find the home screen or root widget that runs after login (e.g. `lib/screens/home_screen.dart` or similar). In `initState` (or `didChangeDependencies`), after the user is confirmed logged in:
  ```dart
  WidgetsBinding.instance.addPostFrameCallback((_) {
    PerformaApprovalSheet.showIfNeeded(context);
  });
  ```

- [ ] **Step 3: Commit**
  ```bash
  git add lib/widgets/performa_approval_sheet.dart
  git commit -m "feat: Performa approval card bottom sheet with accept/reject per insight"
  ```

---

## Phase 5 — Flutter UI

### Task 16: Extract TeleprompterPanel with drag/snap

**Files:**
- Create: `lib/widgets/teleprompter_panel.dart`
- Modify: `lib/screens/new_session_screen.dart` (remove old `_TeleprompterPanel`, replace with import)

- [ ] **Step 1: Write `teleprompter_panel.dart`**

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_animate/flutter_animate.dart';

  class TeleprompterPanel extends StatefulWidget {
    final List<String> hints;
    final double initialHeightFraction;
    final bool hasUncertainSpeaker;
    final VoidCallback? onClose;

    const TeleprompterPanel({
      super.key,
      required this.hints,
      this.initialHeightFraction = 0.38,
      this.hasUncertainSpeaker = false,
      this.onClose,
    });

    @override
    State<TeleprompterPanel> createState() => _TeleprompterPanelState();
  }

  enum _PanelSnap { compact, normal, expanded }

  class _TeleprompterPanelState extends State<TeleprompterPanel> {
    static const _snaps = {
      _PanelSnap.compact: 0.22,
      _PanelSnap.normal: 0.38,
      _PanelSnap.expanded: 0.68,
    };

    _PanelSnap _snap = _PanelSnap.normal;
    double _dragStartFraction = 0.38;
    double _currentFraction = 0.38;
    final ScrollController _scroll = ScrollController();
    bool _userScrolled = false;

    @override
    void initState() {
      super.initState();
      _currentFraction = widget.initialHeightFraction;
      _snap = _snapForFraction(_currentFraction);
      _scroll.addListener(() {
        if (_scroll.hasClients) {
          final atBottom = _scroll.offset >= _scroll.position.maxScrollExtent - 16;
          if (!atBottom && !_userScrolled) setState(() => _userScrolled = true);
          if (atBottom && _userScrolled) setState(() => _userScrolled = false);
        }
      });
    }

    @override
    void didUpdateWidget(TeleprompterPanel old) {
      super.didUpdateWidget(old);
      if (widget.hints.length > old.hints.length && !_userScrolled && _snap != _PanelSnap.compact) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(_scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });
      }
    }

    @override
    void dispose() {
      _scroll.dispose();
      super.dispose();
    }

    _PanelSnap _snapForFraction(double f) {
      if (f < 0.28) return _PanelSnap.compact;
      if (f < 0.52) return _PanelSnap.normal;
      return _PanelSnap.expanded;
    }

    void _cycleSnap() {
      setState(() {
        switch (_snap) {
          case _PanelSnap.compact: _snap = _PanelSnap.normal; break;
          case _PanelSnap.normal: _snap = _PanelSnap.expanded; break;
          case _PanelSnap.expanded: _snap = _PanelSnap.compact; break;
        }
        _currentFraction = _snaps[_snap]!;
      });
    }

    void _onDragStart(DragStartDetails d) {
      _dragStartFraction = _currentFraction;
    }

    void _onDragUpdate(DragUpdateDetails d) {
      final screenH = MediaQuery.of(context).size.height;
      setState(() {
        _currentFraction = (_currentFraction - d.delta.dy / screenH).clamp(0.18, 0.75);
      });
    }

    void _onDragEnd(DragEndDetails d) {
      final velocity = d.primaryVelocity ?? 0;
      _PanelSnap target;
      if (velocity < -300) {
        // fast flick up → expand
        target = _snap == _PanelSnap.compact ? _PanelSnap.normal : _PanelSnap.expanded;
      } else if (velocity > 300) {
        // fast flick down → compact
        target = _snap == _PanelSnap.expanded ? _PanelSnap.normal : _PanelSnap.compact;
      } else {
        target = _snapForFraction(_currentFraction);
      }
      setState(() {
        _snap = target;
        _currentFraction = _snaps[target]!;
      });
    }

    @override
    Widget build(BuildContext context) {
      final screenH = MediaQuery.of(context).size.height;
      final scheme = Theme.of(context).colorScheme;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final panelH = screenH * _currentFraction;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: panelH,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withAlpha(180)
              : Colors.white.withAlpha(230),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: scheme.primary.withAlpha(60)),
          boxShadow: [BoxShadow(color: scheme.primary.withAlpha(30), blurRadius: 20, spreadRadius: 2)],
        ),
        child: Column(children: [
          _header(scheme),
          Expanded(child: _snap == _PanelSnap.compact ? _compactBody() : _scrollBody(isDark, scheme)),
        ]),
      );
    }

    Widget _header(ColorScheme scheme) {
      return GestureDetector(
        onDoubleTap: _cycleSnap,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            // Hint count
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${widget.hints.length} hints',
                  style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w600)),
            ),
            const Spacer(),
            // Drag pill (center)
            Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
            const Spacer(),
            // Uncertain speaker dot
            if (widget.hasUncertainSpeaker)
              Container(
                width: 8, height: 8, margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
              ).animate(onPlay: (c) => c.repeat()).shimmer(duration: const Duration(seconds: 1)),
            // Expand/collapse button
            GestureDetector(
              onTap: _cycleSnap,
              child: Icon(
                _snap == _PanelSnap.expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                size: 20, color: scheme.onSurface.withAlpha(150),
              ),
            ),
          ]),
        ),
      );
    }

    Widget _compactBody() {
      // Compact: only latest hint, no scroll
      if (widget.hints.isEmpty) {
        return const Center(child: Text('Listening...', style: TextStyle(color: Colors.grey)));
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(widget.hints.last,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
            maxLines: 3, overflow: TextOverflow.ellipsis),
      );
    }

    Widget _scrollBody(bool isDark, ColorScheme scheme) {
      if (widget.hints.isEmpty) {
        return const Center(child: Text('Listening...', style: TextStyle(color: Colors.grey)));
      }
      return Stack(children: [
        ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          itemCount: widget.hints.length,
          itemBuilder: (ctx, i) {
            final isLatest = i == widget.hints.length - 1;
            return _HintEntry(
              hint: widget.hints[i],
              index: i + 1,
              isLatest: isLatest,
              isDark: isDark,
              scheme: scheme,
            );
          },
        ),
        if (_userScrolled)
          Positioned(
            bottom: 8, right: 12,
            child: FilledButton.icon(
              onPressed: () {
                setState(() => _userScrolled = false);
                _scroll.animateTo(_scroll.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
              },
              icon: const Icon(Icons.arrow_downward, size: 14),
              label: const Text('Latest', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
      ]);
    }
  }

  class _HintEntry extends StatelessWidget {
    final String hint;
    final int index;
    final bool isLatest;
    final bool isDark;
    final ColorScheme scheme;

    const _HintEntry({
      required this.hint,
      required this.index,
      required this.isLatest,
      required this.isDark,
      required this.scheme,
    });

    @override
    Widget build(BuildContext context) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Sequence dot
          Container(
            width: 20, height: 20, margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLatest ? scheme.primary : scheme.primary.withAlpha(50),
            ),
            child: Center(child: Text('$index',
              style: TextStyle(fontSize: 10, color: isLatest ? Colors.white : scheme.primary,
                  fontWeight: FontWeight.bold))),
          ),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isLatest
                    ? (isDark ? scheme.primary.withAlpha(30) : scheme.primary.withAlpha(15))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isLatest ? Border(left: BorderSide(color: scheme.primary, width: 2)) : null,
              ),
              child: Opacity(
                opacity: isLatest ? 1.0 : 0.75,
                child: Text(hint,
                    style: TextStyle(
                      fontSize: isLatest ? 14.5 : 13,
                      height: 1.4,
                    )),
              ),
            ),
          ),
        ]),
      ).animate().slideY(begin: 0.3, end: 0, duration: 250.ms).fadeIn(duration: 250.ms);
    }
  }
  ```

- [ ] **Step 2: Replace `_TeleprompterPanel` usage in `new_session_screen.dart`**

  At the top of `new_session_screen.dart`, add:
  ```dart
  import '../widgets/teleprompter_panel.dart';
  ```

  Find the `_TeleprompterPanel(...)` widget instantiation (search for `_TeleprompterPanel`) and replace with:
  ```dart
  TeleprompterPanel(
    hints: sessionProvider.adviceHistory,
    hasUncertainSpeaker: _hasUncertainSpeaker(sessionProvider),
  )
  ```

  Add the helper method to `_NewSessionScreenState`:
  ```dart
  bool _hasUncertainSpeaker(SessionProvider sp) {
    if (sp.sessionLogs.isEmpty) return false;
    final last = sp.sessionLogs.last;
    return last['isUncertain'] == true;
  }
  ```

  Delete the old `_TeleprompterPanel`, `_TeleprompterPanelState`, and `_TeleprompterEntry` class definitions from `new_session_screen.dart`.

- [ ] **Step 3: Expose `sessionLogs` getter in SessionProvider if not already public**

  In `session_provider.dart`, ensure:
  ```dart
  List<Map<String, dynamic>> get sessionLogs => List.unmodifiable(_sessionLogs);
  ```

- [ ] **Step 4: Commit**
  ```bash
  git add lib/widgets/teleprompter_panel.dart lib/screens/new_session_screen.dart lib/providers/session_provider.dart
  git commit -m "feat: extract TeleprompterPanel with 3-snap drag handle and double-tap"
  ```

---

### Task 17: Session screen — speaker confidence UI + manual override

**Files:**
- Modify: `lib/screens/new_session_screen.dart`

- [ ] **Step 1: Update chat bubble rendering to show confidence state**

  Find the chat bubble list builder (around line 855–875). The current code:
  ```dart
  bool isMe = msg['speaker'] == "User";
  ```

  Extend to extract uncertainty:
  ```dart
  final bool isMe = msg['speaker'] == "User";
  final bool isUncertain = msg['isUncertain'] == true;
  final String speakerLabel = isUncertain
      ? (isMe ? "You?" : "Them?")
      : (isMe ? "You" : "Them");
  ```

  Pass to `ChatBubble` widget:
  ```dart
  ChatBubble(
    isUser: isMe,
    speakerLabel: speakerLabel,
    isUncertain: isUncertain,
    onAttributionChange: (asMe) => _reattribute(context, index, asMe, sessionProvider, api),
    // ...existing params
  )
  ```

- [ ] **Step 2: Update `ChatBubble` widget to accept uncertainty props**

  Find `lib/widgets/chat_bubble.dart`. Add parameters:
  ```dart
  final bool isUncertain;
  final void Function(bool asMe)? onAttributionChange;
  ```

  In the bubble build method, add the `?` badge when `isUncertain`:
  ```dart
  if (isUncertain && onAttributionChange != null)
    Positioned(
      top: 0,
      right: isUser ? null : 0,
      left: isUser ? 0 : null,
      child: GestureDetector(
        onTap: () => _showAttributionRow(context),
        child: Container(
          width: 18, height: 18,
          decoration: BoxDecoration(
            color: Colors.amber.shade700,
            shape: BoxShape.circle,
          ),
          child: const Center(child: Text('?', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold))),
        ),
      ),
    ),
  ```

  And the attribution row (shown on `?` tap):
  ```dart
  void _showAttributionRow(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton.icon(
              icon: const Icon(Icons.person),
              label: const Text('This was me'),
              onPressed: () { Navigator.pop(context); onAttributionChange!(true); },
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.people),
              label: const Text('This was them'),
              onPressed: () { Navigator.pop(context); onAttributionChange!(false); },
            ),
          ]),
        ),
      ),
    );
  }
  ```

  Apply 60% opacity to the bubble container when `isUncertain`:
  ```dart
  Opacity(
    opacity: isUncertain ? 0.6 : 1.0,
    child: /* existing bubble container */,
  )
  ```

- [ ] **Step 3: Add long-press context menu for all bubbles**

  Wrap the `ChatBubble` (or its outer container) in a `GestureDetector`:
  ```dart
  GestureDetector(
    onLongPress: () => _showSwitchMenu(context, index, isMe, sessionProvider, api),
    child: ChatBubble(...),
  )
  ```

  Add `_showSwitchMenu` method in `_NewSessionScreenState`:
  ```dart
  void _showSwitchMenu(BuildContext ctx, int idx, bool currentIsMe,
      SessionProvider sp, ApiService api) {
    showModalBottomSheet(
      context: ctx,
      builder: (_) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: const Text('Switch speaker'),
          onTap: () {
            Navigator.pop(ctx);
            _reattribute(ctx, idx, !currentIsMe, sp, api);
          },
        ),
      ),
    );
  }
  ```

- [ ] **Step 4: Implement `_reattribute` helper**

  ```dart
  void _reattribute(BuildContext ctx, int idx, bool asMe,
      SessionProvider sp, ApiService api) {
    sp.reattributeTurn(idx, asMe ? "User" : "Other", api);
  }
  ```

  Add `reattributeTurn` to `SessionProvider`:
  ```dart
  void reattributeTurn(int idx, String newSpeaker, ApiService api) {
    if (idx < 0 || idx >= _sessionLogs.length) return;
    _sessionLogs[idx] = {
      ..._sessionLogs[idx],
      'speaker': newSpeaker,
      'isUncertain': false,
    };
    notifyListeners();
    // Re-trigger wingman if newly attributed to Other
    if (newSpeaker == "Other" && !_wingmanInFlight) {
      _askWingman(_sessionLogs[idx]['text'] as String, api);
    }
  }
  ```

- [ ] **Step 5: Update "Swap all speakers" button tooltip**

  Find the existing swap button in `new_session_screen.dart`. Wrap it in a `Tooltip`:
  ```dart
  Tooltip(
    message: 'Flips all past messages',
    child: /* existing swap button */,
  )
  ```

- [ ] **Step 6: Commit**
  ```bash
  git add lib/screens/new_session_screen.dart lib/widgets/chat_bubble.dart lib/providers/session_provider.dart
  git commit -m "feat: speaker confidence badges, manual override, You/Them labels"
  ```

---

### Task 18: Wire entry points

**Files:**
- Modify: `lib/screens/new_session_screen.dart` (or wherever the session app bar lives)
- Modify: root/home screen (wherever post-login init happens)

- [ ] **Step 1: Add Performa icon to session app bar**

  In `new_session_screen.dart`, find the `AppBar` actions list. Add:
  ```dart
  IconButton(
    icon: const Icon(Icons.person_outline),
    tooltip: 'Performa',
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PerformaScreen()),
    ),
  ),
  ```

  Add import at top:
  ```dart
  import 'performa_screen.dart';
  ```

- [ ] **Step 2: Load Performa at session start for context**

  In `new_session_screen.dart` or wherever `startSession` is called, also load performa:
  ```dart
  final userId = AuthService.instance.currentUser?.id ?? '';
  context.read<PerformaProvider>().load(userId);
  ```

- [ ] **Step 3: Show approval card on home screen open**

  In the home screen `initState` (or first screen shown after auth), add:
  ```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerformaApprovalSheet.showIfNeeded(context);
    });
  }
  ```

  Add import:
  ```dart
  import '../widgets/performa_approval_sheet.dart';
  ```

- [ ] **Step 4: Final check — run `flutter analyze`**

  ```bash
  flutter analyze lib/
  ```
  Fix any errors (unused imports, missing required params, type mismatches).

- [ ] **Step 5: Commit**
  ```bash
  git add lib/screens/new_session_screen.dart
  git commit -m "feat: Performa entry point in session bar, approval card on home open"
  ```

---

## Self-Review

**Spec coverage:**
- ✅ Bug fixes — Task 1
- ✅ Sub-500ms pipeline — Tasks 1, 4, 5, 6
- ✅ Session pre-cache — Tasks 4, 5
- ✅ Confidence threshold (0.75) + gating — Tasks 2, 3
- ✅ Manual override (tap `?` badge + long-press) — Task 17
- ✅ Uncertain bubble UI (`You?`/`Them?`, 60% opacity) — Task 17
- ✅ Swap all speakers tooltip — Task 17
- ✅ Teleprompter 3-snap + drag handle + double-tap — Task 16
- ✅ Compact shows latest only — Task 16
- ✅ `_adviceHistory` capped at 20 — Task 3
- ✅ `hasUncertainSpeaker` amber dot on teleprompter header — Task 16
- ✅ Performa DB migration — Task 7
- ✅ Performa CRUD backend — Tasks 8, 9
- ✅ Performa context injection into wingman — Task 10
- ✅ Post-session AI insight analysis — Task 10
- ✅ Performa model — Task 11
- ✅ PerformaRepository + export (JSON, Markdown, PDF) — Task 12
- ✅ PerformaProvider — Task 13
- ✅ Performa screen 4 tabs — Task 14
- ✅ Approval card bottom sheet — Task 15
- ✅ Entry point (profile icon → screen, approval on home open) — Task 18
