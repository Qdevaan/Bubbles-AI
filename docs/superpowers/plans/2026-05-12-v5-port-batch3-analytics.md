# Batch 3 — Analytics Read Endpoints + Feedback (v5 Port) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five v2-parity analytics HTTP endpoints to the v5 backend (`save_feedback`, `session_analytics`, `coaching_report`, `digest`, `communication_trends`) plus enhance the `compute_session_analytics` worker to populate the `session_analytics` and `coaching_reports` tables from the post-session transcript.

**Architecture:** Reads are thin route handlers over two new repo modules (`analytics`, `feedback`); writes happen in the existing ARQ post-session worker, which parses the transcript for turn/word counts and makes one LLM call for the coaching report. No new DB tables (`session_analytics`, `coaching_reports`, `feedback` already exist in the live Supabase schema) — only models, repos, schemas, a prompt, and a new LLM task chain.

**Tech Stack:** FastAPI (async), `asyncpg` over PgBouncer, repository + Unit-of-Work pattern, Pydantic v2 wire schemas, ARQ workers, `LLMRouter` (gemini→cerebras→groq), Jinja2 prompts, `pytest` (+ testcontainers integration), `ruff`, `mypy --strict`, `uv`.

**Source spec:** `docs/superpowers/specs/2026-05-12-v5-port-batch3-analytics-design.md`

**Conventions (read once before starting):**
- `from __future__ import annotations` at the top of every new module.
- `from datetime import UTC` (Python 3.12 target) — never `timezone.utc`.
- Repo functions: `conn: asyncpg.Connection` first positional, everything else keyword-only; private `_row(...)` hydration helpers; `_COLS` string constant.
- Route modules: `router = APIRouter(tags=[...])`; registered in `server/src/bubbles/api/router.py`.
- Wire schemas extend `_Base` in `server/src/bubbles/api/v1/_schemas.py` (`model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)`).
- DB models: `@dataclass(frozen=True, slots=True)` in `server/src/bubbles/db/models.py`.
- **Do not modify `server/pyproject.toml` or any tooling config.**
- Local gate (run from `server/`): `uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest`. Integration tests auto-skip locally (need `RUN_INTEGRATION=1` + Docker); they run in CI. Treat the local gate as green when ruff/mypy/unit-pytest pass.
- All `git` commands below run from the repo root `E:\FYP\FYP_V2\Bubbles-AI` unless noted. Do **not** push.

---

## File Structure

**New files:**
- `server/src/bubbles/core/transcript.py` — `TranscriptStats` dataclass + `parse_transcript()` (pure).
- `server/src/bubbles/db/repo/analytics.py` — `session_analytics` + `coaching_reports` get/upsert, `trends_since`, four `digest_*` reads.
- `server/src/bubbles/db/repo/feedback.py` — `insert`, `find_by_idempotency_key`.
- `server/src/bubbles/ai/prompts/coaching/report.jinja` — coaching-report LLM prompt.
- `server/src/bubbles/api/v1/analytics.py` — `_group_by_week()` + 5 route handlers.
- `server/tests/test_core_transcript.py` — unit tests for `parse_transcript`.
- `server/tests/test_analytics_week_grouping.py` — unit tests for `_group_by_week`.
- `server/tests/integration/test_repo_feedback.py`, `server/tests/integration/test_repo_analytics.py`, `server/tests/integration/test_routes_analytics.py` — integration suites.

**Modified files:**
- `server/src/bubbles/db/models.py` — `SessionAnalytics`, `CoachingReport`, `Feedback`, `WeeklyTrend`.
- `server/src/bubbles/api/v1/_schemas.py` — analytics section.
- `server/src/bubbles/api/router.py` — register `analytics_router`.
- `server/src/bubbles/ai/router.py` — `analytics.coaching` task chain in `DEFAULT_CHAINS`.
- `server/src/bubbles/ai/extraction.py` — `generate_coaching_report()`.
- `server/src/bubbles/workers/jobs/compute_session_analytics.py` — metrics row + coaching report steps.
- `server/tests/integration/fixtures/baseline.sql` — `session_analytics`, `coaching_reports`, `feedback`, `highlights` tables.
- `server/tests/integration/conftest.py` — teardown `DROP TABLE` list.
- `Documentation/server-vs-server_v2-review.md`, `README.md` — Batch 3 callouts.

---

## Task 1: DB models

**Files:**
- Modify: `server/src/bubbles/db/models.py` (append at end of file)

- [ ] **Step 1: Add the four dataclasses**

Append to `server/src/bubbles/db/models.py`. The file already imports `UUID`, `datetime`, `Any` and uses `@dataclass(frozen=True, slots=True)` — match the existing style. Add at the end:

```python
@dataclass(frozen=True, slots=True)
class SessionAnalytics:
    session_id: UUID
    user_id: UUID
    total_turns: int
    user_turns: int
    others_turns: int
    llm_turns: int
    user_word_count: int
    assistant_word_count: int
    average_latency_ms: int | None
    avg_advice_latency_ms: float | None
    total_duration_seconds: float | None
    memories_saved: int
    events_extracted: int
    highlights_created: int
    avg_sentiment_score: float | None
    dominant_sentiment: str | None
    topic_summary: str | None
    computed_at: datetime


@dataclass(frozen=True, slots=True)
class CoachingReport:
    id: UUID
    user_id: UUID
    session_id: UUID | None
    model_used: str | None
    user_talk_pct: float | None
    others_talk_pct: float | None
    key_topics: list[str]
    key_decisions: list[str]
    action_items: list[str]
    follow_up_people: list[str]
    filler_words: list[str]
    filler_word_count: int
    tone_summary: str | None
    engagement_trend: str | None
    suggestions: list[str]
    strengths: list[str]
    areas_of_improvement: list[str]
    report_text: str | None
    report_content: dict[str, Any]
    generated_at: datetime


@dataclass(frozen=True, slots=True)
class Feedback:
    id: UUID
    user_id: UUID
    session_id: UUID | None
    log_id: UUID | None
    consultant_log_id: UUID | None
    feedback_type: str | None
    rating: int | None
    value: int | None
    comment: str | None
    idempotency_key: str | None
    created_at: datetime


@dataclass(frozen=True, slots=True)
class WeeklyTrend:
    week: str
    sessions: int
    total_turns: int
    user_words: int
    ai_words: int
    avg_sentiment_score: float | None
    total_duration_seconds: float
```

- [ ] **Step 2: Verify lint + types**

Run (from `server/`): `uv run ruff check src/bubbles/db/models.py && uv run mypy`
Expected: PASS (mypy reports source-file count, no errors).

- [ ] **Step 3: Commit**

```bash
git add server/src/bubbles/db/models.py
git commit -m "feat(models): add analytics DB models (SessionAnalytics, CoachingReport, Feedback, WeeklyTrend)"
```

---

## Task 2: Transcript parser (`core/transcript.py`)

**Files:**
- Create: `server/src/bubbles/core/transcript.py`
- Test: `server/tests/test_core_transcript.py`

- [ ] **Step 1: Write the failing tests**

Create `server/tests/test_core_transcript.py`:

```python
"""Unit tests for the pure transcript parser."""

from __future__ import annotations

from bubbles.core.transcript import TranscriptStats, parse_transcript


def test_empty_transcript_is_all_zeros() -> None:
    assert parse_transcript("") == TranscriptStats(0, 0, 0, 0, 0, 0, 0)
    assert parse_transcript("   \n  \n") == TranscriptStats(0, 0, 0, 0, 0, 0, 0)


def test_single_user_line() -> None:
    s = parse_transcript("User: hello there friend")
    assert s.total_turns == 1
    assert s.user_turns == 1
    assert s.others_turns == 0
    assert s.llm_turns == 0
    assert s.user_words == 3


def test_mixed_speakers() -> None:
    text = "\n".join(
        [
            "User: hi how are you",          # 4 user words
            "AI: I am well thanks",           # 4 assistant words
            "Alice: nice to meet you both",   # 5 others words
            "User: same here",                # 2 user words
        ]
    )
    s = parse_transcript(text)
    assert s.total_turns == 4
    assert s.user_turns == 2
    assert s.llm_turns == 1
    assert s.others_turns == 1
    assert s.user_words == 6
    assert s.assistant_words == 4
    assert s.others_words == 5


def test_continuation_lines_attach_to_previous_turn() -> None:
    text = "User: first part\nand second part\nAI: reply"
    s = parse_transcript(text)
    assert s.total_turns == 2
    assert s.user_turns == 1
    assert s.user_words == 5  # "first part and second part"
    assert s.llm_turns == 1
    assert s.assistant_words == 1


def test_leading_continuation_with_no_speaker_is_ignored() -> None:
    # Lines before any speaker prefix have nowhere to attach -> dropped.
    s = parse_transcript("just some preamble text\nUser: real turn")
    assert s.total_turns == 1
    assert s.user_turns == 1
    assert s.user_words == 2


def test_assistant_aliases_classified_as_llm() -> None:
    for name in ("Assistant", "ai", "Bubbles", "AI"):
        s = parse_transcript(f"{name}: one two three")
        assert s.llm_turns == 1, name
        assert s.assistant_words == 3, name


def test_user_aliases_classified_as_user() -> None:
    for name in ("User", "me", "You", "user"):
        s = parse_transcript(f"{name}: alpha beta")
        assert s.user_turns == 1, name
        assert s.user_words == 2, name


def test_long_speaker_label_is_treated_as_content_not_prefix() -> None:
    # A "prefix" longer than 40 chars before the colon is not a speaker.
    long_label = "x" * 50
    s = parse_transcript(f"{long_label}: hello")
    assert s.total_turns == 0


def test_extra_whitespace_around_speaker_and_content() -> None:
    s = parse_transcript("  User  :   spaced   out   words  ")
    assert s.user_turns == 1
    assert s.user_words == 3
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `server/`): `uv run pytest tests/test_core_transcript.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'bubbles.core.transcript'`.

- [ ] **Step 3: Implement the parser**

Create `server/src/bubbles/core/transcript.py`:

```python
"""Pure transcript parsing — turn/word counts from a plain-text transcript.

v5 does not persist per-turn ``session_logs``; the post-session worker only
receives the accumulated transcript string. Speaker roles are inferred from
``Speaker: text`` line prefixes (the same shape v5's wingman prompts render).
"""

from __future__ import annotations

import re
from dataclasses import dataclass

_SPEAKER_RE = re.compile(r"^\s*([^:]{1,40}?)\s*:\s*(.*)$")
_USER_NAMES = frozenset({"user", "me", "you"})
_LLM_NAMES = frozenset({"ai", "assistant", "bubbles"})


