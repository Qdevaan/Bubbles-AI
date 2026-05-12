# H1 — Wire ARQ job enqueues into the API (v5 port)

**Date:** 2026-05-12 • **Owner:** backend • **Severity:** P0 • **Ref:** `Documentation/server-vs-server_v2-review.md` §5 H1, §6 step 1

## Problem

`server/src/bubbles/workers/enqueue.py` exposes `enqueue_session_analytics`,
`enqueue_extract_knowledge`, `enqueue_grammar_scan`, `enqueue_compute_embeddings`,
but nothing in `src/` imports them. No ARQ client is attached to the API process
(`app.state` has `redis`, `db`, … but no `arq`). Consequence: ending a session
produces no title/summary/highlights/coaching report/entity links/embeddings —
Batch 1 and Batch 3 work is inert.

## Scope

1. Attach an `ArqRedis` pool to `app.state.arq` in the lifespan (warn-only on
   failure, like the Redis/DB pings — a queue outage must not block startup).
2. Expose it as an **optional** FastAPI dependency (`ArqDep -> ArqRedis | None`).
   It must not raise `UpstreamUnavailable`: a down queue degrades a write to
   "no async follow-up", it does not 503 the request.
3. `POST /v1/end_session` accepts an optional `transcript` (client supplies the
   assembled transcript — see review §4; the per-turn store is H2, out of scope
   here). When present, enqueue `compute_session_analytics`, `extract_knowledge`,
   and `compute_embeddings` for the owner. Enqueue failures are logged and
   swallowed; the session is still ended.
4. `POST /v1/check_user_turn` enqueues `grammar_scan` for the LanguageTool pass
   (complements the synchronous LLM pass already there; the route docstring
   already promised "runs in an ARQ worker").

Out of scope: per-turn persistence (H2), `process_transcript_wingman` (H3),
backfill job (H8).

## Design

- New module `bubbles/workers/client.py`: `make_arq_pool(settings) -> ArqRedis`
  using `arq.create_pool(RedisSettings.from_dsn(settings.redis_url))`. Kept
  separate from `arq_settings.py` so importing it into the API process does not
  pull in the worker's job/AI wiring.
- `lifespan.py`: `app.state.arq = await make_arq_pool(settings)` wrapped so a
  connection failure logs `arq_unavailable` and sets `app.state.arq = None`;
  `await arq.aclose()` on shutdown.
- `deps.py`: `get_arq(request) -> ArqRedis | None` returning
  `getattr(request.app.state, "arq", None)`; `ArqDep = Annotated[ArqRedis | None, Depends(get_arq)]`.
- `_schemas.py`: `EndSessionRequest.transcript: str | None = Field(default=None, max_length=200_000)`
  (same bound as `SaveSessionRequest.transcript`).
- `sessions.py`: helper `_enqueue_post_session_jobs(arq, *, user_id, session_id, transcript)`
  — three awaits inside one `try/except Exception` that logs `post_session_enqueue_failed`.
  Called from `end_session` only when `arq is not None and body.transcript`.
- `grammar.py`: after the sync pass, `if arq is not None: await enqueue_grammar_scan(arq, user_id=…, session_id=body.session_id, text=body.text)` inside a try/except logging `grammar_enqueue_failed`.

## Tests

- `tests/unit/test_enqueue_helpers.py` — fake `ArqRedis` recording `enqueue_job`
  calls; assert each helper passes the right `_job_name`, kwargs, and stable
  `_job_id`; assert duplicate calls produce the same `_job_id`.
- `tests/unit/test_routes_grammar_enqueue.py` — stub router (no mistakes), fake
  arq via `get_arq` override, dummy pool; assert `/v1/check_user_turn` enqueues
  `grammar_scan`; assert it still 200s when `get_arq` returns `None`.
- `tests/integration/test_routes_sessions.py` — extend: `end_session` with a
  `transcript` and a fake-arq override records the three job enqueues; without a
  transcript, none; with `app.state.arq = None`, the call still 200s.

## Done when

`ruff` clean, `mypy --strict` clean, unit suite green; review doc §5 H1 / §7
updated to reflect the wiring.
