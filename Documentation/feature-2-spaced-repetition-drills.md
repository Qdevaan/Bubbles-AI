# Feature 2 — Spaced-Repetition Mistake Drills

Turns the `user_mistakes` log into a Leitner-box spaced-repetition drill
system: cards materialised at session end, self-graded by the user, XP
awarded on every box transition. Delivered as a daily due-stack plus an
on-demand "practice early" surface.

## Server side — what was built

**Table** `drill_cards` (migration `0007`): one row per
`(user_id, rule_id, category)`. Carries the Leitner state inline —
`box (1..5)`, `due_at`, `last_reviewed_at`, `correct_streak`,
`total_reviews`, `total_correct`, `retired_at`. The `examples` JSONB
column holds the **10 most recent snippets** for the card
(`{mistake_id, snippet, suggestion, created_at}`, newest at index 0).
Unique on `(user_id, rule_id, category)`. Hot-path index
`(user_id, due_at) WHERE retired_at IS NULL`.

**Helper** `bubbles.ai.drills.next_state(box, result)` — pure Leitner
math. Correct advances by 1 (capped at 5). Wrong resets to 1. Box
intervals: `{1: 1d, 2: 3d, 3: 7d, 4: 14d, 5: 30d}`.

**Worker** `materialize_drill_cards` — runs from the `end_session`
fan-out. Loads this session's `user_mistakes` rows via
`grammar_repo.list_for_session` and upserts cards via
`drill_repo.upsert_from_mistakes`. New mistakes are prepended to the
card's `examples` array; the array is capped at 10. The job is
deduplicated per `(user_id, session_id)` so a repeat `end_session`
enqueue is a no-op.

**Endpoints** (all under `/v1`, JWT-authenticated, ownership-checked):

| Method | Path | Purpose |
|---|---|---|
| GET  | `/v1/drills/queue?limit=20&offset=0&include_upcoming=false` | The drill queue. By default returns cards with `retired_at IS NULL AND due_at <= now()`. When `include_upcoming=true` AND the due-list is empty, falls back to the next N upcoming cards (practice-early surface). `limit` is capped 1..100; `offset` is clamped to ≥0. |
| POST | `/v1/drills/{id}/review` | Body `{"result": "correct" | "wrong"}`. Applies the Leitner transition, persists the new box + `due_at`, awards XP. `200` with `{card, xp_awarded, transition}`. `404` unknown id. `403` not the caller's card. `409` if the card is retired. Rate-limited ~60/min/user. |
| POST | `/v1/drills/{id}/retire` | Silences the card from the queue forever. `200` with the updated card. `404` unknown. `403` not owner. `409` already retired. |

**XP awards** (via `xp_repo.record`, idempotent on
`(user_id, source_type='drill_review', source_id=f"{card_id}:{from->to}")`):

- `+15` on a correct review that advances the box (box 1..4 → next box).
- `+5` on a wrong review (showing-up credit). Resets to box 1.
- `+0` on a correct review that stays in box 5 (mastered card — no
  ledger row written at all).

Idempotency is keyed on the box transition shape, so the same
`from->to` is never double-awarded; a `wrong → correct` cycle that
recreates the same transition string after a different intervening
review still awards XP because the second occurrence is a fresh
(transition-shape, but only-fired-once) award.

**Speed:** queue is a single indexed query
(`(user_id, due_at) WHERE retired_at IS NULL`). Review is one
`UPDATE ... RETURNING` plus at most one XP insert. Materialisation
runs in an ARQ worker. The wingman per-turn loop and its 0.5 s
context budget are untouched.

## App side — what is required (Flutter)

1. **Drills tab / screen** — a new screen listing the due queue via
   `GET /v1/drills/queue`. Each card shows `front` (most recent
   snippet), the `category` badge (e.g. "article", "agreement"),
   a "box N / 5" indicator, and the `examples_count` so the user can
   see "this is the 3rd time you've made this kind of mistake".
   Show an empty state when the queue is empty (new users, or all
   cards retired/scheduled out).