@dataclass(frozen=True, slots=True)
class TranscriptStats:
    total_turns: int
    user_turns: int
    others_turns: int
    llm_turns: int
    user_words: int
    assistant_words: int
    others_words: int


def _word_count(text: str) -> int:
    return len(text.split())


def parse_transcript(transcript: str) -> TranscriptStats:
    # role -> list of content fragments for the current open turn
    turns: list[tuple[str, list[str]]] = []
    for raw_line in transcript.splitlines():
        line = raw_line.rstrip()
        if not line.strip():
            continue
        m = _SPEAKER_RE.match(line)
        if m is not None:
            speaker = m.group(1).strip().lower()
            content = m.group(2)
            if speaker in _USER_NAMES:
                role = "user"
            elif speaker in _LLM_NAMES:
                role = "llm"
            else:
                role = "others"
            turns.append((role, [content] if content else []))
        elif turns:
            turns[-1][1].append(line.strip())
        # else: continuation before any speaker -> dropped

    total = user_t = others_t = llm_t = 0
    user_w = asst_w = others_w = 0
    for role, fragments in turns:
        total += 1
        wc = sum(_word_count(f) for f in fragments)
        if role == "user":
            user_t += 1
            user_w += wc
        elif role == "llm":
            llm_t += 1
            asst_w += wc
        else:
            others_t += 1
            others_w += wc
    return TranscriptStats(total, user_t, others_t, llm_t, user_w, asst_w, others_w)
```

- [ ] **Step 4: Run tests to verify they pass**

Run (from `server/`): `uv run pytest tests/test_core_transcript.py -q`
Expected: PASS (9 tests).
Then: `uv run ruff check src/bubbles/core/transcript.py tests/test_core_transcript.py && uv run ruff format --check src/bubbles/core/transcript.py tests/test_core_transcript.py && uv run mypy`
Expected: PASS. (If `ruff format --check` complains, run `uv run ruff format` on the two files and re-check.)

- [ ] **Step 5: Commit**

```bash
git add server/src/bubbles/core/transcript.py server/tests/test_core_transcript.py
git commit -m "feat(core): add pure transcript parser for turn/word counts"
```

---

## Task 3: Feedback repo + baseline `feedback` table

**Files:**
- Create: `server/src/bubbles/db/repo/feedback.py`
- Create: `server/tests/integration/test_repo_feedback.py`
- Modify: `server/tests/integration/fixtures/baseline.sql` (append `feedback` table)
- Modify: `server/tests/integration/conftest.py` (teardown list)

- [ ] **Step 1: Add the `feedback` table to baseline.sql**

In `server/tests/integration/fixtures/baseline.sql`, after the `session_entities` block (the current last table) and before any trailing content, append:

```sql
-- feedback (matches Documentation/db_schema.sql)
CREATE TABLE feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id uuid,
    log_id uuid,
    consultant_log_id uuid,
    feedback_type text,
    rating integer,
    value integer,
    comment text,
    idempotency_key text UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);
```

- [ ] **Step 2: Add `feedback` to the conftest teardown**

In `server/tests/integration/conftest.py`, the `DROP TABLE IF EXISTS` statement in the `pool` fixture teardown — add `feedback,` to the list (place it right after `DROP TABLE IF EXISTS ` so it drops before FK-referenced tables; order among siblings doesn't matter with `CASCADE`):

```python
            await con.execute(
                """
                DROP SCHEMA IF EXISTS auth CASCADE;
                DROP TABLE IF EXISTS feedback, session_entities, events, tasks,
                    user_rewards, rewards, user_achievements, achievements, xp_transactions,
                    user_quests, quest_definitions,
                    user_gamification, user_mistakes, memory, user_personas,
                    entity_relations, entities, sessions CASCADE;
                """
            )
```

(Tasks 3 and 4 both edit this list; Task 4 adds `session_analytics, coaching_reports, highlights`.)

- [ ] **Step 3: Write the failing integration test**

Create `server/tests/integration/test_repo_feedback.py`:

```python
"""Integration tests for the feedback repo."""

from __future__ import annotations

from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import feedback as feedback_repo

pytestmark = pytest.mark.integration


