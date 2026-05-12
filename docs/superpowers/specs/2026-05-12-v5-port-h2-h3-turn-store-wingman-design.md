# H2 + H3 — Per-turn store + `process_transcript_wingman` (v5 port)

**Date:** 2026-05-12 • **Owner:** backend • **Severity:** P0 • **Ref:** `Documentation/server-vs-server_v2-review.md` §5 H2/H3, §6 step 2

## Problem

- **H2** — v5 stores no per-turn conversation content. No `session_logs` writer, `save_session` is a no-op, the transcript exists only transiently. Consequence: `session_replay/{session_id}` is unbuildable; per-turn `session_analytics` columns (`average_latency_ms`, `avg_advice_latency_ms`, `avg_sentiment_score`, `dominant_sentiment`) stay NULL; `sentiment_trend` is `[]`.
- **H3** — v2's `process_transcript_wingman` (the real-time, per-turn advice loop — the actual product feature) is not ported. v5 ships only `suggest_reply` (one-shot `wingman.short`). Not equivalent.

These are one batch: the wingman loop is where turns naturally get persisted.

## Decision (per review §6 step 2 — option 5.H2(a))

Add a `session_logs` table + persist every turn. `end_session` assembles the
transcript from rows when the client doesn't supply one (H1 still accepts a
client-supplied transcript; rows take precedence). This unlocks `session_replay`
and the per-turn analytics columns.

We mirror v2's `session_logs` shape so the existing analytics worker math and the
future `session_replay` endpoint line up with the live Supabase schema.

## Scope

1. **Migration `0004_session_logs`** — `session_logs` table (forward + working `downgrade`):
   - `id uuid pk default gen_random_uuid()`
   - `session_id uuid not null references sessions(id) on delete cascade`
   - `user_id uuid not null references auth.users(id) on delete cascade`
   - `role text not null check (role in ('user','others','llm'))`
   - `content text not null`
   - `speaker_label text`, `confidence numeric`
   - `model_used text`, `latency_ms integer`, `tokens_used integer`, `finish_reason text`
   - `sentiment_score numeric`, `sentiment_label text`  *(written later by a sentiment pass; nullable now)*
   - `is_ephemeral boolean not null default false`
   - `turn_index integer not null` *(monotonic per session; assigned server-side)*
   - `created_at timestamptz not null default now()`
   - indexes: `(session_id, turn_index)`, `(user_id, created_at desc)`
   - Baseline `0001` is a no-op against live Supabase — but `session_logs` already exists there per `db_schema_final_v2.sql`; `0004` must therefore be **idempotent / `IF NOT EXISTS`-guarded** for the live DB and create-from-scratch for a fresh CI DB. Match the pattern `0002`/`0003` already use.
2. **`baseline.sql`** — add `session_logs`; **conftest** teardown — add `session_logs` to the DROP list.
3. **`db/models.py`** — `SessionLog` dataclass.
4. **`db/repo/session_logs.py`** — new repo:
   - `append(conn, *, session_id, user_id, role, content, **meta) -> SessionLog` — computes `turn_index` as `coalesce(max(turn_index)+1, 0)` for the session (single statement, `INSERT … SELECT`), returns the row.
   - `list_for_session(conn, *, session_id, limit, offset) -> list[SessionLog]` — ordered by `turn_index`.
   - `assemble_transcript(conn, *, session_id, limit=None) -> str` — `"User: …\nAI: …"`-style join (role → label map: `user→User`, `others→Others`, `llm→AI`), newest-N if `limit` given (for rolling summaries).
   - `count_for_session`, `turn_count` helpers.
5. **`session_analytics`-style repo for ephemeral session metadata** — out of scope; reuse `sessions.session_context` + a small Redis cache as v5 already does for `post_session_context`. (v2's `session_store` is Redis-backed metadata; we don't need a faithful port — the wingman route reads `sessions` + `session_context` directly.)
6. **Schemas (`_schemas.py`)**:
   - `WingmanTurnRequest`: `session_id: UUID | None`, `transcript: str (1..4000)`, `speaker_role: Literal['user','others'] = 'others'`, `speaker_label: str | None`, `confidence: float | None (0..1)`, `mode: str = 'live_wingman'`, `persona: str = 'casual'`. (No `user_id` — taken from the JWT, unlike v2.)
   - `WingmanTurnResponse`: `advice: str`, `provider: str`, `turn_index: int | None`.
   - `LogTurnRequest` / `LogTurnResponse` — a plain "append a turn" route for clients that aren't using the wingman loop (e.g. user-only turns, or a non-AI session).
   - `SessionReplayResponse`: `session_id`, `turns: list[ReplayTurnOut]` where `ReplayTurnOut` exposes role/content/speaker_label/created_at/turn_index/latency/sentiment.