2. **Practice-early** — when the due-list is empty, fetch
   `GET /v1/drills/queue?include_upcoming=true` to surface the next N
   cards regardless of `due_at`. Use a distinct UI affordance ("Practice
   early — next due in 2d") so the user knows they're working ahead of
   schedule.

3. **Self-grade flow** — tapping a card flips it. `front` (the
   snippet the user originally wrote wrong) → tap → `back` (the
   suggested correction). Two buttons: **Got it** (POST review with
   `result: "correct"`) and **Still tricky** (POST with
   `result: "wrong"`). On success, animate the card off the stack and
   pop the toast: `+15 XP` / `+5 XP` (use the response's `xp_awarded`
   value verbatim — a `0` means the same transition was already
   awarded for this card, which is the box-5-stay path or a re-grind
   path).

4. **Retire** — overflow menu / swipe action on a card →
   `POST /v1/drills/{id}/retire`; remove from list. Confirm with a
   small dialog ("Stop showing this card?") — retire is terminal.

5. **Poll cadence** — after `end_session` returns, wait 2-5 s and
   refetch `GET /v1/drills/queue` to pick up cards materialised by the
   worker. The "Drills" tab badge (the count) is `total_due` from the
   queue response.

6. **No app-side SRS logic** — the server computes the next `due_at`
   and the new `box`. The app just renders what `card` returns in
   each review response.

## Status lifecycle (card state machine)

| State | meaning | next allowed transition |
|---|---|---|
| **Active (queued)** | `retired_at IS NULL` and `due_at <= now()` | review → advance/reset; retire → silenced |
| **Active (upcoming)** | `retired_at IS NULL` and `due_at > now()` | wait; or surface via `include_upcoming=true` |
| **Mastered (box 5)** | `box = 5`, returning to box 5 each correct review | never retires automatically; user can retire manually |
| **Retired** | `retired_at IS NOT NULL` | terminal — never shows in queue, review returns 409 |

`box` only changes via `POST /v1/drills/{id}/review`. `due_at` only
changes via review (push forward) or new mistake materialisation (no
change to existing schedule — the card just gets a new example).
`retired_at` only changes via `POST /v1/drills/{id}/retire`.

## File map (server)

- `server/alembic/versions/2026_05_23_0007_drill_cards.py` — migration.
- `server/src/bubbles/db/models.py` — `DrillCard` dataclass.
- `server/src/bubbles/db/repo/drill_cards.py` — repo + `NewMistakeForCard`.
- `server/src/bubbles/db/repo/grammar.py` — `list_for_session` reader.
- `server/src/bubbles/ai/drills.py` — `BOX_INTERVALS` + `next_state` pure helper.
- `server/src/bubbles/api/v1/drills.py` — 3 routes.
- `server/src/bubbles/api/v1/_schemas.py` — `DrillCardOut`, `ReviewDrillRequest`, `ReviewDrillResponse`, `DrillQueueResponse`.
- `server/src/bubbles/api/router.py` — router registered.
- `server/src/bubbles/workers/jobs/materialize_drill_cards.py` — end_session worker.
- `server/src/bubbles/workers/enqueue.py` — `enqueue_materialize_drill_cards` helper.
- `server/src/bubbles/workers/arq_settings.py` — worker registered in `_JOB_REGISTRY`.
- `server/src/bubbles/api/v1/sessions.py` — `end_session` fan-out wired.

## Tests

- `server/tests/unit/test_drill_intervals.py` — 5 cases for `next_state` (correct advance, wrong reset, cap at 5, invalid box, invalid result).
- `server/tests/integration/test_repo_drill_cards.py` — 7 cases (upsert dedup + cap-at-10, list filters, review transitions, retire guard, ownership).
- `server/tests/integration/test_repo_grammar_session.py` — 2 cases (per-session filtering, empty result).
- `server/tests/integration/test_routes_drills.py` — 8 cases (queue ownership, include-upcoming fallback, correct + XP idempotency, wrong + show-up XP, box-5 zero-XP, retired-then-review 409, 404 unknown, 403 cross-user).
- `server/tests/integration/test_workers_drills.py` — 3 cases (no-op on empty session, upsert per rule, idempotency on second call).
- `server/tests/integration/test_routes_sessions.py` — extended to assert the new enqueue appears in the post-session fan-out.

Integration tests run with `$env:RUN_INTEGRATION='1'` and require
Docker (testcontainers Postgres). They skip automatically when Docker
is unavailable.

## Error handling

- **Rate limit** — `POST /v1/drills/{id}/review` enforces ~60
  reviews/min/user. Excess fires `429 Too Many Requests` with a
  `Retry-After` header. App should pause the review submit button and
  show a brief "slow down" toast.
- **404** — the card id is unknown.
- **403** — the card belongs to a different user. Treat as a 404 from
  the UI (don't leak ownership info).
- **409** — the card is retired (review) or already retired
  (retire endpoint).
- **5xx** — surface a generic "couldn't sync — try again" toast; queue
  state stays correct because the server is the source of truth.

## Out of scope (handled later, if ever)

- Push notifications when `total_due > 0` — app-side concern; the app
  can wake the user with a daily local notification.
- Multi-language or locale-specific rules — uses whatever `rule_id`
  the existing grammar pipeline emits.
- Multiple-choice / type-the-fix variants — only self-grade for now.
- Cron-scheduled materialisation — the end_session worker is enough.
- LLM-generated reformulations of cards — keep it deterministic.