async def test_insert_and_find_by_idempotency_key(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        row = await feedback_repo.insert(
            conn,
            user_id=user_id,
            feedback_type="thumbs",
            value=1,
            comment="great",
            idempotency_key="abc-123",
        )
        assert row.user_id == user_id
        assert row.feedback_type == "thumbs"
        assert row.value == 1
        found = await feedback_repo.find_by_idempotency_key(conn, key="abc-123")
        assert found == row.id
        missing = await feedback_repo.find_by_idempotency_key(conn, key="nope")
        assert missing is None


async def test_duplicate_idempotency_key_raises_unique_violation(
    pool: asyncpg.Pool, user_id: UUID
) -> None:
    async with pool.acquire() as conn:
        await feedback_repo.insert(
            conn, user_id=user_id, feedback_type="star", value=5, idempotency_key="dup-1"
        )
        with pytest.raises(asyncpg.UniqueViolationError):
            await feedback_repo.insert(
                conn, user_id=user_id, feedback_type="star", value=4, idempotency_key="dup-1"
            )


async def test_insert_without_idempotency_key(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        row = await feedback_repo.insert(conn, user_id=user_id, feedback_type="text", comment="hi")
        assert row.idempotency_key is None
        assert row.value is None
```

- [ ] **Step 4: Run the test to verify it fails**

Run (from `server/`): `RUN_INTEGRATION=1 uv run pytest tests/integration/test_repo_feedback.py -q` (PowerShell: `$env:RUN_INTEGRATION=1; uv run pytest tests/integration/test_repo_feedback.py -q`)
Expected: FAIL — `ModuleNotFoundError: No module named 'bubbles.db.repo.feedback'` (or, if Docker is unavailable, the suite skips — then rely on the post-implementation gate and CI).

- [ ] **Step 5: Implement the feedback repo**

Create `server/src/bubbles/db/repo/feedback.py`:

```python
"""Feedback repo — user thumbs/star/text feedback rows."""

from __future__ import annotations

from uuid import UUID

import asyncpg

from bubbles.db.models import Feedback

_COLS = (
    "id, user_id, session_id, log_id, consultant_log_id, "
    "feedback_type, rating, value, comment, idempotency_key, created_at"
)


def _row(row: asyncpg.Record) -> Feedback:
    return Feedback(
        id=row["id"],
        user_id=row["user_id"],
        session_id=row["session_id"],
        log_id=row["log_id"],
        consultant_log_id=row["consultant_log_id"],
        feedback_type=row["feedback_type"],
        rating=row["rating"],
        value=row["value"],
        comment=row["comment"],
        idempotency_key=row["idempotency_key"],
        created_at=row["created_at"],
    )


async def find_by_idempotency_key(conn: asyncpg.Connection, *, key: str) -> UUID | None:
    row = await conn.fetchrow("SELECT id FROM feedback WHERE idempotency_key = $1", key)
    if row is None:
        return None
    out: UUID = row["id"]
    return out


async def insert(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    feedback_type: str,
    session_id: UUID | None = None,
    log_id: UUID | None = None,
    consultant_log_id: UUID | None = None,
    value: int | None = None,
    rating: int | None = None,
    comment: str | None = None,
    idempotency_key: str | None = None,
) -> Feedback:
    row = await conn.fetchrow(
        f"""
        INSERT INTO feedback (
            user_id, session_id, log_id, consultant_log_id,
            feedback_type, rating, value, comment, idempotency_key
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING {_COLS}
        """,
        user_id,
        session_id,
        log_id,
        consultant_log_id,
        feedback_type,
        rating,
        value,
        comment,
        idempotency_key,
    )
    assert row is not None
    return _row(row)
```

- [ ] **Step 6: Run the test to verify it passes (or skips cleanly)**

Run (from `server/`): `$env:RUN_INTEGRATION=1; uv run pytest tests/integration/test_repo_feedback.py -q` (only if Docker available — otherwise it skips).
Then always: `uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest -q`
Expected: ruff/mypy clean; pytest passes (integration suites skipped locally).

- [ ] **Step 7: Commit**

```bash
git add server/src/bubbles/db/repo/feedback.py server/tests/integration/test_repo_feedback.py server/tests/integration/fixtures/baseline.sql server/tests/integration/conftest.py
git commit -m "feat(repo): add feedback repo + baseline feedback table"
```

---

## Task 4: Analytics repo + baseline tables (`session_analytics`, `coaching_reports`, `highlights`)

**Files:**
- Create: `server/src/bubbles/db/repo/analytics.py`
- Create: `server/tests/integration/test_repo_analytics.py`
- Modify: `server/tests/integration/fixtures/baseline.sql` (append three tables)
- Modify: `server/tests/integration/conftest.py` (teardown list)

- [ ] **Step 1: Add the three tables to baseline.sql**

In `server/tests/integration/fixtures/baseline.sql`, after the `feedback` block added in Task 3, append:

```sql
-- session_analytics (matches Documentation/db_schema.sql; session_id is the PK)
CREATE TABLE session_analytics (
    session_id uuid NOT NULL PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    total_turns integer DEFAULT 0,
    user_word_count integer DEFAULT 0,
    assistant_word_count integer DEFAULT 0,
    average_latency_ms integer,
    topic_summary text,
    user_turns integer DEFAULT 0,
    others_turns integer DEFAULT 0,
    llm_turns integer DEFAULT 0,
    avg_advice_latency_ms numeric,
    total_duration_seconds numeric,
    memories_saved integer DEFAULT 0,
    events_extracted integer DEFAULT 0,
    highlights_created integer DEFAULT 0,
    avg_sentiment_score numeric,
    dominant_sentiment text,
    computed_at timestamptz NOT NULL DEFAULT now()
);

-- coaching_reports (matches Documentation/db_schema.sql)
CREATE TABLE coaching_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id uuid,
    report_content jsonb NOT NULL DEFAULT '{}'::jsonb,
    areas_of_improvement text[],
    model_used text,
    user_talk_pct double precision,
    others_talk_pct double precision,
    key_topics text[],
    key_decisions text[],
    action_items text[],
    follow_up_people text[],
    filler_words text[],
    filler_word_count integer DEFAULT 0,
    tone_summary text,
    engagement_trend text,
    suggestions text[],
    strengths text[],
    report_text text,
    generated_at timestamptz NOT NULL DEFAULT now()
);

-- highlights (written by the compute_session_analytics worker; read by digest)
CREATE TABLE highlights (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id uuid,
    highlight_type text,
    title text,
    body text,
    content text,
    created_at timestamptz DEFAULT now()
);
```

- [ ] **Step 2: Add the three tables to the conftest teardown**

In `server/tests/integration/conftest.py`, extend the `DROP TABLE IF EXISTS` list (already has `feedback,` from Task 3) to also include `session_analytics, coaching_reports, highlights`:

```python
                DROP TABLE IF EXISTS feedback, session_analytics, coaching_reports, highlights,
                    session_entities, events, tasks,
                    user_rewards, rewards, user_achievements, achievements, xp_transactions,
                    user_quests, quest_definitions,
                    user_gamification, user_mistakes, memory, user_personas,
                    entity_relations, entities, sessions CASCADE;
```

- [ ] **Step 3: Write the failing integration test**

Create `server/tests/integration/test_repo_analytics.py`:

```python
"""Integration tests for the analytics repo."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import asyncpg
import pytest

from bubbles.db.repo import analytics as analytics_repo

pytestmark = pytest.mark.integration


async def _new_session(conn: asyncpg.Connection, user_id: UUID) -> UUID:
    sid = uuid4()
    await conn.execute(
        "INSERT INTO sessions (id, user_id, status) VALUES ($1, $2, 'ended')", sid, user_id
    )
    return sid


async def test_upsert_and_get_session_analytics(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        sid = await _new_session(conn, user_id)
        await analytics_repo.upsert_session_analytics(
            conn,
            session_id=sid,
            user_id=user_id,
            total_turns=4,
            user_turns=2,
            others_turns=1,
            llm_turns=1,
            user_word_count=10,
            assistant_word_count=8,
            total_duration_seconds=120.0,
            memories_saved=3,
            events_extracted=1,
            highlights_created=2,
            topic_summary="a chat",
        )
        row = await analytics_repo.get_session_analytics(conn, session_id=sid)
        assert row is not None
        assert row.total_turns == 4
        assert row.user_word_count == 10
        assert row.memories_saved == 3
        assert row.topic_summary == "a chat"
        assert row.average_latency_ms is None
        assert row.avg_sentiment_score is None
        # conflict update
        await analytics_repo.upsert_session_analytics(
            conn,
            session_id=sid,
            user_id=user_id,
            total_turns=9,
            user_turns=5,
            others_turns=2,
            llm_turns=2,
            user_word_count=20,
            assistant_word_count=15,
            total_duration_seconds=240.0,
            memories_saved=4,
            events_extracted=2,
            highlights_created=3,
            topic_summary="updated",
        )
        row2 = await analytics_repo.get_session_analytics(conn, session_id=sid)
        assert row2 is not None
        assert row2.total_turns == 9
        assert row2.topic_summary == "updated"
        assert await analytics_repo.get_session_analytics(conn, session_id=uuid4()) is None


async def test_upsert_and_get_coaching_report(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        sid = await _new_session(conn, user_id)
        await analytics_repo.upsert_coaching_report(
            conn,
            session_id=sid,
            user_id=user_id,
            model_used="analytics.coaching",
            user_talk_pct=60.0,
            others_talk_pct=40.0,
            key_topics=["budget", "timeline"],
            key_decisions=["ship friday"],
            action_items=["email alice"],
            follow_up_people=["alice"],
            filler_words=["um", "like"],
            filler_word_count=7,
            tone_summary="warm",
            engagement_trend="rising",
            suggestions=["pause more"],
            strengths=["clear"],
            areas_of_improvement=["fillers"],
            report_text="Solid conversation.",
            report_content={"tone_clarity": 8, "tone_empathy": 7},
        )
        row = await analytics_repo.get_coaching_report(conn, session_id=sid)
        assert row is not None
        assert row.user_talk_pct == 60.0
        assert row.key_topics == ["budget", "timeline"]
        assert row.filler_word_count == 7
        assert row.report_content == {"tone_clarity": 8, "tone_empathy": 7}
        # re-upsert replaces in place (no duplicate row)
        await analytics_repo.upsert_coaching_report(
            conn,
            session_id=sid,
            user_id=user_id,
            model_used="analytics.coaching",
            user_talk_pct=55.0,
            others_talk_pct=45.0,
            key_topics=["new"],
            key_decisions=[],
            action_items=[],
            follow_up_people=[],
            filler_words=[],
            filler_word_count=0,
            tone_summary=None,
            engagement_trend=None,
            suggestions=[],
            strengths=[],
            areas_of_improvement=[],
            report_text=None,
            report_content={},
        )
        again = await analytics_repo.get_coaching_report(conn, session_id=sid)
        assert again is not None
        assert again.user_talk_pct == 55.0
        assert again.key_topics == ["new"]
        cnt = await conn.fetchval("SELECT count(*) FROM coaching_reports WHERE session_id = $1", sid)
        assert cnt == 1
        assert await analytics_repo.get_coaching_report(conn, session_id=uuid4()) is None


async def test_trends_since_window(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        recent_sid = await _new_session(conn, user_id)
        old_sid = await _new_session(conn, user_id)
        now = datetime.now(UTC)
        await conn.execute(
            "INSERT INTO session_analytics (session_id, user_id, total_turns, computed_at) "
            "VALUES ($1, $2, 3, $3)",
            recent_sid,
            user_id,
            now - timedelta(days=2),
        )
        await conn.execute(
            "INSERT INTO session_analytics (session_id, user_id, total_turns, computed_at) "
            "VALUES ($1, $2, 9, $3)",
            old_sid,
            user_id,
            now - timedelta(days=40),
        )
        rows = await analytics_repo.trends_since(conn, user_id=user_id, since=now - timedelta(days=14))
        assert [r["session_id"] for r in rows] == [recent_sid]


async def test_digest_reads(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with pool.acquire() as conn:
        now = datetime.now(UTC)
        sid = uuid4()
        await conn.execute(
            "INSERT INTO sessions (id, user_id, title, mode, status, created_at) "
            "VALUES ($1, $2, 'recent', 'live_wingman', 'ended', $3)",
            sid,
            user_id,
            now - timedelta(hours=1),
        )
        old_sid = uuid4()
        await conn.execute(
            "INSERT INTO sessions (id, user_id, title, created_at) VALUES ($1, $2, 'old', $3)",
            old_sid,
            user_id,
            now - timedelta(days=30),
        )
        await conn.execute(
            "INSERT INTO tasks (user_id, title, status) VALUES ($1, 'todo', 'pending'), "
            "($1, 'done-task', 'done')",
            user_id,
        )
        await conn.execute(
            "INSERT INTO entities (user_id, display_name, entity_type, mention_count) "
            "VALUES ($1, 'Alice', 'person', 9), ($1, 'Bob', 'person', 2)",
            user_id,
        )
        await conn.execute(
            "INSERT INTO highlights (user_id, session_id, highlight_type, title, body, created_at) "
            "VALUES ($1, $2, 'insight', 'h1', 'body1', $3)",
            user_id,
            sid,
            now - timedelta(hours=2),
        )
        since = now - timedelta(days=7)
        sessions = await analytics_repo.digest_sessions(conn, user_id=user_id, since=since)
        assert [r["title"] for r in sessions] == ["recent"]
        tasks = await analytics_repo.digest_pending_tasks(conn, user_id=user_id)
        assert [r["title"] for r in tasks] == ["todo"]
        ents = await analytics_repo.digest_top_entities(conn, user_id=user_id)
        assert [r["display_name"] for r in ents] == ["Alice", "Bob"]
        hls = await analytics_repo.digest_recent_highlights(conn, user_id=user_id, since=since)
        assert [r["title"] for r in hls] == ["h1"]
```

> Note: `entities` columns — `display_name`, `entity_type`, `mention_count` — must exist in `baseline.sql`'s `entities` table. They already do (the entities repo selects them). If `mention_count` is absent, the implementer should add the missing column to the baseline `entities` table; do **not** invent new columns beyond what the entities repo already references.

- [ ] **Step 4: Run the test to verify it fails**

Run (from `server/`): `$env:RUN_INTEGRATION=1; uv run pytest tests/integration/test_repo_analytics.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'bubbles.db.repo.analytics'` (or skip if no Docker).

- [ ] **Step 5: Implement the analytics repo**

Create `server/src/bubbles/db/repo/analytics.py`:

```python
"""Analytics repo — session_analytics, coaching_reports, trends, digest reads.

``coaching_reports`` has no unique constraint on ``session_id`` in the live
schema, so ``upsert_coaching_report`` does DELETE-then-INSERT inside the
caller's transaction (the worker wraps its writes in a UnitOfWork). Safe
because the worker is idempotent per session.
"""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any
from uuid import UUID

import asyncpg

from bubbles.db.models import CoachingReport, SessionAnalytics

_SA_COLS = (
    "session_id, user_id, total_turns, user_turns, others_turns, llm_turns, "
    "user_word_count, assistant_word_count, average_latency_ms, avg_advice_latency_ms, "
    "total_duration_seconds, memories_saved, events_extracted, highlights_created, "
    "avg_sentiment_score, dominant_sentiment, topic_summary, computed_at"
)

_CR_COLS = (
    "id, user_id, session_id, model_used, user_talk_pct, others_talk_pct, "
    "key_topics, key_decisions, action_items, follow_up_people, filler_words, "
    "filler_word_count, tone_summary, engagement_trend, suggestions, strengths, "
    "areas_of_improvement, report_text, report_content, generated_at"
)


def _list(value: Any) -> list[str]:
    if not value:
        return []
    return [str(v) for v in value]


def _int(value: Any) -> int:
    return int(value) if value is not None else 0


def _float(value: Any) -> float | None:
    return float(value) if value is not None else None


def _session_analytics(row: asyncpg.Record) -> SessionAnalytics:
    return SessionAnalytics(
        session_id=row["session_id"],
        user_id=row["user_id"],
        total_turns=_int(row["total_turns"]),
        user_turns=_int(row["user_turns"]),
        others_turns=_int(row["others_turns"]),
        llm_turns=_int(row["llm_turns"]),
        user_word_count=_int(row["user_word_count"]),
        assistant_word_count=_int(row["assistant_word_count"]),
        average_latency_ms=row["average_latency_ms"],
        avg_advice_latency_ms=_float(row["avg_advice_latency_ms"]),
        total_duration_seconds=_float(row["total_duration_seconds"]),
        memories_saved=_int(row["memories_saved"]),
        events_extracted=_int(row["events_extracted"]),
        highlights_created=_int(row["highlights_created"]),
        avg_sentiment_score=_float(row["avg_sentiment_score"]),
        dominant_sentiment=row["dominant_sentiment"],
        topic_summary=row["topic_summary"],
        computed_at=row["computed_at"],
    )


def _coaching_report(row: asyncpg.Record) -> CoachingReport:
    raw_content = row["report_content"]
    if isinstance(raw_content, str):
        content: dict[str, Any] = json.loads(raw_content)
    elif raw_content is None:
        content = {}
    else:
        content = dict(raw_content)
    return CoachingReport(
        id=row["id"],
        user_id=row["user_id"],
        session_id=row["session_id"],
        model_used=row["model_used"],
        user_talk_pct=_float(row["user_talk_pct"]),
        others_talk_pct=_float(row["others_talk_pct"]),
        key_topics=_list(row["key_topics"]),
        key_decisions=_list(row["key_decisions"]),
        action_items=_list(row["action_items"]),
        follow_up_people=_list(row["follow_up_people"]),
        filler_words=_list(row["filler_words"]),
        filler_word_count=_int(row["filler_word_count"]),
        tone_summary=row["tone_summary"],
        engagement_trend=row["engagement_trend"],
        suggestions=_list(row["suggestions"]),
        strengths=_list(row["strengths"]),
        areas_of_improvement=_list(row["areas_of_improvement"]),
        report_text=row["report_text"],
        report_content=content,
        generated_at=row["generated_at"],
    )


# --- session_analytics -----------------------------------------------------


async def get_session_analytics(
    conn: asyncpg.Connection, *, session_id: UUID
) -> SessionAnalytics | None:
    row = await conn.fetchrow(
        f"SELECT {_SA_COLS} FROM session_analytics WHERE session_id = $1", session_id
    )
    return _session_analytics(row) if row is not None else None


async def upsert_session_analytics(
    conn: asyncpg.Connection,
    *,
    session_id: UUID,
    user_id: UUID,
    total_turns: int,
    user_turns: int,
    others_turns: int,
    llm_turns: int,
    user_word_count: int,
    assistant_word_count: int,
    total_duration_seconds: float | None,
    memories_saved: int,
    events_extracted: int,
    highlights_created: int,
    topic_summary: str | None,
) -> None:
    await conn.execute(
        """
        INSERT INTO session_analytics (
            session_id, user_id, total_turns, user_turns, others_turns, llm_turns,
            user_word_count, assistant_word_count, total_duration_seconds,
            memories_saved, events_extracted, highlights_created, topic_summary, computed_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, now())
        ON CONFLICT (session_id) DO UPDATE SET
            user_id = EXCLUDED.user_id,
            total_turns = EXCLUDED.total_turns,
            user_turns = EXCLUDED.user_turns,
            others_turns = EXCLUDED.others_turns,
            llm_turns = EXCLUDED.llm_turns,
            user_word_count = EXCLUDED.user_word_count,
            assistant_word_count = EXCLUDED.assistant_word_count,
            total_duration_seconds = EXCLUDED.total_duration_seconds,
            memories_saved = EXCLUDED.memories_saved,
            events_extracted = EXCLUDED.events_extracted,
            highlights_created = EXCLUDED.highlights_created,
            topic_summary = EXCLUDED.topic_summary,
            computed_at = now()
        """,
        session_id,
        user_id,
        total_turns,
        user_turns,
        others_turns,
        llm_turns,
        user_word_count,
        assistant_word_count,
        total_duration_seconds,
        memories_saved,
        events_extracted,
        highlights_created,
        topic_summary,
    )


# --- coaching_reports ------------------------------------------------------


async def get_coaching_report(
    conn: asyncpg.Connection, *, session_id: UUID
) -> CoachingReport | None:
    row = await conn.fetchrow(
        f"SELECT {_CR_COLS} FROM coaching_reports WHERE session_id = $1 "
        "ORDER BY generated_at DESC LIMIT 1",
        session_id,
    )
    return _coaching_report(row) if row is not None else None


async def upsert_coaching_report(
    conn: asyncpg.Connection,
    *,
    session_id: UUID,
    user_id: UUID,
    model_used: str | None,
    user_talk_pct: float | None,
    others_talk_pct: float | None,
    key_topics: list[str],
    key_decisions: list[str],
    action_items: list[str],
    follow_up_people: list[str],
    filler_words: list[str],
    filler_word_count: int,
    tone_summary: str | None,
    engagement_trend: str | None,
    suggestions: list[str],
    strengths: list[str],
    areas_of_improvement: list[str],
    report_text: str | None,
    report_content: dict[str, Any],
) -> None:
    await conn.execute("DELETE FROM coaching_reports WHERE session_id = $1", session_id)
    await conn.execute(
        """
        INSERT INTO coaching_reports (
            session_id, user_id, model_used, user_talk_pct, others_talk_pct,
            key_topics, key_decisions, action_items, follow_up_people, filler_words,
            filler_word_count, tone_summary, engagement_trend, suggestions, strengths,
            areas_of_improvement, report_text, report_content, generated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
                $16, $17, $18::jsonb, now())
        """,
        session_id,
        user_id,
        model_used,
        user_talk_pct,
        others_talk_pct,
        key_topics,
        key_decisions,
        action_items,
        follow_up_people,
        filler_words,
        filler_word_count,
        tone_summary,
        engagement_trend,
        suggestions,
        strengths,
        areas_of_improvement,
        report_text,
        json.dumps(report_content),
    )


# --- trends ----------------------------------------------------------------


async def trends_since(
    conn: asyncpg.Connection, *, user_id: UUID, since: datetime
) -> list[asyncpg.Record]:
    return list(
        await conn.fetch(
            """
            SELECT session_id, total_turns, user_word_count, assistant_word_count,
                   avg_sentiment_score, total_duration_seconds, computed_at
            FROM session_analytics
            WHERE user_id = $1 AND computed_at >= $2
            ORDER BY computed_at DESC
            """,
            user_id,
            since,
        )
    )


# --- digest reads ----------------------------------------------------------


async def digest_sessions(
    conn: asyncpg.Connection, *, user_id: UUID, since: datetime, limit: int = 20
) -> list[asyncpg.Record]:
    return list(
        await conn.fetch(
            """
            SELECT id, title, mode, status, created_at, summary
            FROM sessions
            WHERE user_id = $1 AND created_at >= $2 AND deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT $3
            """,
            user_id,
            since,
            limit,
        )
    )


async def digest_pending_tasks(
    conn: asyncpg.Connection, *, user_id: UUID, limit: int = 10
) -> list[asyncpg.Record]:
    return list(
        await conn.fetch(
            """
            SELECT id, title, status, priority
            FROM tasks
            WHERE user_id = $1 AND status = 'pending'
            ORDER BY created_at DESC
            LIMIT $2
            """,
            user_id,
            limit,
        )
    )


async def digest_top_entities(
    conn: asyncpg.Connection, *, user_id: UUID, limit: int = 5
) -> list[asyncpg.Record]:
    return list(
        await conn.fetch(
            """
            SELECT id, display_name, entity_type, mention_count
            FROM entities
            WHERE user_id = $1 AND deleted_at IS NULL
            ORDER BY mention_count DESC NULLS LAST
            LIMIT $2
            """,
            user_id,
            limit,
        )
    )


async def digest_recent_highlights(
    conn: asyncpg.Connection, *, user_id: UUID, since: datetime, limit: int = 5
) -> list[asyncpg.Record]:
    return list(
        await conn.fetch(
            """
            SELECT id, highlight_type, title, body
            FROM highlights
            WHERE user_id = $1 AND created_at >= $2
            ORDER BY created_at DESC
            LIMIT $3
            """,
            user_id,
            since,
            limit,
        )
    )
```

> If `entities` in `baseline.sql` lacks `deleted_at` or `mention_count`, add those columns to the baseline `entities` table to match what the entities repo already uses — check `server/src/bubbles/db/repo/entities.py` for the exact column set before editing. (The entities repo already references `deleted_at`; if `digest_top_entities`'s `mention_count` isn't there, add `mention_count integer DEFAULT 0`.)

- [ ] **Step 6: Run the test to verify it passes (or skips), then the gate**

Run (from `server/`): `$env:RUN_INTEGRATION=1; uv run pytest tests/integration/test_repo_analytics.py -q` (if Docker available).
Then always: `uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest -q`
Expected: ruff/mypy clean; pytest passes.

- [ ] **Step 7: Commit**

```bash
git add server/src/bubbles/db/repo/analytics.py server/tests/integration/test_repo_analytics.py server/tests/integration/fixtures/baseline.sql server/tests/integration/conftest.py
git commit -m "feat(repo): add analytics repo + baseline session_analytics/coaching_reports/highlights tables"
```

---

## Task 5: Wire schemas

**Files:**
- Modify: `server/src/bubbles/api/v1/_schemas.py` (append a new section)

- [ ] **Step 1: Append the analytics schemas**

`_schemas.py` already imports `from datetime import date, datetime`, `from typing import Any, Literal`, `from uuid import UUID`, `from pydantic import BaseModel, ConfigDict, Field`, and defines `_Base`. Append at the end of the file:

```python
# --- analytics: feedback ---------------------------------------------------


class SaveFeedbackRequest(_Base):
    session_id: UUID | None = None
    session_log_id: UUID | None = None
    consultant_log_id: UUID | None = None
    feedback_type: Literal["thumbs", "star", "text"]
    value: int | None = Field(default=None, ge=-1, le=5)
    comment: str | None = Field(default=None, max_length=1000)
    idempotency_key: str | None = Field(default=None, max_length=200)


class SaveFeedbackResponse(_Base):
    status: Literal["ok"]
    idempotent: bool = False


# --- analytics: session analytics ------------------------------------------


class SentimentPoint(_Base):
    turn_index: int
    score: float | None
    label: str | None


class SessionAnalyticsOut(_Base):
    session_id: UUID
    total_turns: int
    user_turns: int
    others_turns: int
    llm_turns: int
    user_word_count: int
    assistant_word_count: int
    average_latency_ms: int | None
    avg_advice_latency_ms: float | None
    total_duration_seconds: float | None
    memories_saved: int
    events_extracted: int
    highlights_created: int
    avg_sentiment_score: float | None
    dominant_sentiment: str | None
    topic_summary: str | None
    sentiment_trend: list[SentimentPoint]
    computed_at: datetime


# --- analytics: coaching report --------------------------------------------


class CoachingReportOut(_Base):
    session_id: UUID | None
    model_used: str | None
    user_talk_pct: float | None
    others_talk_pct: float | None
    key_topics: list[str]
    key_decisions: list[str]
    action_items: list[str]
    follow_up_people: list[str]
    filler_words: list[str]
    filler_word_count: int
    tone_summary: str | None
    engagement_trend: str | None
    suggestions: list[str]
    strengths: list[str]
    areas_of_improvement: list[str]
    report_text: str | None
    tone_scores: dict[str, int]
    generated_at: datetime


# --- analytics: digest -----------------------------------------------------


class DigestSession(_Base):
    id: UUID
    title: str | None
    mode: str | None
    status: str | None
    created_at: datetime
    summary: str | None


class DigestTask(_Base):
    id: UUID
    title: str | None
    status: str | None
    priority: str | None


class DigestEntity(_Base):
    id: UUID
    display_name: str | None
    entity_type: str | None
    mention_count: int | None


class DigestHighlight(_Base):
    id: UUID
    highlight_type: str | None
    title: str | None
    body: str | None


class DigestResponse(_Base):
    period: Literal["day", "week"]
    user_id: UUID
    sessions_count: int
    recent_sessions: list[DigestSession]
    pending_tasks: list[DigestTask]
    top_entities: list[DigestEntity]
    recent_highlights: list[DigestHighlight]


# --- analytics: communication trends ---------------------------------------


class WeeklyTrendOut(_Base):
    week: str
    sessions: int
    total_turns: int
    user_words: int
    ai_words: int
    avg_sentiment_score: float | None
    total_duration_seconds: float


class CommunicationTrendsResponse(_Base):
    user_id: UUID
    weeks_requested: int
    weeks_available: int
    trends: list[WeeklyTrendOut]
```

- [ ] **Step 2: Verify lint + types**

Run (from `server/`): `uv run ruff check src/bubbles/api/v1/_schemas.py && uv run ruff format --check src/bubbles/api/v1/_schemas.py && uv run mypy`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add server/src/bubbles/api/v1/_schemas.py
git commit -m "feat(schemas): add analytics wire schemas"
```

---

## Task 6: Coaching-report prompt + LLM task chain + extraction helper

**Files:**
- Create: `server/src/bubbles/ai/prompts/coaching/report.jinja`
- Modify: `server/src/bubbles/ai/router.py` (`DEFAULT_CHAINS`)
- Modify: `server/src/bubbles/ai/extraction.py` (add `generate_coaching_report`)

- [ ] **Step 1: Create the prompt template**

Create directory `server/src/bubbles/ai/prompts/coaching/` and file `server/src/bubbles/ai/prompts/coaching/report.jinja`:

```jinja
You are an expert communication coach. Analyse the conversation transcript below and produce a structured coaching report.

Return ONLY a JSON object with exactly these fields:
- "user_talk_pct": float, the percentage (0-100) of words spoken by the user
- "others_talk_pct": float, the percentage (0-100) of words spoken by everyone else
- "key_topics": array of up to 5 short strings
- "key_decisions": array of up to 5 short strings
- "action_items": array of up to 5 short strings
- "follow_up_people": array of up to 5 short strings (names of people to follow up with)
- "filler_words": array of up to 5 short strings (filler words the user used, e.g. "um", "like")
- "filler_word_count": integer, total count of filler words used by the user
- "tone_summary": string, one sentence describing the user's overall tone
- "engagement_trend": string, one short phrase (e.g. "rising", "steady", "declining")
- "report_text": string, a short (2-4 sentence) narrative summary of the user's communication
- "suggestions": array of up to 5 short actionable strings
- "strengths": array of up to 5 short strings
- "areas_of_improvement": array of up to 5 short strings
- "tone_aggression": integer 0-10
- "tone_empathy": integer 0-10
- "tone_analytical": integer 0-10
- "tone_confidence": integer 0-10
- "tone_clarity": integer 0-10

If the transcript is too short or empty, return zeros / empty arrays / empty strings. Respond with JSON only — no markdown, no commentary.

Transcript:
{{ transcript }}
```

- [ ] **Step 2: Add the LLM task chain**

In `server/src/bubbles/ai/router.py`, find `DEFAULT_CHAINS` and add an `analytics.coaching` entry (place it after the `grammar.correct` line):

```python
DEFAULT_CHAINS: tuple[TaskChain, ...] = (
    TaskChain("consultant.stream", ("gemini", "cerebras", "groq"), max_tokens=1024),
    TaskChain("consultant.complete", ("gemini", "cerebras", "groq"), max_tokens=1024),
    TaskChain("wingman.json", ("cerebras", "groq", "gemini"), temperature=0.2, max_tokens=600),
    TaskChain("wingman.short", ("cerebras", "groq"), temperature=0.3, max_tokens=300),
    TaskChain("grammar.correct", ("groq", "cerebras"), temperature=0.0, max_tokens=400),
    TaskChain("analytics.coaching", ("gemini", "cerebras", "groq"), temperature=0.3, max_tokens=900),
)
```

- [ ] **Step 3: Add `generate_coaching_report` to `extraction.py`**

In `server/src/bubbles/ai/extraction.py`, after `correct_grammar`, append:

```python
async def generate_coaching_report(router: LLMRouter, transcript: str) -> dict[str, Any]:
    prompt = render("coaching/report.jinja", transcript=_truncate(transcript))
    completion = await router.complete(
        "analytics.coaching",
        [ChatMessage(role=Role.user, content=prompt)],
        response_format="json",
    )
    return _parse_json(completion.text)
```

(`_truncate`, `_parse_json`, `render`, `ChatMessage`, `Role`, `LLMRouter`, `Any` are all already imported in that module.)

- [ ] **Step 4: Verify it loads + lint + types**

Run (from `server/`):
```
uv run python -c "from bubbles.ai.extraction import generate_coaching_report; from bubbles.ai.prompts.loader import render; print(render('coaching/report.jinja', transcript='User: hi')[:40])"
uv run ruff check src/bubbles/ai/router.py src/bubbles/ai/extraction.py && uv run ruff format --check src/bubbles/ai/router.py src/bubbles/ai/extraction.py && uv run mypy
```
Expected: prints the first 40 chars of the rendered prompt; ruff/mypy clean.

- [ ] **Step 5: Commit**

```bash
git add server/src/bubbles/ai/prompts/coaching/report.jinja server/src/bubbles/ai/router.py server/src/bubbles/ai/extraction.py
git commit -m "feat(ai): add coaching-report prompt, analytics.coaching task chain, generate_coaching_report"
```

---

## Task 7: Worker enhancement — populate `session_analytics` + `coaching_reports`

**Files:**
- Modify: `server/src/bubbles/workers/jobs/compute_session_analytics.py`
- Test: `server/tests/integration/test_job_compute_session_analytics.py` (create if absent; otherwise extend)

- [ ] **Step 1: Rewrite the worker job**

Replace the entire contents of `server/src/bubbles/workers/jobs/compute_session_analytics.py` with:

```python
"""Post-session analytics: title, summary, highlights, metrics row, coaching report."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any
from uuid import UUID

from bubbles.ai.extraction import (
    extract_highlights,
    generate_coaching_report,
    generate_summary,
    generate_title,
)
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.core.transcript import parse_transcript
from bubbles.db.repo import analytics as analytics_repo
from bubbles.db.uow import UnitOfWork

if TYPE_CHECKING:
    from bubbles.workers.arq_settings import WorkerCtx

log = get_logger(__name__)

_TONE_KEYS = (
    "tone_aggression",
    "tone_empathy",
    "tone_analytical",
    "tone_confidence",
    "tone_clarity",
)


def _as_float(value: Any) -> float | None:
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def _as_str(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _as_str_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(v).strip() for v in value if str(v).strip()][:5]


def _as_int(value: Any) -> int:
    try:
        return int(value) if value is not None else 0
    except (TypeError, ValueError):
        return 0


async def run(
    ctx: dict[str, Any],
    *,
    user_id: str,
    session_id: str,
    transcript: str,
) -> dict[str, Any]:
    bub: WorkerCtx = ctx["bubbles"]
    sess_uuid = UUID(session_id)
    user_uuid = UUID(user_id)

    title = ""
    summary = ""
    highlights: list[dict[str, Any]] = []
    coaching: dict[str, Any] | None = None

    try:
        title = await generate_title(bub.ai.router, transcript)
    except UpstreamUnavailable as exc:
        log.warning("title_upstream", error=str(exc))
    try:
        summary = await generate_summary(bub.ai.router, transcript)
    except UpstreamUnavailable as exc:
        log.warning("summary_upstream", error=str(exc))
    try:
        h_payload = await extract_highlights(bub.ai.router, transcript)
        h_raw = h_payload.get("highlights") or []
        highlights = [h for h in h_raw if isinstance(h, dict)][:5]
    except UpstreamUnavailable as exc:
        log.warning("highlights_upstream", error=str(exc))
    try:
        coaching = await generate_coaching_report(bub.ai.router, transcript)
    except UpstreamUnavailable as exc:
        log.warning("coaching_upstream", error=str(exc))

    stats = parse_transcript(transcript)

    async with UnitOfWork(bub.pool) as uow:
        await uow.conn.execute(
            """
            UPDATE sessions
            SET title = COALESCE(NULLIF($2, ''), title),
                summary = COALESCE(NULLIF($3, ''), summary)
            WHERE id = $1 AND user_id = $4
            """,
            sess_uuid,
            title,
            summary,
            user_uuid,
        )
        for h in highlights:
            content = (h.get("body") or h.get("title") or "").strip()
            if not content:
                continue
            await uow.conn.execute(
                """
                INSERT INTO highlights
                    (user_id, session_id, highlight_type, title, body, content)
                VALUES ($1, $2, $3, $4, $5, $6)
                """,
                user_uuid,
                sess_uuid,
                str(h.get("type") or "insight"),
                str(h.get("title") or "")[:120] or None,
                str(h.get("body") or "")[:600] or None,
                content[:2000],
            )

        sess_row = await uow.conn.fetchrow(
            "SELECT start_time, ended_at, end_time FROM sessions WHERE id = $1", sess_uuid
        )
        duration: float | None = None
        if sess_row is not None and sess_row["start_time"] is not None:
            end_ts = sess_row["ended_at"] or sess_row["end_time"]
            if end_ts is not None:
                duration = max(0.0, (end_ts - sess_row["start_time"]).total_seconds())
        memories_saved = (
            await uow.conn.fetchval("SELECT count(*) FROM memory WHERE session_id = $1", sess_uuid)
            or 0
        )
        events_extracted = (
            await uow.conn.fetchval("SELECT count(*) FROM events WHERE session_id = $1", sess_uuid)
            or 0
        )
        await analytics_repo.upsert_session_analytics(
            uow.conn,
            session_id=sess_uuid,
            user_id=user_uuid,
            total_turns=stats.total_turns,
            user_turns=stats.user_turns,
            others_turns=stats.others_turns,
            llm_turns=stats.llm_turns,
            user_word_count=stats.user_words,
            assistant_word_count=stats.assistant_words,
            total_duration_seconds=duration,
            memories_saved=int(memories_saved),
            events_extracted=int(events_extracted),
            highlights_created=len(highlights),
            topic_summary=summary or None,
        )

        if coaching is not None:
            report_content = {
                k: _as_int(coaching.get(k)) for k in _TONE_KEYS if coaching.get(k) is not None
            }
            await analytics_repo.upsert_coaching_report(
                uow.conn,
                session_id=sess_uuid,
                user_id=user_uuid,
                model_used="analytics.coaching",
                user_talk_pct=_as_float(coaching.get("user_talk_pct")),
                others_talk_pct=_as_float(coaching.get("others_talk_pct")),
                key_topics=_as_str_list(coaching.get("key_topics")),
                key_decisions=_as_str_list(coaching.get("key_decisions")),
                action_items=_as_str_list(coaching.get("action_items")),
                follow_up_people=_as_str_list(coaching.get("follow_up_people")),
                filler_words=_as_str_list(coaching.get("filler_words")),
                filler_word_count=_as_int(coaching.get("filler_word_count")),
                tone_summary=_as_str(coaching.get("tone_summary")),
                engagement_trend=_as_str(coaching.get("engagement_trend")),
                suggestions=_as_str_list(coaching.get("suggestions")),
                strengths=_as_str_list(coaching.get("strengths")),
                areas_of_improvement=_as_str_list(coaching.get("areas_of_improvement")),
                report_text=_as_str(coaching.get("report_text")),
                report_content=report_content,
            )

    log.info(
        "session_analytics_done",
        session=session_id,
        title_set=bool(title),
        summary_set=bool(summary),
        highlights=len(highlights),
        coaching=coaching is not None,
        turns=stats.total_turns,
    )
    return {
        "title": title,
        "summary": summary,
        "highlights": len(highlights),
        "coaching": coaching is not None,
        "turns": stats.total_turns,
    }
```

- [ ] **Step 2: Write/extend the integration test**

Create (or extend) `server/tests/integration/test_job_compute_session_analytics.py`:

```python
"""Integration test for the compute_session_analytics worker job."""

from __future__ import annotations

from typing import Any
from uuid import UUID, uuid4

import asyncpg
import pytest

from bubbles.db.repo import analytics as analytics_repo
from bubbles.workers.jobs import compute_session_analytics

pytestmark = pytest.mark.integration


class _FakeCompletion:
    def __init__(self, text: str) -> None:
        self.text = text
        self.raw: dict[str, Any] = {}


class _FakeRouter:
    """Returns canned JSON for whichever task is asked for."""

    async def complete(self, task: str, messages: Any, **kwargs: Any) -> _FakeCompletion:
        if task == "analytics.coaching":
            return _FakeCompletion(
                '{"user_talk_pct": 60.0, "others_talk_pct": 40.0, "key_topics": ["budget"], '
                '"key_decisions": [], "action_items": ["email alice"], "follow_up_people": ["alice"], '
                '"filler_words": ["um"], "filler_word_count": 3, "tone_summary": "warm", '
                '"engagement_trend": "rising", "report_text": "Good chat.", "suggestions": ["pause"], '
                '"strengths": ["clear"], "areas_of_improvement": ["fillers"], "tone_clarity": 8, '
                '"tone_empathy": 7}'
            )
        if task == "wingman.json":
            # title / summary / highlights all go through wingman.json in extraction.py
            return _FakeCompletion('{"title": "T", "summary": "S", "highlights": []}')
        return _FakeCompletion("{}")


class _FakeAI:
    router = _FakeRouter()


class _FakeCtxBubbles:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self.pool = pool
        self.ai = _FakeAI()


async def test_worker_writes_analytics_and_coaching(pool: asyncpg.Pool, user_id: UUID) -> None:
    sid = uuid4()
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO sessions (id, user_id, status) VALUES ($1, $2, 'ended')", sid, user_id
        )
    transcript = "User: hi how are you\nAI: I am well thanks\nUser: great to hear"
    ctx = {"bubbles": _FakeCtxBubbles(pool)}
    result = await compute_session_analytics.run(
        ctx, user_id=str(user_id), session_id=str(sid), transcript=transcript
    )
    assert result["coaching"] is True
    assert result["turns"] == 3
    async with pool.acquire() as conn:
        sa = await analytics_repo.get_session_analytics(conn, session_id=sid)
        assert sa is not None
        assert sa.total_turns == 3
        assert sa.user_turns == 2
        assert sa.llm_turns == 1
        assert sa.user_word_count == 8
        assert sa.assistant_word_count == 4
        cr = await analytics_repo.get_coaching_report(conn, session_id=sid)
        assert cr is not None
        assert cr.user_talk_pct == 60.0
        assert cr.filler_word_count == 3
        assert cr.report_content == {"tone_clarity": 8, "tone_empathy": 7}
