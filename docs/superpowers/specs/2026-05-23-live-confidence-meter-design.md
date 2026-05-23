# Live Confidence Meter — local heuristic with server persistence

**Date:** 2026-05-23 • **Owner:** backend (server crumbs) + app (UX) • **Type:** new feature (Feature 4 of 4) • **Ref:** brainstorming 2026-05-23

## Problem

A user practicing a real conversation through Bubbles-AI has no in-the-moment signal that tells them whether they sound confident or hesitant. They get an after-the-fact `coaching_report` with filler-word counts at the end of a session, but the *live* meter — the thing that nudges them to slow down or skip the "um" — is missing.

The on-device transcript stream already has everything needed to compute this: each STT chunk arrives with text, and the app can run a tiny regex over the rolling last-N-second window. There is no server inference needed; an LLM call would blow the 0.5 s wingman context budget.

The only server-side question is whether to *persist* the score so the existing F3 dashboard can later add a "confidence trend" series. The `session_logs` table already carries an unused `confidence numeric` column from the baseline schema — sized exactly for this purpose.

## Decision

The thinnest possible server-side feature, scoped to **enable persistence only**. The meter itself, the heuristic, the rolling window, the colour-coded UI — all of that is app-side. The server adds:

- One write endpoint that accepts a per-session bulk update of per-turn confidence scores.
- A repo function that does the `UPDATE` against the existing `session_logs.confidence` column.
- Three Pydantic schemas (request item, request envelope, response).
- Tests.

**Why batch on `end_session`:**
- Wingman per-turn loop stays untouched. No `client_confidence` kwarg is added to the existing turn endpoint, so a malformed client field can never break the wingman hot path.
- One round-trip per session, not N. Network impact is invisible.
- If the call fails, the meter still works — confidence persistence is a side-effect, not the feature.

**Why per-turn (not per-session-average):**
- The existing schema column is per-turn. Storing the array unlocks F3 dashboard follow-up without a second migration.
- Average can always be derived; the reverse is impossible.

**Why `0..1 float`:**
- Matches the existing `session_logs.confidence numeric` column type and the project's sentiment-score precedent.
- `Field(ge=0.0, le=1.0)` makes the contract self-documenting.

**Why the heuristic stays in the app:**
- LLM call per turn breaks the 0.5 s budget.
- Server-side regex over the transcript would double-process every turn for no benefit.
- The app already has the text in real time; computing locally is zero-latency.

## Scope

1. **`db/repo/session_logs.py`** — modify; append a single new function:

   ```python
   async def update_confidence_bulk(
       conn: asyncpg.Connection,
       *,
       session_id: UUID,
       items: list[tuple[int, float]],
   ) -> int:
       """Bulk-update session_logs.confidence keyed by (session_id, turn_index).

       Rows whose ``turn_index`` does not match an existing log entry for
       this session are silently ignored. Returns the count of rows
       actually updated.
       """
   ```

   Implementation is one SQL statement using `unnest`:

   ```sql
   UPDATE session_logs sl
   SET confidence = data.score
   FROM unnest($1::int[], $2::numeric[]) AS data(turn_index, score)
   WHERE sl.session_id = $3 AND sl.turn_index = data.turn_index
   ```

   Use `conn.execute` and parse the `UPDATE N` status string for the count, or use `RETURNING 1` + `len(rows)`.

2. **Schemas** (`api/v1/_schemas.py`):

   - `TurnConfidenceItem(_Base)` — `turn_index: int = Field(ge=0)`, `score: float = Field(ge=0.0, le=1.0)`.
   - `SetTurnConfidenceRequest(_Base)` — `confidence_by_turn: list[TurnConfidenceItem] = Field(min_length=1, max_length=500)`.
   - `SetTurnConfidenceResponse(_Base)` — `updated: int = Field(ge=0)`.

   The `max_length=500` cap on `confidence_by_turn` is a defensive bound: a 500-turn session is multi-hour and well beyond any realistic wingman session.

3. **Route** (`api/v1/sessions.py` — append):

   ```python
   @router.post(
       "/sessions/{session_id}/confidence",
       response_model=SetTurnConfidenceResponse,
   )
   async def set_turn_confidence(
       session_id: UUID,
       body: SetTurnConfidenceRequest,
       user: CurrentUserDep,
       pool: PoolDep,
       limiter: RateLimiterDep,
   ) -> SetTurnConfidenceResponse: ...
   ```

   Behaviour:
   - Rate limit ~10 calls/min/user. Key: `f"confidence:{user.id}"`. `429` when exceeded.
   - Load session via `sessions_repo.get`; `404` when missing; `403` when `session.user_id != user.id` (via `require_ownership`).
   - Convert `body.confidence_by_turn` into two parallel arrays (`turn_indexes`, `scores`).
   - Call `session_logs_repo.update_confidence_bulk` inside a `UnitOfWork`.
   - Return `SetTurnConfidenceResponse(updated=<count>)`.

   No fan-out; no enqueue; no side effects beyond the row update.

4. **Tests:**

   - `tests/unit/test_routes_validation.py` (extend) — `SetTurnConfidenceRequest` rejects empty list, item with `score=1.5`, item with `turn_index=-1`.
   - `tests/integration/test_repo_session_logs_confidence.py` — `update_confidence_bulk` updates matching `(session_id, turn_index)`; silently skips non-matching `turn_index`; returns correct count; values readable via subsequent SELECT.
   - `tests/integration/test_routes_sessions_confidence.py` — happy path 200 + `updated` count; 404 unknown session; 403 cross-user; 400 on out-of-range score; 429 on rate-limit; ignores turn_index that's not in session_logs (still 200).

## Out of scope

- Adding `confidence_per_bucket` series to the F3 dashboard. Trivially additive later — the data is there once F4 ships.
- Server-side recomputation of confidence from the transcript. The heuristic is app-side; server stores opaque numbers.
- `coaching_report.avg_confidence` aggregate. Can be computed on demand from `session_logs`.
- Per-session "confidence over time" chart endpoint. Existing `session_logs` is exposed via the analytics surface — extend there if/when a per-session line chart is needed.
- Real-time streaming (websocket / SSE). The meter is local; the server only needs the final batch.
- Configurable heuristic weights or server-side feature flags for fillers/hedges. Fixed in the app; doc captures the formula so a future v2 can adjust.
- Multilingual filler lists. English only for v1.

## Done when

`ruff` clean, `mypy --strict` clean, the unit suite green (integration suite green under `RUN_INTEGRATION=1`); the confidence route is visible in the OpenAPI schema; every function fully implemented — no placeholder bodies, stub returns, or "implement later" comments.

## App-side heuristic (documented here so the app contract is single-sourced)

The doc at `Documentation/feature-4-live-confidence-meter.md` carries the full app contract. The heuristic itself is:

- Filler tokens (case-insensitive, whole-word): `um, uh, er, ah, hmm, like, basically, literally, actually`.
- Hedge phrases (case-insensitive, matched as bigrams/trigrams): `you know, sort of, kind of, i mean, i think, i guess, maybe, possibly`. Hedges weight 0.5× a filler.
- Rolling window: last 8 s of speech (configurable in app constants).
- Score formula: `filler_density = (filler_count + 0.5 * hedge_count) / max(word_count, 1)`; `confidence = clamp(1.0 - 4.0 * filler_density, 0.0, 1.0)`.
- Render thresholds: < 0.4 red, 0.4-0.7 amber, > 0.7 green.

Per-turn confidence stored by the app is the **score at the moment the turn ended** (not the rolling average across the turn).