7. **Route `POST /v1/process_transcript_wingman`** (`api/v1/wingman.py`, new module):
   - Auth + ownership on `session_id` if provided.
   - Append the incoming turn to `session_logs` (role = `speaker_role`).
   - If `speaker_role == 'user'`: enqueue `compute_embeddings` (memory of `"User: …"` is created by the existing memory path — keep parity by enqueuing extract/embeddings sparingly), return `{"advice": "WAITING", ...}`. **No** synchronous LLM call (matches v2 fast-path).
   - Else (`others`): build context (graph + vector) — v5 already has `ai/graph` + `ai/embeddings`; use them with a hard timeout like v2's 200 ms cap, falling back to empty context. Call `LLMRouter.complete("wingman.advice", …)` with the persona/scenario system prompt (reuse the persona Jinja fragments + `_scenario_header` already ported). Append the advice as an `llm` turn (with `model_used`/`latency_ms`/`tokens_used`/`finish_reason` meta). Every Nth turn (configurable, default 5) enqueue `extract_knowledge` for the running transcript; every turn is cheap-only. Return `{"advice": advice_text, "provider": …, "turn_index": …}`.
   - All persistence/extraction beyond the advice itself is fire-and-forget via `app.state.bg` (`FireAndForget`) so it never blocks the response — same posture as v2's `asyncio.create_task`.
8. **Route `POST /v1/log_turn`** — append a single turn; ownership-checked; returns the stored row. (Lets the client persist user turns even outside the wingman loop, and is what `save_session` semantics should have been.)
9. **Route `GET /v1/session_replay/{session_id}`** — ownership-checked; paginated (`limit`/`offset`); returns turns ordered by `turn_index`. (Closes the §2 "not yet registered" `session_replay` item too.)
10. **`end_session`** — if `body.transcript` is `None`, assemble it from `session_logs` rows; if rows exist, prefer them over a supplied transcript (rows are authoritative). Then enqueue the post-session jobs as today (H1). If neither rows nor a supplied transcript → no jobs (unchanged).
11. **`save_session`** — leave as the read-only refresh it is; `log_turn` is the real "persist" path now. Update its docstring and the review §4 note. *(Alternatively fold `log_turn` semantics into `save_session` — but `save_session`'s `transcript: str` field implies a full-blob replace, which we don't want; keep them separate.)*
12. **Worker `compute_session_analytics`** — when invoked, prefer rebuilding the transcript from `session_logs` if present (so the per-turn columns + `sentiment_trend` can be filled from row metadata); the `transcript` arg becomes a fallback. (Small change; the row→metrics math is the H2 payoff.)
13. **`LLMRouter` task chains** — register `wingman.advice` (gemini → cerebras → groq) in the wiring if not already present; `suggest_reply` keeps `wingman.short`.
14. **Rate limiting** — `process_transcript_wingman` is hot; apply the existing `RateLimiter` (token bucket) keyed by user, ~30/min like v2.

## Out of scope

- Rolling-summary-every-20-turns (`_rolling_summarize`) — nice-to-have, fold into a follow-up if desired; not required for parity-with-a-workaround.
- Multiplayer / `is_multiplayer` turn handling.
- Sentiment scoring of turns (the `sentiment_score`/`sentiment_label` columns ship nullable; a `sentiment_scan` worker is a later item — note it in the review as a sub-hole of H2).
- Speaker `enroll`/`identify` (that's H4, next).

## Tests

- `tests/integration/test_repo_session_logs.py` — append assigns monotonic `turn_index`; `assemble_transcript` role mapping + newest-N; `list_for_session` ordering; cascade delete with the session.
- `tests/integration/test_routes_wingman.py` — user turn → `{"advice":"WAITING"}` + a row appended; `others` turn (stub `LLMRouter`) → advice text + an `llm` row appended + `turn_index` monotonic; ownership 403; queue-down still 200.
- `tests/integration/test_routes_session_replay.py` — replay returns turns in `turn_index` order, paginates, 404 unknown / soft-deleted, 403 other user.
- `tests/integration/test_routes_sessions.py` — extend: `end_session` with no `transcript` but existing `session_logs` rows enqueues the post-session jobs (assembled from rows).
- `tests/unit/test_routes_validation.py` — `process_transcript_wingman` rejects empty `transcript`, bad `speaker_role`, `confidence` out of `[0,1]`.
- `tests/unit/` — `assemble_transcript` pure-ish bits if any land in `core/transcript.py`.

## Done when

`ruff` clean, `mypy --strict` clean, unit suite green (integration suite green when `RUN_INTEGRATION=1`); migration `0004` upgrades+downgrades cleanly against a fresh Postgres and is a safe no-op against the live schema; review doc §2/§4/§5(H2,H3)/§6/§7 updated; `session_replay` removed from §2's "not yet registered" list.