```

> If a `test_job_compute_session_analytics.py` already exists with different fakes, keep its existing tests and add `test_worker_writes_analytics_and_coaching`, adapting the fake-router shape to whatever the file already uses.

- [ ] **Step 3: Run the gate**

Run (from `server/`):
```
$env:RUN_INTEGRATION=1; uv run pytest tests/integration/test_job_compute_session_analytics.py -q   # if Docker available
uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest -q
```
Expected: ruff/mypy clean; pytest passes.

- [ ] **Step 4: Commit**

```bash
git add server/src/bubbles/workers/jobs/compute_session_analytics.py server/tests/integration/test_job_compute_session_analytics.py
git commit -m "feat(worker): compute_session_analytics writes session_analytics + coaching_reports rows"
```

---

## Task 8: Route module `api/v1/analytics.py` (5 endpoints + week grouping)

**Files:**
- Create: `server/src/bubbles/api/v1/analytics.py`
- Modify: `server/src/bubbles/api/router.py`
- Test: `server/tests/test_analytics_week_grouping.py` (unit)
- Test: `server/tests/integration/test_routes_analytics.py` (integration)

- [ ] **Step 1: Write the failing unit test for week grouping**

Create `server/tests/test_analytics_week_grouping.py`:

```python
"""Unit tests for the ISO-week grouping helper used by communication_trends."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from bubbles.api.v1.analytics import _group_by_week


def _rec(computed_at: datetime, **kw: object) -> dict[str, object]:
    base: dict[str, object] = {
        "total_turns": 0,
        "user_word_count": 0,
        "assistant_word_count": 0,
        "avg_sentiment_score": None,
        "total_duration_seconds": 0,
        "computed_at": computed_at,
    }
    base.update(kw)
    return base


def test_empty_input() -> None:
    assert _group_by_week([]) == []


def test_single_row() -> None:
    rows = [_rec(datetime(2026, 5, 12, tzinfo=UTC), total_turns=5, user_word_count=10)]
    out = _group_by_week(rows)
    assert len(out) == 1
    assert out[0].week == "2026-W20"
    assert out[0].sessions == 1
    assert out[0].total_turns == 5
    assert out[0].user_words == 10
    assert out[0].avg_sentiment_score is None


def test_multiple_rows_same_week_are_aggregated() -> None:
    d1 = datetime(2026, 5, 11, tzinfo=UTC)
    d2 = datetime(2026, 5, 13, tzinfo=UTC)
    rows = [
        _rec(d1, total_turns=3, user_word_count=5, assistant_word_count=4, avg_sentiment_score=0.2,
             total_duration_seconds=60),
        _rec(d2, total_turns=7, user_word_count=15, assistant_word_count=6, avg_sentiment_score=0.6,
             total_duration_seconds=90),
    ]
    out = _group_by_week(rows)
    assert len(out) == 1
    w = out[0]
    assert w.week == "2026-W20"
    assert w.sessions == 2
    assert w.total_turns == 10
    assert w.user_words == 20
    assert w.ai_words == 10
    assert w.total_duration_seconds == 150.0
    assert w.avg_sentiment_score == pytest.approx(0.4)


def test_rows_spanning_weeks_sorted_newest_first() -> None:
    early = datetime(2026, 5, 4, tzinfo=UTC)   # 2026-W19
    late = datetime(2026, 5, 12, tzinfo=UTC)   # 2026-W20
    out = _group_by_week([_rec(early), _rec(late)])
    assert [w.week for w in out] == ["2026-W20", "2026-W19"]


def test_null_sentiment_ignored_in_average() -> None:
    d = datetime(2026, 5, 12, tzinfo=UTC)
    rows = [_rec(d, avg_sentiment_score=None), _rec(d, avg_sentiment_score=0.5)]
    out = _group_by_week(rows)
    assert out[0].avg_sentiment_score == 0.5
```

- [ ] **Step 2: Run the unit test to verify it fails**

Run (from `server/`): `uv run pytest tests/test_analytics_week_grouping.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'bubbles.api.v1.analytics'`.

- [ ] **Step 3: Implement the route module**

Create `server/src/bubbles/api/v1/analytics.py`:

```python
"""Analytics read endpoints + feedback write.

