# Feature 4 — Live Confidence Meter

A real-time on-device meter that shows the user how confidently they're
speaking during a wingman session. The meter and the heuristic live
**entirely in the app** — the server only persists the per-turn
confidence score at session end so a future dashboard can chart a
"confidence trend" series.

## Server side — what was built

**No new table, no worker, no LLM call.** The pre-existing
`session_logs.confidence numeric` column (in baseline schema since
day 1, previously unused) is the storage target. F4 adds one repo
function, one route, and three schemas.

**Endpoint** (under `/v1`, JWT-authenticated, owner-scoped via session
ownership):

| Method | Path | Purpose |
|---|---|---|
| POST | `/v1/sessions/{session_id}/confidence` | Bulk-update `session_logs.confidence` from a per-turn array. Body `{confidence_by_turn: [{turn_index, score}, ...]}` (1-500 items, `score` in `[0.0, 1.0]`, `turn_index ≥ 0`). Returns `{updated: <int>}`. `200` happy path. `404` unknown session. `403` not session owner. `400` malformed body. `429` rate-limited (~10/min/user). |

**Repo function** (`session_logs_repo.update_confidence_bulk`) is a
single SQL `UPDATE session_logs SET confidence = data.score FROM unnest($1::int[], $2::numeric[]) ...`
— one round-trip regardless of array size. Rows whose `turn_index`
doesn't match an existing log entry are silently ignored; the response
`updated` count tells the app how many rows actually landed.

**Speed:** one route, one DB write, no fan-out. The wingman per-turn
loop and its 0.5 s context budget are untouched.

## App side — what is required (Flutter)

### 1. The meter (UX)

A small inline widget visible during an active wingman session.
Renders a value in `[0.0, 1.0]` mapped to a colour:

| Score range | Colour |
|---|---|
| `0.0 ≤ s < 0.4` | red (low confidence) |
| `0.4 ≤ s < 0.7` | amber |
| `0.7 ≤ s ≤ 1.0` | green |

Update cadence: recompute on every new STT chunk; smooth the displayed
value with a short ease-in (e.g., 200 ms) so the meter doesn't
jitter mid-turn.

### 2. The heuristic (formula)

Run locally over the **rolling last 8 s** of the user's transcribed
speech (configurable via an app constant):

```
filler_tokens  = ["um", "uh", "er", "ah", "hmm",
                  "like", "basically", "literally", "actually"]
hedge_phrases  = ["you know", "sort of", "kind of", "i mean",
                  "i think", "i guess", "maybe", "possibly"]

filler_count   = count of filler_tokens in window (case-insensitive, whole-word)
hedge_count    = count of hedge_phrases in window (case-insensitive, bigram/trigram match)
word_count     = total word count in window

filler_density = (filler_count + 0.5 * hedge_count) / max(word_count, 1)
confidence     = clamp(1.0 - 4.0 * filler_density, 0.0, 1.0)
```

Tune so that **25 % filler density ⇒ confidence 0.0** (the formula
above does this directly).

### 3. Per-turn capture

Each turn ends when the wingman session logs a user turn (the existing
`/v1/log_turn` write or its inline equivalent). At that moment, snapshot
the **current meter value** (not the rolling average across the turn)
and store it locally as `{turn_index, score}`. Stash the array in
session state for the duration of the session.

### 4. Send to server on session end

After `POST /v1/end_session` returns `200`, fire (fire-and-forget):

```http
POST /v1/sessions/{session_id}/confidence
Authorization: Bearer …
Content-Type: application/json

{
  "confidence_by_turn": [
    {"turn_index": 0, "score": 0.82},
    {"turn_index": 1, "score": 0.74},
    {"turn_index": 2, "score": 0.41},
    ...
  ]
}
```

The call is **non-essential**. Failure (network, 429, 5xx) does not
degrade the live meter UX. Log and move on. App SHOULD retry once on
network failure but should not block end-of-session navigation.

### 5. Error handling

- **`400`** — body validation failed. Shouldn't happen with correct
  app code; log and drop.
- **`401`** — auth expired between `end_session` and the confidence
  POST. Treat as already-handled; the global auth flow will re-prompt.
- **`403`** — wrong owner. Should never happen for a session the user
  just ended; log as a bug.
- **`404`** — session id doesn't exist. Probably a race against
  another tab deleting the session; log and drop.
- **`429`** — rate-limited. App should debounce session-end retries.
- **`5xx`** — drop silently; the meter UX is unaffected.

### 6. What the app does NOT do

- The app does **not** compute confidence on the server. The heuristic
  is local, deterministic, latency-free.
- The app does **not** display the persisted confidence anywhere yet.
  Persistence is forward-looking — a future F3 dashboard follow-up
  will add a `confidence_per_bucket` series.

## Status lifecycle

The endpoint is **idempotent in spirit but not by contract**: posting
the same `confidence_by_turn` array twice will overwrite the column
to the same value both times. There is no `updated_at` on
`session_logs` to bump; the column simply reflects whatever was last
written.

| Server state | meaning |
|---|---|
| `confidence IS NULL` | turn not yet scored (default) |
| `confidence IS NOT NULL` | app posted a score for this `turn_index` |

`coaching_report` and `session_analytics` do **not** automatically
read the new column yet. That's a future follow-up; F4's scope is
storage only.

## File map (server)

- `server/src/bubbles/api/v1/_schemas.py` — `TurnConfidenceItem`, `SetTurnConfidenceRequest`, `SetTurnConfidenceResponse`.
- `server/src/bubbles/db/repo/session_logs.py` — `update_confidence_bulk` appended.
- `server/src/bubbles/api/v1/sessions.py` — `POST /sessions/{id}/confidence` route appended.

## Tests

- `server/tests/unit/test_routes_validation.py` — 5 cases (empty list, score > 1, score < 0, turn_index < 0, unknown field) all reject with `422`.
- `server/tests/integration/test_repo_session_logs_confidence.py` — 4 cases (happy path bulk update, unknown turn_index silently skipped, cross-session isolation, empty list is no-op).
- `server/tests/integration/test_routes_sessions_confidence.py` — 5 cases (happy path 200 + count, 404 unknown session, 403 cross-user, 429 rate-limited, unknown turn_index still 200).

Integration tests run with `$env:RUN_INTEGRATION='1'` and require
Docker (testcontainers Postgres). They skip automatically when Docker
is unavailable.

## Out of scope (handled later, if ever)

- Adding `confidence_per_bucket` to the F3 dashboard. Trivially additive
  once F4 ships and produces data.
- Server-side recomputation from the transcript. The heuristic is
  app-side; server stores opaque numbers.
- `coaching_report.avg_confidence` aggregate. Compute on demand from
  `session_logs` if/when needed.
- Real-time streaming of confidence to server. Pull-batch on session
  end is sufficient.
- Configurable heuristic weights / server-side feature flags. Fixed in
  the app constants.
- Multilingual filler lists. English only for v1.
