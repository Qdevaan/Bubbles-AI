# Supabase-First Data Layer — Design Spec
_2026-04-27 · Bubbles-AI Performance Optimization, Sub-project A_

## Goal

Eliminate Flutter→FastAPI reads for data-at-rest. FastAPI becomes a write+compute service only. Flutter reads all persisted data directly from Supabase, with Realtime subscriptions for volatile tables and auto-hydration on server reconnect.

---

## Data Flow Architecture

### Write + Compute (FastAPI — unchanged)
- Live session STT → LLM pipeline
- Consultant Q&A streaming
- Entity extraction post-session
- NetworkX graph computation
- Vector / RAG search

### Read (Supabase direct — new)
- Sessions list + summaries
- Entities + relationships
- Gamification profile / XP / leaderboard
- Profile + user settings
- Insights / key points
- Home feed data

### Realtime (Supabase → Flutter, 3 tables)
- `entities` filtered by `user_id` → invalidate GraphRepository cache → refetch
- `gamification_profiles` filtered by `user_id` → push XP/level directly into GamificationProvider
- `sessions` filtered by `user_id` → invalidate SessionsRepository cache → append

### Auth
RLS is disabled. All Flutter Supabase queries use the anon key with no RLS filtering. Server uses service-role key (unchanged).

---

## Repository Migration

| Repository | Current source | Action |
|---|---|---|
| `SessionsRepository` | Supabase ✓ | None — already correct |
| `GamificationRepository` | Supabase ✓ | Add Realtime subscription |
| `ProfileRepository` | Supabase (assumed) | Verify + add to hydration list |
| `SettingsRepository` | Supabase (assumed) | Verify + add to hydration list |
| `InsightsRepository` | FastAPI `/session_analytics` | **Migrate** → query `session_logs` + `sessions` |
| `GraphRepository` | FastAPI `/graph_export` | **Migrate** → query `entities` + relationships table |
| `HomeRepository` | FastAPI (composite) | **Migrate** → composite Supabase query |

---

## Schema Gaps

Before the Flutter read migration can land, verify these server-side write paths:

### Entity relationships
- `graph_service.py` builds NetworkX graph from entities.
- If relationships are not persisted, add an `entity_relationships` table and upsert triples `{source_entity_id, target_entity_id, relation}` in `entity_service` after extraction.
- `GraphRepository` then queries this table directly instead of calling `/graph_export`.

### Session insights / key points
- `brain_service.extract_highlights()` returns key points.
- Confirm `session_service.save_session()` inserts them into a persistent table (`session_insights` or `session_logs` with a `type` column).
- If not persisted, add the insert. `InsightsRepository` reads from this table.

### Session summaries
- `sessions.summary` column — assumed already populated by `save_session`. Verify.

---

## HydrationService (new file: `lib/services/hydration_service.dart`)

A lightweight singleton that holds references to all 7 repositories and calls `fetch(forceRefresh: true)` on all of them in parallel.

```dart
class HydrationService {
  Future<void> refreshAll() async {
    await Future.wait([
      _sessionsRepo.fetch(forceRefresh: true),
      _gamificationRepo.fetch(forceRefresh: true),
      _graphRepo.fetch(forceRefresh: true),
      _insightsRepo.fetch(forceRefresh: true),
      _homeRepo.fetch(forceRefresh: true),
      _profileRepo.fetch(forceRefresh: true),
      _settingsRepo.fetch(forceRefresh: true),
    ]);
  }
}
```

Wired in `main.dart`:
```dart
connectionService.addListener(() {
  if (connectionService.status == ConnectionStatus.connected) {
    hydrationService.refreshAll();
  }
});
```

---

## Realtime Subscription Pattern

Applied to the 3 volatile tables. Same pattern for each:

```dart
supabase
  .from('entities')
  .stream(primaryKey: ['id'])
  .eq('user_id', userId)
  .listen((_) {
    _graphRepo.invalidateCache();
    _graphRepo.fetch();
  });
```

Subscriptions initialized once in `HydrationService.init()` after first successful auth.

---

## Cache Strategy

Uses the existing L1 (in-memory) + L2 (persistent) cache infrastructure in `lib/cache/`.

| Scenario | Behavior |
|---|---|
| Cold start | L2 served immediately (no blank screens) |
| `refreshAll()` fires | Runs in background, updates L1+L2 silently |
| Realtime event | Invalidate cache key → background refetch |
| App resumes from background | `fetch_policy` stale-while-revalidate decides |
| Server reconnect | `HydrationService.refreshAll()` triggered |

---

## What Does NOT Change

- Live session processing (latency-critical, stays FastAPI)
- Consultant Q&A streaming (stays FastAPI)
- Graph computation (NetworkX, stays FastAPI) — only the *result* is cached, not the computation path. GraphRepository reads the persisted entity+relationship tables instead of calling `/graph_export`.
- All server write paths (no changes to FastAPI services)

---

## Files Changed

**New:**
- `lib/services/hydration_service.dart`

**Modified (Flutter):**
- `lib/repositories/insights_repository.dart` — swap FastAPI call for Supabase query
- `lib/repositories/graph_repository.dart` — swap `/graph_export` for Supabase entity+relationship query
- `lib/repositories/home_repository.dart` — swap FastAPI composite call for Supabase query
- `lib/repositories/gamification_repository.dart` — add Realtime subscription
- `lib/main.dart` — wire `ConnectionService` → `HydrationService`

**Modified (Server — only if schema gaps confirmed):**
- `server_v2/app/services/session_service.py` — add `session_insights` insert in `save_session`
- `server_v2/app/services/entity_service.py` — add `entity_relationships` upsert
- `Documentation/db_schema_final_v2.sql` — add `entity_relationships` and/or `session_insights` tables if missing