- POST /v1/save_feedback                       — record user feedback (idempotent)
- GET  /v1/session_analytics/{session_id}      — cached per-session metrics row
- GET  /v1/coaching_report/{session_id}        — cached per-session coaching report
- GET  /v1/digest/{user_id}                    — recent activity digest (day|week)
- GET  /v1/communication_trends/{user_id}      — session_analytics aggregated by ISO week

The metrics row and coaching report are written by the ``compute_session_analytics``
worker; until it has run for a session these GETs return 404.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Query

from bubbles.api.v1._schemas import (
    CoachingReportOut,
    CommunicationTrendsResponse,
    DigestEntity,
    DigestHighlight,
    DigestResponse,
    DigestSession,
    DigestTask,
    SaveFeedbackRequest,
    SaveFeedbackResponse,
    SessionAnalyticsOut,
    WeeklyTrendOut,
)
from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import NotFound
from bubbles.db.repo import analytics as analytics_repo
from bubbles.db.repo import feedback as feedback_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep

router = APIRouter(tags=["analytics"])


def _group_by_week(rows: list[asyncpg.Record]) -> list[WeeklyTrendOut]:
    buckets: dict[str, dict[str, float | int]] = {}
    sentiment: dict[str, tuple[float, int]] = {}
    for r in rows:
        iso = r["computed_at"].isocalendar()
        key = f"{iso[0]}-W{iso[1]:02d}"
        b = buckets.setdefault(
            key,
            {"sessions": 0, "total_turns": 0, "user_words": 0, "ai_words": 0, "duration": 0.0},
        )
        b["sessions"] = int(b["sessions"]) + 1
        b["total_turns"] = int(b["total_turns"]) + int(r["total_turns"] or 0)
        b["user_words"] = int(b["user_words"]) + int(r["user_word_count"] or 0)
        b["ai_words"] = int(b["ai_words"]) + int(r["assistant_word_count"] or 0)
        b["duration"] = float(b["duration"]) + float(r["total_duration_seconds"] or 0)
        score = r["avg_sentiment_score"]
        if score is not None:
            s_sum, s_n = sentiment.get(key, (0.0, 0))
            sentiment[key] = (s_sum + float(score), s_n + 1)
    out: list[WeeklyTrendOut] = []
    for key, b in buckets.items():
        s_sum, s_n = sentiment.get(key, (0.0, 0))
        out.append(
            WeeklyTrendOut(
                week=key,
                sessions=int(b["sessions"]),
                total_turns=int(b["total_turns"]),
                user_words=int(b["user_words"]),
                ai_words=int(b["ai_words"]),
                avg_sentiment_score=(s_sum / s_n) if s_n else None,
                total_duration_seconds=float(b["duration"]),
            )
        )
    out.sort(key=lambda w: w.week, reverse=True)
    return out


