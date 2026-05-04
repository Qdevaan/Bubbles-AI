# Live Session Overhaul + Performa Profile — Design Spec
**Date:** 2026-05-04  
**Status:** Approved

---

## Overview

Two tightly related initiatives:

1. **Live Session Overhaul** — fix blocking speaker detection bugs, hit sub-500ms wingman response target, redesign teleprompter panel to be resizable, add confidence-gated speaker attribution with manual override.
2. **Performa Profile** — new feature giving users a rich AI-aware context document about themselves. AI reads it during live sessions and auto-extends it after sessions. Users can view, edit, and export.

---

## 1. Architecture

### Files Modified

| File | Change |
|------|--------|
| `lib/screens/new_session_screen.dart` | Remove `_TeleprompterPanel` widget (extracted), add drag state wiring, speaker confidence UI, manual override taps |
| `lib/providers/session_provider.dart` | Fix speaker case bugs, accept confidence param, add confidence gating, lower timeouts |
| `lib/services/deepgram_service.dart` | Expose `confidence` per transcript callback, fix speaker string casing to lowercase |
| `server_v2/app/routes/sessions.py` | Load performa context in `start_session` pre-cache alongside graph/vector; 200ms hard timeout on cache miss |
| `server_v2/app/services/brain_service.py` | Inject `ABOUT YOU` performa block into wingman system prompt (80 token budget) |

### New Flutter Files

| File | Purpose |
|------|---------|
| `lib/widgets/teleprompter_panel.dart` | Extracted, fully self-contained resizable teleprompter widget |
| `lib/screens/performa_screen.dart` | 4-tab Performa profile screen (About / People / AI Insights / Export) |
| `lib/models/performa.dart` | Performa + PerformaContact + PerformaInsight data models |
| `lib/providers/performa_provider.dart` | State management (load, update, approve/reject insights) |
| `lib/repositories/performa_repository.dart` | Supabase CRUD + PDF/JSON/Markdown export logic |

### New Backend Files

| File | Purpose |
|------|---------|
| `server_v2/app/routes/performa.py` | CRUD endpoints: GET/PUT performa, GET pending insights, POST approve/reject |
| `server_v2/app/services/performa_service.py` | Post-session AI analysis, insight classification (minor vs significant), silent/approval-gated writes |

### New DB Table

```sql
CREATE TABLE performa (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id),
  manual_data JSONB NOT NULL DEFAULT '{}',
  ai_data JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE performa ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own performa"
  ON performa FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
```

---

## 2. Live Session Performance

### Bug Fixes (Blocking)

Both bugs prevent wingman from ever triggering. Fix first, before any other work.

- **`new_session_screen.dart`** line ~1016: `msg['speaker'] == "User"` → `"user"`
- **`session_provider.dart`**: `finalSpeaker == "Other"` → `"other"`
- **`deepgram_service.dart`**: ensure all speaker string assignments output lowercase `"user"` / `"other"` (already lowercase — verify and lock)

### Sub-500ms Pipeline

**Session start pre-cache (backend):**
- `start_session` launches three parallel coroutines: graph context fetch, vector context fetch, performa context fetch
- Results stored in `session_store[session_id]['context_cache']`
- `process_transcript_wingman` reads from cache (zero latency per turn)
- On cache miss (new user, evicted): `asyncio.wait_for(fetch_all_context(), timeout=0.2)` — use whatever loaded

**LLM tuning:**
- Reduce `max_tokens` from 60 → 45 (saves ~80ms on Cerebras)
- Keep Cerebras as primary, Groq as fallback (unchanged)

**Flutter timeout reductions:**
- Wingman HTTP timeout: 15s → 4s
- Realtime fallback timeout: 30s → 8s

**Latency budget per turn:**