@router.post("/save_feedback", response_model=SaveFeedbackResponse)
async def save_feedback(
    body: SaveFeedbackRequest, user: CurrentUserDep, pool: PoolDep
) -> SaveFeedbackResponse:
    # No HTML sanitization of `comment`: v5 never renders it as HTML, and the
    # schema bounds its length. The row's user_id is always the caller's id.
    if body.idempotency_key:
        async with transaction(pool) as conn:
            existing = await feedback_repo.find_by_idempotency_key(conn, key=body.idempotency_key)
        if existing is not None:
            return SaveFeedbackResponse(status="ok", idempotent=True)
    rating = body.value if body.feedback_type == "star" else None
    async with UnitOfWork(pool) as uow:
        try:
            await feedback_repo.insert(
                uow.conn,
                user_id=UUID(user.id),
                feedback_type=body.feedback_type,
                session_id=body.session_id,
                log_id=body.session_log_id,
                consultant_log_id=body.consultant_log_id,
                value=body.value,
                rating=rating,
                comment=body.comment,
                idempotency_key=body.idempotency_key,
            )
        except asyncpg.UniqueViolationError:
            return SaveFeedbackResponse(status="ok", idempotent=True)
    return SaveFeedbackResponse(status="ok")


@router.get("/session_analytics/{session_id}", response_model=SessionAnalyticsOut)
async def get_session_analytics(
    session_id: UUID, user: CurrentUserDep, pool: PoolDep
) -> SessionAnalyticsOut:
    async with transaction(pool) as conn:
        row = await analytics_repo.get_session_analytics(conn, session_id=session_id)
    if row is None:
        raise NotFound("session analytics not found")
    require_ownership(user, str(row.user_id))
    return SessionAnalyticsOut(
        session_id=row.session_id,
        total_turns=row.total_turns,
        user_turns=row.user_turns,
        others_turns=row.others_turns,
        llm_turns=row.llm_turns,
        user_word_count=row.user_word_count,
        assistant_word_count=row.assistant_word_count,
        average_latency_ms=row.average_latency_ms,
        avg_advice_latency_ms=row.avg_advice_latency_ms,
        total_duration_seconds=row.total_duration_seconds,
        memories_saved=row.memories_saved,
        events_extracted=row.events_extracted,
        highlights_created=row.highlights_created,
        avg_sentiment_score=row.avg_sentiment_score,
        dominant_sentiment=row.dominant_sentiment,
        topic_summary=row.topic_summary,
        sentiment_trend=[],
        computed_at=row.computed_at,
    )


@router.get("/coaching_report/{session_id}", response_model=CoachingReportOut)
async def get_coaching_report(
    session_id: UUID, user: CurrentUserDep, pool: PoolDep
) -> CoachingReportOut:
    async with transaction(pool) as conn:
        row = await analytics_repo.get_coaching_report(conn, session_id=session_id)
    if row is None:
        raise NotFound("coaching report not found")
    require_ownership(user, str(row.user_id))
    tone_scores = {k: int(v) for k, v in row.report_content.items() if isinstance(v, (int, float))}
    return CoachingReportOut(
        session_id=row.session_id,
        model_used=row.model_used,
        user_talk_pct=row.user_talk_pct,
        others_talk_pct=row.others_talk_pct,
        key_topics=row.key_topics,
        key_decisions=row.key_decisions,
        action_items=row.action_items,
        follow_up_people=row.follow_up_people,
        filler_words=row.filler_words,
        filler_word_count=row.filler_word_count,
        tone_summary=row.tone_summary,
        engagement_trend=row.engagement_trend,
        suggestions=row.suggestions,
        strengths=row.strengths,
        areas_of_improvement=row.areas_of_improvement,
        report_text=row.report_text,
        tone_scores=tone_scores,
        generated_at=row.generated_at,
    )


@router.get("/digest/{user_id}", response_model=DigestResponse)
async def get_digest(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
    period: Literal["day", "week"] = "week",
) -> DigestResponse:
    require_ownership(user, str(user_id))
    days = 1 if period == "day" else 7
    since = datetime.now(UTC) - timedelta(days=days)
    async with transaction(pool) as conn:
        sessions = await analytics_repo.digest_sessions(conn, user_id=user_id, since=since)
        count = (
            await conn.fetchval(
                "SELECT count(*) FROM sessions "
                "WHERE user_id = $1 AND created_at >= $2 AND deleted_at IS NULL",
                user_id,
                since,
            )
            or 0
        )
        tasks = await analytics_repo.digest_pending_tasks(conn, user_id=user_id)
        entities = await analytics_repo.digest_top_entities(conn, user_id=user_id)
        highlights = await analytics_repo.digest_recent_highlights(conn, user_id=user_id, since=since)
    return DigestResponse(
        period=period,
        user_id=user_id,
        sessions_count=int(count),
        recent_sessions=[DigestSession(**dict(r)) for r in sessions],
        pending_tasks=[DigestTask(**dict(r)) for r in tasks],
        top_entities=[DigestEntity(**dict(r)) for r in entities],
        recent_highlights=[DigestHighlight(**dict(r)) for r in highlights],
    )


@router.get("/communication_trends/{user_id}", response_model=CommunicationTrendsResponse)
async def get_communication_trends(
    user_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
    weeks: int = Query(8, ge=1, le=52),
) -> CommunicationTrendsResponse:
    require_ownership(user, str(user_id))
    since = datetime.now(UTC) - timedelta(weeks=weeks)
    async with transaction(pool) as conn:
        rows = await analytics_repo.trends_since(conn, user_id=user_id, since=since)
    trends = _group_by_week(rows)
    return CommunicationTrendsResponse(
        user_id=user_id, weeks_requested=weeks, weeks_available=len(trends), trends=trends
    )
```

- [ ] **Step 4: Register the router**

In `server/src/bubbles/api/router.py`, add the import (after the `entities` import line) and the `include_router` call (after `entities_router`):

```python
from bubbles.api.v1.analytics import router as analytics_router
```
```python
v1_router.include_router(analytics_router)
```

So the file becomes:

```python
"""Mount all /v1 sub-routers under a single prefix."""

from __future__ import annotations

from fastapi import APIRouter

from bubbles.api.v1.analytics import router as analytics_router
from bubbles.api.v1.consultant import router as consultant_router
from bubbles.api.v1.entities import router as entities_router
from bubbles.api.v1.gamification import router as gamification_router
from bubbles.api.v1.grammar import router as grammar_router
from bubbles.api.v1.memories import router as memories_router
from bubbles.api.v1.persona import router as persona_router
from bubbles.api.v1.sessions import router as sessions_router
from bubbles.api.v1.stt import router as stt_router
from bubbles.api.v1.voice import router as voice_router