| Step | Target |
|------|--------|
| Deepgram STT (is_final) | ~200–400ms (Deepgram's own) |
| Flutter → backend | ~20ms |
| Context fetch (cached) | ~0ms |
| Cerebras LLM (45 tok) | ~150–250ms |
| Backend → Flutter | ~20ms |
| **Total (app-controlled)** | **~190–290ms** |

---

## 3. Speaker Detection

### Confidence Threshold

- `deepgram_service.dart`: compute average `confidence` across `words[]` for each final transcript
- Pass `confidence` alongside `speaker` string in transcript callback
- Threshold: `< 0.75` = uncertain

**Session provider flow:**
- `confidence < 0.75`: log transcript, skip wingman, mark entry `isUncertain = true`
- `confidence ≥ 0.75`: normal flow — trigger wingman on "other" turns

### Uncertain Bubble UI

- Bubble renders with faint `?` badge on top-right corner
- Speaker color at 60% opacity
- Tap `?` badge → inline action row: **"This was me"** / **"This was them"**
- On tap: re-attributes, re-triggers wingman if now "other", removes badge

### Manual Override (All Bubbles)

- Long-press any bubble → context menu: **"Switch speaker"**
- Re-attributes + re-triggers wingman if result is "other"
- **"Swap all speakers"** button (existing `toggleSwapSpeakers`) gets warning tooltip: "This flips all past messages"

### Speaker Labels

- Bubbles display **"You"** / **"Them"** (not raw speaker strings)
- Uncertain: **"You?"** / **"Them?"**

---

## 4. Teleprompter Panel

**Extracted to:** `lib/widgets/teleprompter_panel.dart`

### Widget Signature

```dart
TeleprompterPanel({
  required List<String> hints,
  double initialHeightFraction = 0.38,
  bool hasUncertainSpeaker = false, // drives amber dot in header
  VoidCallback? onClose,
})
```

Fully self-contained. No session state inside it. Parent (`new_session_screen.dart`) passes `hasUncertainSpeaker` derived from `SessionProvider`.

### Size States (3 Snaps)

| State | Height | Hints visible |
|-------|--------|---------------|
| Compact | 22% screen | Latest hint only (no scroll) |
| Default | 38% screen | ~4–5 hints |
| Expanded | 68% screen | ~9–10 hints |

### Drag & Snap

- Pill drag handle at top-center (`GestureDetector` + `AnimatedContainer`)
- Snaps to nearest state on release, velocity-aware (fast flick skips midpoint)
- Double-tap header → cycles Compact → Default → Expanded → Compact
- Expand/collapse icon button (top-right) taps through same 3 states

### Scroll Behavior

- Default + Expanded: auto-scroll to latest hint; "Latest" button when user scrolls up
- Compact: no scroll, always shows newest hint only

### Hint Entry Cards

- Latest: full opacity, primary accent left border, 14.5px
- Previous: 80% opacity, no border, 13px, compressed padding
- Entry animation: slide up + fade in (existing, keep)
- `_adviceHistory` capped at 20 entries

### Header Bar

- Left: hint count badge ("4 hints")
- Center: drag pill
- Right: expand/collapse icon
- Uncertain speaker active: amber pulsing dot indicator

---

## 5. Performa Profile

### Data Model (`lib/models/performa.dart`)

```dart
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
  final String communicationStyle; // "direct" | "diplomatic" | "analytical"
  final List<PerformaContact> recurringContacts;
  final List<String> customKeywords;
  final String background; // free-text

  // AI-extended fields
  final List<PerformaInsight> aiInsights;
  final List<String> inferredStrengths;
  final List<String> inferredWeaknesses;
  final List<String> notablePatterns;

  final DateTime createdAt;
  final DateTime updatedAt;
}

class PerformaContact {
  final String name;
  final String relationship;
  final String notes;
  final DateTime? lastSeenAt;
}

class PerformaInsight {
  final String text;
  final String source;     // session_id that triggered it
  final double confidence; // 0.0–1.0
  final DateTime addedAt;
  final bool approved;
}
```

### Performa Screen (`lib/screens/performa_screen.dart`)

4-tab layout:

**Tab 1 — About You**
- Editable fields: name, role, industry, company, communication style (dropdown)
- Goals: chip list + add button
- Conversation scenarios: chip list + add button
- Languages: chip list
- Background: multi-line text field

**Tab 2 — People**
- `recurringContacts` list: name, relationship, notes
- Add / edit / delete contacts
- `customKeywords`: chip list

**Tab 3 — AI Insights**
- Read-only list of `aiInsights` with `approved: true`
- Each insight: text + source label + confidence bar
- Editable text (tap to edit)
- Swipe to delete

**Tab 4 — Export**
- Export PDF button
- Export JSON button
- Export Markdown button
- Each export uses `performa_repository.dart` export methods

**Entry point:** Profile icon in app bar → routes to Performa screen

### AI Extension Pipeline (`server_v2/app/services/performa_service.py`)

Called after `end_session` as a background task:

1. Single LLM call: scan session transcript for patterns (cheap prompt, ≤200 tokens output)
2. Classify each finding:
   - **Minor**: contact name mentioned, repeated keyword, topic area
   - **Significant**: new goal detected, communication weakness pattern, role/industry change signal
3. Minor → insert with `approved: true` (silent)
4. Significant → insert with `approved: false` (pending approval)

### Approval Card UI (Flutter)

- Bottom sheet shown on next app open if pending insights exist
- Title: "We learned a few things about you"
- List of pending insights, each: text + approve ✓ / reject ✗ tap
- Approved → `approved: true` in DB; rejected → deleted

### Session Context Injection

`start_session` pre-cache loads performa. Brain service wingman prompt gains:

```
ABOUT YOU:
Role: {role} at {company}
Industry: {industry}
Goals: {goals joined by ", "}
Watch for: {customKeywords joined by ", "}
Style: {communicationStyle}
```

Injected only when non-empty. Hard token budget: 80 tokens (truncated beyond that).

### Export Formats

| Format | Contents |
|--------|---------|
| JSON | Full model serialized, all fields |
| Markdown | Structured human-readable doc, sections per tab |
| PDF | `pdf` package, A4, sections + AI insights table |

---

## 6. Non-Goals

- Voice enrollment / biometric speaker ID (existing `voice.py` infra — out of scope)
- Performa sharing between users
- Performa versioning / history
- Real-time performa updates during a live session (only post-session)