v1_router = APIRouter(prefix="/v1")
v1_router.include_router(sessions_router)
v1_router.include_router(consultant_router)
v1_router.include_router(entities_router)
v1_router.include_router(analytics_router)
v1_router.include_router(gamification_router)
v1_router.include_router(memories_router)
v1_router.include_router(persona_router)
v1_router.include_router(grammar_router)
v1_router.include_router(voice_router)
v1_router.include_router(stt_router)
```

- [ ] **Step 5: Run the unit test + lint + types**

Run (from `server/`): `uv run pytest tests/test_analytics_week_grouping.py -q && uv run ruff check . && uv run ruff format --check . && uv run mypy`
Expected: unit tests PASS; ruff/mypy clean. (If `ruff format --check` flags the new files, run `uv run ruff format` and re-check.)

- [ ] **Step 6: Write the integration route tests**

Create `server/tests/integration/test_routes_analytics.py`:

```python
"""Integration tests for the analytics HTTP routes."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import asyncpg
import httpx
import pytest
from httpx import ASGITransport

from bubbles.app import create_app
from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.deps import get_pool

pytestmark = pytest.mark.integration


def _client(pool: asyncpg.Pool, uid: UUID) -> httpx.AsyncClient:
    app = create_app()
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )
    return httpx.AsyncClient(transport=ASGITransport(app=app), base_url="http://t")


async def _new_user(pool: asyncpg.Pool) -> UUID:
    uid = uuid4()
    async with pool.acquire() as conn:
        await conn.execute("INSERT INTO auth.users (id) VALUES ($1)", uid)
    return uid


async def _new_session(pool: asyncpg.Pool, user_id: UUID, **cols: object) -> UUID:
    sid = uuid4()
    keys = ", ".join(["id", "user_id", *cols.keys()])
    placeholders = ", ".join(f"${i + 1}" for i in range(2 + len(cols)))
    async with pool.acquire() as conn:
        await conn.execute(
            f"INSERT INTO sessions ({keys}) VALUES ({placeholders})", sid, user_id, *cols.values()
        )
    return sid


# --- save_feedback ---------------------------------------------------------


async def test_save_feedback_happy_path(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with _client(pool, user_id) as c:
        r = await c.post("/v1/save_feedback", json={"feedback_type": "thumbs", "value": 1})
        assert r.status_code == 200
        assert r.json() == {"status": "ok", "idempotent": False}
    async with pool.acquire() as conn:
        n = await conn.fetchval("SELECT count(*) FROM feedback WHERE user_id = $1", user_id)
        assert n == 1


async def test_save_feedback_idempotent_replay(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with _client(pool, user_id) as c:
        body = {"feedback_type": "star", "value": 5, "idempotency_key": "k1"}
        r1 = await c.post("/v1/save_feedback", json=body)
        assert r1.json()["idempotent"] is False
        r2 = await c.post("/v1/save_feedback", json=body)
        assert r2.status_code == 200
        assert r2.json()["idempotent"] is True
    async with pool.acquire() as conn:
        n = await conn.fetchval("SELECT count(*) FROM feedback WHERE idempotency_key = 'k1'")
        assert n == 1


async def test_save_feedback_bad_value_is_422(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with _client(pool, user_id) as c:
        r = await c.post("/v1/save_feedback", json={"feedback_type": "star", "value": 99})
        assert r.status_code == 422


async def test_save_feedback_bad_type_is_422(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with _client(pool, user_id) as c:
        r = await c.post("/v1/save_feedback", json={"feedback_type": "nope"})
        assert r.status_code == 422


# --- session_analytics -----------------------------------------------------


async def test_session_analytics_404_when_absent(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with _client(pool, user_id) as c:
        r = await c.get(f"/v1/session_analytics/{uuid4()}")
        assert r.status_code == 404


async def test_session_analytics_happy_and_cross_user_403(pool: asyncpg.Pool, user_id: UUID) -> None:
    sid = await _new_session(pool, user_id, status="ended")
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO session_analytics (session_id, user_id, total_turns, user_word_count) "
            "VALUES ($1, $2, 5, 12)",
            sid,
            user_id,
        )
    async with _client(pool, user_id) as c:
        r = await c.get(f"/v1/session_analytics/{sid}")
        assert r.status_code == 200
        body = r.json()
        assert body["total_turns"] == 5
        assert body["user_word_count"] == 12
        assert body["sentiment_trend"] == []
        assert body["avg_sentiment_score"] is None
    other = await _new_user(pool)
    async with _client(pool, other) as c:
        r = await c.get(f"/v1/session_analytics/{sid}")
        assert r.status_code == 403


# --- coaching_report -------------------------------------------------------


async def test_coaching_report_404_then_happy(pool: asyncpg.Pool, user_id: UUID) -> None:
    sid = await _new_session(pool, user_id, status="ended")
    async with _client(pool, user_id) as c:
        assert (await c.get(f"/v1/coaching_report/{sid}")).status_code == 404
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO coaching_reports "
            "(session_id, user_id, model_used, user_talk_pct, key_topics, filler_word_count, "
            " report_content) "
            "VALUES ($1, $2, 'analytics.coaching', 55.0, ARRAY['budget'], 4, '{\"tone_clarity\": 8}'::jsonb)",
            sid,
            user_id,
        )
    async with _client(pool, user_id) as c:
        r = await c.get(f"/v1/coaching_report/{sid}")
        assert r.status_code == 200
        body = r.json()
        assert body["user_talk_pct"] == 55.0
        assert body["key_topics"] == ["budget"]
        assert body["tone_scores"] == {"tone_clarity": 8}
    other = await _new_user(pool)
    async with _client(pool, other) as c:
        assert (await c.get(f"/v1/coaching_report/{sid}")).status_code == 403


# --- digest ----------------------------------------------------------------


async def test_digest_period_window_and_cross_user_403(pool: asyncpg.Pool, user_id: UUID) -> None:
    now = datetime.now(UTC)
    await _new_session(pool, user_id, title="recent", status="ended", created_at=now - timedelta(hours=1))
    await _new_session(pool, user_id, title="old", created_at=now - timedelta(days=20))
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO tasks (user_id, title, status) VALUES ($1, 'todo', 'pending')", user_id
        )
        await conn.execute(
            "INSERT INTO entities (user_id, display_name, entity_type, mention_count) "
            "VALUES ($1, 'Alice', 'person', 9)",
            user_id,
        )
    async with _client(pool, user_id) as c:
        r = await c.get(f"/v1/digest/{user_id}", params={"period": "week"})
        assert r.status_code == 200
        body = r.json()
        assert body["period"] == "week"
        assert [s["title"] for s in body["recent_sessions"]] == ["recent"]
        assert body["sessions_count"] == 1
        assert [t["title"] for t in body["pending_tasks"]] == ["todo"]
        assert [e["display_name"] for e in body["top_entities"]] == ["Alice"]
        r_day = await c.get(f"/v1/digest/{user_id}", params={"period": "day"})
        assert r_day.status_code == 200
    other = await _new_user(pool)
    async with _client(pool, other) as c:
        assert (await c.get(f"/v1/digest/{user_id}")).status_code == 403


# --- communication_trends --------------------------------------------------


async def test_communication_trends_grouping_and_validation(pool: asyncpg.Pool, user_id: UUID) -> None:
    now = datetime.now(UTC)
    s1 = await _new_session(pool, user_id, status="ended")
    s2 = await _new_session(pool, user_id, status="ended")
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO session_analytics (session_id, user_id, total_turns, user_word_count, "
            "assistant_word_count, computed_at) VALUES ($1, $2, 3, 5, 4, $3), ($4, $2, 7, 10, 6, $5)",
            s1,
            user_id,
            now - timedelta(days=1),
            s2,
            now - timedelta(days=2),
        )
    async with _client(pool, user_id) as c:
        r = await c.get(f"/v1/communication_trends/{user_id}", params={"weeks": 8})
        assert r.status_code == 200
        body = r.json()
        assert body["weeks_requested"] == 8
        # both rows are within the last ~3 days -> same or adjacent ISO weeks
        total_turns = sum(t["total_turns"] for t in body["trends"])
        assert total_turns == 10
        assert (await c.get(f"/v1/communication_trends/{user_id}", params={"weeks": 0})).status_code == 422
        assert (await c.get(f"/v1/communication_trends/{user_id}", params={"weeks": 53})).status_code == 422
    other = await _new_user(pool)
    async with _client(pool, other) as c:
        assert (await c.get(f"/v1/communication_trends/{user_id}")).status_code == 403
```

> The exact app-factory import (`from bubbles.app import create_app`) and dependency names (`get_pool`, `current_user`) must match what the existing `tests/integration/test_routes_gamification.py` uses — copy that file's imports and `_client`/override helpers verbatim and only swap the request paths. If `create_app` lives elsewhere (e.g. `bubbles.main:app`), follow the existing test exactly.

- [ ] **Step 7: Run the gate**

Run (from `server/`):
```
$env:RUN_INTEGRATION=1; uv run pytest tests/integration/test_routes_analytics.py -q   # if Docker available
uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest -q
```
Expected: ruff/mypy clean; pytest passes (integration suites skipped locally).

- [ ] **Step 8: Commit**

```bash
git add server/src/bubbles/api/v1/analytics.py server/src/bubbles/api/router.py server/tests/test_analytics_week_grouping.py server/tests/integration/test_routes_analytics.py
git commit -m "feat(api): add analytics routes (save_feedback, session_analytics, coaching_report, digest, communication_trends)"
```

---

## Task 9: Docs — review-doc §5 + README

**Files:**
- Modify: `Documentation/server-vs-server_v2-review.md`
- Modify: `README.md`

- [ ] **Step 1: Update the review doc §5**

In `Documentation/server-vs-server_v2-review.md`, after the "Batch 2 (gamification HTTP) — done." callout in §5, add:

```markdown
> **Batch 3 (analytics reads + feedback) — done.** `POST /v1/save_feedback` (idempotent on `idempotency_key`), `GET /v1/session_analytics/{session_id}`, `GET /v1/coaching_report/{session_id}`, `GET /v1/digest/{user_id}?period=day|week`, `GET /v1/communication_trends/{user_id}?weeks=N` are implemented in v5. The `compute_session_analytics` worker now also writes a `session_analytics` metrics row (turn/word counts parsed from the transcript; duration; memory/event/highlight counts) and an LLM-generated `coaching_reports` row (`analytics.coaching` task chain). No migration — `session_analytics` / `coaching_reports` / `feedback` already exist in the live Supabase schema. See `docs/superpowers/specs/2026-05-12-v5-port-batch3-analytics-design.md`.
```

Then update the follow-ups bullets to remove `coaching_report`, `session_analytics`, `digest`, `communication_trends`, `save_feedback` from the "Analytics/performance read endpoints" line, leaving:

```markdown
- **Analytics follow-ups**: `GET /v1/session_replay/{session_id}` is not ported — it needs a per-turn store (`session_logs`), which v5 does not keep yet; bundle it with that work. The per-turn-derived `session_analytics` columns (`average_latency_ms`, `avg_advice_latency_ms`, `avg_sentiment_score`, `dominant_sentiment`) stay NULL and the `sentiment_trend` array stays empty until v5 captures per-turn latency/sentiment (a `sentiment_logs` writer). Nothing yet calls `enqueue_session_analytics` (end_session → enqueue) — wiring that trigger is a separate change.
- **`performance_summary/{user_id}` endpoint**: not yet ported (later batch).
```

(Keep the existing `coaching_report`, `session_replay`, etc. mentions only where they still apply per the above; remove the now-done ones. If the existing §5 has a single bullet listing all five "Analytics/performance read endpoints", replace it with the two bullets above.)

- [ ] **Step 2: Update README "Backend API Summary"**

In `README.md`, under "## Backend API Summary" → "Versioned business endpoints:", add an "Analytics" group (place it after the existing "Analytics" group if one exists — there is currently an "Analytics" group with `save_feedback` / `session_analytics` / `coaching_report` listed under it; ensure it lists all five and matches the implemented paths):

```markdown
- Analytics
  - `POST /v1/save_feedback`
  - `GET /v1/session_analytics/{session_id}`
  - `GET /v1/coaching_report/{session_id}`
  - `GET /v1/digest/{user_id}`
  - `GET /v1/communication_trends/{user_id}`
```

If a stale "Analytics" group already exists with only three of these, replace it wholesale with the block above (and remove `process_transcript_wingman` / `enroll` from groups where they don't yet exist in v5 — but **only** if doing so doesn't conflict with other pending batches; when in doubt, just make the Analytics group correct and leave the rest).

- [ ] **Step 3: Commit**

```bash
git add Documentation/server-vs-server_v2-review.md README.md
git commit -m "docs: record Batch 3 (analytics reads + feedback) in review doc and README"
```

(`Documentation/` is gitignored except force-tracked files; `server-vs-server_v2-review.md` is already force-tracked, so a plain `git add` works. If `git status` shows it as untracked/ignored, use `git add -f Documentation/server-vs-server_v2-review.md`.)

---

## Final Verification (after all tasks)

- [ ] Run the full gate from `server/`:
```
uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest -q
```
Expected: ruff clean, mypy clean (reports source-file count), pytest all green (integration suites skipped locally — they run in CI with `RUN_INTEGRATION=1` + Docker).
- [ ] (If Docker available) `$env:RUN_INTEGRATION=1; uv run pytest tests/integration -q` — all new integration suites pass.
- [ ] `git log --oneline` shows 9 commits for Batch 3.
- [ ] Dispatch a final code review over the whole Batch 3 diff, then proceed to `superpowers:finishing-a-development-branch`.

---

## Notes / deviations from the spec

- **`upsert_coaching_report`** uses DELETE-then-INSERT (spec §3.3 said UPDATE-then-INSERT). Equivalent — both run inside the worker's `UnitOfWork` transaction, the worker is idempotent per session, and DELETE+INSERT is simpler to write correctly.
- **`analytics.coaching` `max_tokens`** set to 900 (spec §4.3 said 800) — small headroom for the larger JSON payload; not material.
- **`_truncate` window** (`_MAX_TRANSCRIPT_CHARS = 4000`, last 4000 chars) is reused as-is for the coaching prompt — matches every other extraction task; v2 used "first 6000 chars" but matching v5's existing convention is preferable to introducing a special case.
