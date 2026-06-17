# Purpose: Repository for XP ledger, quest assignments, streak records, and leaderboard aggregation.
"""Gamification repo: user_gamification + quests + rewards."""

from __future__ import annotations

import json
from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from uuid import UUID

import asyncpg

from bubbles.db.models import (
    QuestDefinition,
    Reward,
    UserGamification,
    UserQuest,
    UserReward,
)
from bubbles.db.repo import xp as xp_repo

# Automated XP sources (sessions, extraction, …) can earn at most this much per
# UTC day combined. Quests, achievements and streak milestones are exempt.
DAILY_AUTOMATED_XP_CAP = 500
_CAP_EXEMPT_SOURCES = frozenset({"quest", "achievement", "streak_milestone"})

# Streak length → one-off bonus XP (exempt from the daily cap; idempotent per
# user per milestone via the ledger source_id).
_STREAK_MILESTONE_BONUS: dict[int, int] = {7: 50, 14: 100, 30: 250, 60: 500, 100: 1000, 365: 5000}


def _utc_day_start(today: date) -> datetime:
    return datetime.combine(today, time.min, tzinfo=UTC)


_GAMIF_COLS = """
    user_id, total_xp, level, current_streak, longest_streak, streak_freezes,
    last_active_date, xp_spent, leaderboard_opt_in, updated_at
"""

_QUEST_DEF_COLS = """
    id, title, description, quest_type, action_type, target, xp_reward,
    is_active, focus_area, difficulty, mission_type, brief
"""

_USER_QUEST_COLS = """
    id, user_id, quest_id, progress, target, is_completed, xp_awarded,
    assigned_date, completed_at, created_at
"""

_REWARD_COLS = """
    id, title, description, icon, category, cost_xp, sort_order, is_active
"""

_USER_REWARD_COLS = "id, user_id, reward_id, cost_xp, unlocked_at"


def _gamif(row: asyncpg.Record) -> UserGamification:
    return UserGamification(
        user_id=row["user_id"],
        total_xp=row["total_xp"] or 0,
        level=row["level"] or 1,
        current_streak=row["current_streak"] or 0,
        longest_streak=row["longest_streak"] or 0,
        streak_freezes=row["streak_freezes"] or 0,
        last_active_date=row["last_active_date"],
        xp_spent=row["xp_spent"] or 0,
        leaderboard_opt_in=row["leaderboard_opt_in"] or False,
        updated_at=row["updated_at"],
    )


def _quest_def(row: asyncpg.Record) -> QuestDefinition:
    brief = row["brief"]
    if isinstance(brief, str):
        import json

        brief = json.loads(brief)
    return QuestDefinition(
        id=row["id"],
        title=row["title"],
        description=row["description"],
        quest_type=row["quest_type"] or "daily",
        action_type=row["action_type"],
        target=row["target"],
        xp_reward=row["xp_reward"] or 0,
        is_active=row["is_active"] or False,
        focus_area=row["focus_area"],
        difficulty=row["difficulty"] or "medium",
        mission_type=row["mission_type"] or "action",
        brief=brief,
    )


def _user_quest(row: asyncpg.Record) -> UserQuest:
    return UserQuest(
        id=row["id"],
        user_id=row["user_id"],
        quest_id=row["quest_id"],
        progress=row["progress"] or 0,
        target=row["target"],
        is_completed=row["is_completed"] or False,
        xp_awarded=row["xp_awarded"] or False,
        assigned_date=row["assigned_date"],
        completed_at=row["completed_at"],
        created_at=row["created_at"],
    )


def _reward(row: asyncpg.Record) -> Reward:
    return Reward(
        id=row["id"],
        title=row["title"],
        description=row["description"],
        icon=row["icon"] or "🎁",
        category=row["category"] or "general",
        cost_xp=row["cost_xp"],
        sort_order=row["sort_order"] or 0,
        is_active=row["is_active"] or False,
    )


def _user_reward(row: asyncpg.Record) -> UserReward:
    return UserReward(
        id=row["id"],
        user_id=row["user_id"],
        reward_id=row["reward_id"],
        cost_xp=row["cost_xp"],
        unlocked_at=row["unlocked_at"],
    )


# --- gamification state -----------------------------------------------------


async def get_or_init_gamification(conn: asyncpg.Connection, user_id: UUID) -> UserGamification:
    row = await conn.fetchrow(
        f"""
        INSERT INTO user_gamification (user_id)
        VALUES ($1)
        ON CONFLICT (user_id) DO UPDATE SET updated_at = user_gamification.updated_at
        RETURNING {_GAMIF_COLS}
        """,
        user_id,
    )
    assert row is not None
    return _gamif(row)


async def add_xp(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    amount: int,
    source_type: str = "manual",
    source_id: str | None = None,
    description: str | None = None,
    capped: bool = True,
) -> UserGamification:
    """Award XP. Writes an ``xp_transactions`` ledger row first; if that row was
    deduped (same ``source_id`` already awarded) the ``user_gamification`` total
    is left unchanged — making repeated awards with the same ``source_id`` a no-op.

    When ``capped`` (the default for automated sources), the awarded amount is
    clamped so the user's combined automated XP for the current UTC day does not
    exceed ``DAILY_AUTOMATED_XP_CAP``. Exempt sources (quests, achievements,
    streak milestones) pass ``capped=False`` and are never limited.
    """
    if amount < 0:
        raise ValueError("amount must be non-negative")
    if capped and amount > 0:
        earned_today = await xp_repo.sum_since(
            conn,
            user_id=user_id,
            since=_utc_day_start(datetime.now(tz=UTC).date()),
            exclude_source_types=_CAP_EXEMPT_SOURCES,
        )
        amount = max(0, min(amount, DAILY_AUTOMATED_XP_CAP - earned_today))
    if amount == 0:
        return await get_or_init_gamification(conn, user_id)
    ledger_row = await xp_repo.record(
        conn,
        user_id=user_id,
        amount=amount,
        source_type=source_type,
        source_id=source_id,
        description=description,
    )
    if ledger_row is None:
        # Already awarded for this source_id — do not double-count.
        return await get_or_init_gamification(conn, user_id)
    row = await conn.fetchrow(
        f"""
        INSERT INTO user_gamification (user_id, total_xp, last_active_date, updated_at)
        VALUES ($1, $2, CURRENT_DATE, NOW())
        ON CONFLICT (user_id) DO UPDATE SET
            total_xp = user_gamification.total_xp + EXCLUDED.total_xp,
            last_active_date = CURRENT_DATE,
            updated_at = NOW()
        RETURNING {_GAMIF_COLS}
        """,
        user_id,
        amount,
    )
    assert row is not None
    return _gamif(row)


async def update_streak(
    conn: asyncpg.Connection, *, user_id: UUID, today: date | None = None
) -> UserGamification:
    """Advance the user's daily streak; award a milestone bonus when one is hit.

    Call this once per day at the start of activity (e.g. ``start_session``),
    *before* any XP is awarded — ``add_xp`` stamps ``last_active_date`` to
    today, which this function reads to decide whether today already counted.
    Rules: consecutive day → +1; one-day gap with a freeze available → +1 and
    consume a freeze; otherwise → reset to 1.
    """
    g = await get_or_init_gamification(conn, user_id)
    day = today or datetime.now(tz=UTC).date()
    last = g.last_active_date
    if last == day:
        return g
    freezes = g.streak_freezes
    if last == day - timedelta(days=1):
        new_streak = g.current_streak + 1
    elif last is not None and last == day - timedelta(days=2) and freezes > 0:
        new_streak = g.current_streak + 1
        freezes -= 1
    else:
        new_streak = 1
    longest = max(g.longest_streak, new_streak)
    row = await conn.fetchrow(
        f"""
        UPDATE user_gamification
        SET current_streak = $2, longest_streak = $3, streak_freezes = $4,
            last_active_date = $5, updated_at = NOW()
        WHERE user_id = $1
        RETURNING {_GAMIF_COLS}
        """,
        user_id,
        new_streak,
        longest,
        freezes,
        day,
    )
    assert row is not None
    updated = _gamif(row)
    bonus = _STREAK_MILESTONE_BONUS.get(new_streak)
    if bonus:
        updated = await add_xp(
            conn,
            user_id=user_id,
            amount=bonus,
            source_type="streak_milestone",
            source_id=f"streak_{user_id}_{new_streak}",
            description=f"{new_streak}-day streak",
            capped=False,
        )
        # Re-fetch streak fields since add_xp returns its own gamification row
        # (which has the streak we just wrote — add_xp doesn't touch streaks).
    return updated


async def set_leaderboard_opt_in(
    conn: asyncpg.Connection, *, user_id: UUID, opt_in: bool
) -> UserGamification:
    row = await conn.fetchrow(
        f"""
        UPDATE user_gamification SET leaderboard_opt_in = $2, updated_at = NOW()
        WHERE user_id = $1
        RETURNING {_GAMIF_COLS}
        """,
        user_id,
        opt_in,
    )
    if row is None:
        # First touch — create row first.
        await get_or_init_gamification(conn, user_id)
        return await set_leaderboard_opt_in(conn, user_id=user_id, opt_in=opt_in)
    return _gamif(row)


async def leaderboard_top(conn: asyncpg.Connection, *, limit: int = 50) -> list[asyncpg.Record]:
    rows = await conn.fetch(
        """
        SELECT user_id, total_xp, level, current_streak
        FROM user_gamification
        WHERE leaderboard_opt_in = true
        ORDER BY total_xp DESC
        LIMIT $1
        """,
        limit,
    )
    return list(rows)


# --- quests -----------------------------------------------------------------


async def list_active_quest_defs(conn: asyncpg.Connection) -> list[QuestDefinition]:
    rows = await conn.fetch(
        f"SELECT {_QUEST_DEF_COLS} FROM quest_definitions WHERE is_active = true"
    )
    return [_quest_def(r) for r in rows]


async def list_user_quests(
    conn: asyncpg.Connection, *, user_id: UUID, on_date: date | None = None
) -> list[UserQuest]:
    rows = await conn.fetch(
        f"""
        SELECT {_USER_QUEST_COLS}
        FROM user_quests
        WHERE user_id = $1
          AND ($2::date IS NULL OR assigned_date = $2)
        ORDER BY created_at DESC
        """,
        user_id,
        on_date,
    )
    return [_user_quest(r) for r in rows]


async def assign_quest(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    quest_id: UUID,
    target: int,
    assigned_date: date,
) -> UserQuest:
    row = await conn.fetchrow(
        f"""
        INSERT INTO user_quests (user_id, quest_id, target, assigned_date)
        VALUES ($1, $2, $3, $4)
        RETURNING {_USER_QUEST_COLS}
        """,
        user_id,
        quest_id,
        target,
        assigned_date,
    )
    assert row is not None
    return _user_quest(row)


async def increment_quest_progress(
    conn: asyncpg.Connection,
    *,
    user_quest_id: UUID,
    delta: int = 1,
) -> UserQuest | None:
    row = await conn.fetchrow(
        f"""
        UPDATE user_quests
        SET progress = LEAST(progress + $2, target),
            is_completed = (progress + $2) >= target,
            completed_at = CASE WHEN (progress + $2) >= target AND completed_at IS NULL
                                THEN NOW() ELSE completed_at END
        WHERE id = $1
        RETURNING {_USER_QUEST_COLS}
        """,
        user_quest_id,
        delta,
    )
    return _user_quest(row) if row is not None else None


# --- rewards ----------------------------------------------------------------


async def list_active_rewards(conn: asyncpg.Connection) -> list[Reward]:
    rows = await conn.fetch(
        f"""
        SELECT {_REWARD_COLS} FROM rewards
        WHERE is_active = true
        ORDER BY sort_order ASC, cost_xp ASC
        """
    )
    return [_reward(r) for r in rows]


async def redeem_reward(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    reward_id: UUID,
) -> UserReward:
    """Atomic redeem: deduct XP and record. Errors if insufficient XP."""
    cost_row = await conn.fetchrow(
        "SELECT cost_xp, is_active FROM rewards WHERE id = $1",
        reward_id,
    )
    if cost_row is None or not cost_row["is_active"]:
        raise ValueError("reward not available")
    cost: int = cost_row["cost_xp"]

    deducted = await conn.fetchrow(
        """
        UPDATE user_gamification
        SET xp_spent = xp_spent + $2, updated_at = NOW()
        WHERE user_id = $1 AND total_xp - xp_spent >= $2
        RETURNING user_id
        """,
        user_id,
        cost,
    )
    if deducted is None:
        raise ValueError("insufficient XP")

    row = await conn.fetchrow(
        f"""
        INSERT INTO user_rewards (user_id, reward_id, cost_xp)
        VALUES ($1, $2, $3)
        RETURNING {_USER_REWARD_COLS}
        """,
        user_id,
        reward_id,
        cost,
    )
    assert row is not None
    return _user_reward(row)


async def owned_reward_ids(conn: asyncpg.Connection, *, user_id: UUID) -> set[UUID]:
    rows = await conn.fetch("SELECT reward_id FROM user_rewards WHERE user_id = $1", user_id)
    return {r["reward_id"] for r in rows}


async def get_or_assign_daily_quests(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    on_date: date,
    n: int = 3,
) -> list[UserQuest]:
    """Return the user's quests assigned for ``on_date``; if none are assigned
    yet, pick up to ``n`` random active definitions, assign each, and return
    them. Runs inside the caller's transaction (no commit here). Returns ``[]``
    if there are no active quest definitions.
    """
    existing = await list_user_quests(conn, user_id=user_id, on_date=on_date)
    if existing:
        return existing
    defs = await conn.fetch(
        f"SELECT {_QUEST_DEF_COLS} FROM quest_definitions WHERE is_active = true "
        "ORDER BY random() LIMIT $1",
        n,
    )
    assigned: list[UserQuest] = []
    for d in defs:
        qd = _quest_def(d)
        assigned.append(
            await assign_quest(
                conn,
                user_id=user_id,
                quest_id=qd.id,
                target=qd.target,
                assigned_date=on_date,
            )
        )
    return assigned


async def leaderboard_period(
    conn: asyncpg.Connection, *, since: datetime, limit: int = 25
) -> list[asyncpg.Record]:
    """Top opted-in users by XP earned since ``since`` (positive ledger rows)."""
    rows = await conn.fetch(
        """
        SELECT t.user_id, COALESCE(SUM(t.amount), 0)::int AS xp, g.level, g.current_streak
        FROM xp_transactions t
        JOIN user_gamification g ON g.user_id = t.user_id AND g.leaderboard_opt_in = true
        WHERE t.amount > 0 AND t.created_at >= $1
        GROUP BY t.user_id, g.level, g.current_streak
        ORDER BY xp DESC
        LIMIT $2
        """,
        since,
        limit,
    )
    return list(rows)


async def rank_all_time(conn: asyncpg.Connection, *, user_id: UUID) -> int | None:
    """1-based rank of ``user_id`` among opted-in users by ``total_xp``; ``None``
    if the user is not opted in."""
    val: int | None = await conn.fetchval(
        """
        SELECT rnk FROM (
            SELECT user_id, RANK() OVER (ORDER BY total_xp DESC) AS rnk
            FROM user_gamification WHERE leaderboard_opt_in = true
        ) s WHERE s.user_id = $1
        """,
        user_id,
    )
    return val


async def rank_period(conn: asyncpg.Connection, *, user_id: UUID, since: datetime) -> int | None:
    """1-based rank of ``user_id`` among opted-in users by XP since ``since``;
    ``None`` if the user has no positive ledger rows in the window or isn't opted in."""
    val: int | None = await conn.fetchval(
        """
        SELECT rnk FROM (
            SELECT t.user_id, RANK() OVER (ORDER BY COALESCE(SUM(t.amount), 0) DESC) AS rnk
            FROM xp_transactions t
            JOIN user_gamification g ON g.user_id = t.user_id AND g.leaderboard_opt_in = true
            WHERE t.amount > 0 AND t.created_at >= $2
            GROUP BY t.user_id
        ) s WHERE s.user_id = $1
        """,
        user_id,
        since,
    )
    return val


async def quest_completion_between(
    conn: asyncpg.Connection, *, user_id: UUID, since_date: date
) -> tuple[int, int]:
    """(assigned, completed) daily quests with ``assigned_date >= since_date``."""
    row = await conn.fetchrow(
        """
        SELECT count(*)::int AS assigned,
               count(*) FILTER (WHERE is_completed)::int AS completed
        FROM user_quests
        WHERE user_id = $1 AND assigned_date >= $2
        """,
        user_id,
        since_date,
    )
    assert row is not None
    return int(row["assigned"]), int(row["completed"])


# --- activity stats ---------------------------------------------------------


async def user_activity_stats(conn: asyncpg.Connection, *, user_id: UUID) -> dict[str, int]:
    """Aggregate non-deleted activity counts for the profile ``stats{}`` block."""
    row = await conn.fetchrow(
        """
        SELECT
          (SELECT count(*)::int FROM sessions WHERE user_id = $1 AND deleted_at IS NULL)
            AS sessions_total,
          (SELECT count(*)::int FROM sessions
             WHERE user_id = $1 AND deleted_at IS NULL AND ended_at IS NOT NULL)
            AS sessions_completed,
          (SELECT count(*)::int FROM memory WHERE user_id = $1 AND is_archived = false)
            AS memories_total,
          (SELECT count(*)::int FROM entities WHERE user_id = $1 AND is_archived = false)
            AS entities_total,
          (SELECT count(*)::int FROM user_mistakes WHERE user_id = $1) AS mistakes_total,
          (SELECT count(*)::int FROM user_quests WHERE user_id = $1 AND is_completed = true)
            AS quests_completed,
          (SELECT count(*)::int FROM user_achievements WHERE user_id = $1) AS achievements_earned
        """,
        user_id,
    )
    assert row is not None
    return {k: int(v or 0) for k, v in dict(row).items()}


# --- quest missions ---------------------------------------------------------


async def get_user_quest(conn: asyncpg.Connection, user_quest_id: UUID) -> UserQuest | None:
    row = await conn.fetchrow(
        f"SELECT {_USER_QUEST_COLS} FROM user_quests WHERE id = $1", user_quest_id
    )
    return _user_quest(row) if row is not None else None


async def get_quest_def(conn: asyncpg.Connection, quest_id: UUID) -> QuestDefinition | None:
    row = await conn.fetchrow(
        f"SELECT {_QUEST_DEF_COLS} FROM quest_definitions WHERE id = $1", quest_id
    )
    return _quest_def(row) if row is not None else None


async def _brief_state(conn: asyncpg.Connection, user_quest_id: UUID) -> dict[str, Any]:
    raw = await conn.fetchval("SELECT brief_state FROM user_quests WHERE id = $1", user_quest_id)
    if raw is None:
        return {}
    if isinstance(raw, str):
        return dict(json.loads(raw))
    return dict(raw)


async def award_quest_xp_once(
    conn: asyncpg.Connection, *, user_quest_id: UUID, user_id: UUID, xp_reward: int, title: str
) -> None:
    """Award a quest's XP exactly once, flipping ``xp_awarded``."""
    flagged = await conn.fetchval(
        "UPDATE user_quests SET xp_awarded = true WHERE id = $1 AND xp_awarded = false RETURNING id",
        user_quest_id,
    )
    if flagged is None or xp_reward <= 0:
        return
    await add_xp(
        conn,
        user_id=user_id,
        amount=xp_reward,
        source_type="quest",
        source_id=f"quest_{user_quest_id}",
        description=f"Quest: {title}",
        capped=False,
    )


async def record_question_answer(
    conn: asyncpg.Connection, *, quest: UserQuest, question_id: str, answer: str
) -> tuple[UserQuest, bool]:
    """Record one answer for a question_set mission. Progress = #distinct questions answered.

    Returns (updated_user_quest, newly_completed). Caller should pass a freshly
    fetched ``quest`` (we read its ``is_completed`` / ``target`` to decide).
    """
    state = await _brief_state(conn, quest.id)
    answers: dict[str, Any] = dict(state.get("answers") or {})
    answers[question_id] = answer
    state["answers"] = answers
    new_progress = min(len(answers), quest.target)
    newly_completed = (not quest.is_completed) and len(answers) >= quest.target
    is_completed = quest.is_completed or newly_completed
    row = await conn.fetchrow(
        f"""
        UPDATE user_quests
        SET brief_state = $2::jsonb, progress = $3, is_completed = $4,
            completed_at = CASE WHEN $5 THEN NOW() ELSE completed_at END
        WHERE id = $1
        RETURNING {_USER_QUEST_COLS}
        """,
        quest.id,
        json.dumps(state),
        new_progress,
        is_completed,
        newly_completed,
    )
    assert row is not None
    return _user_quest(row), newly_completed


async def complete_conversation_quest(
    conn: asyncpg.Connection,
    *,
    quest: UserQuest,
    session_id: UUID,
    user_turns: int,
    min_turns: int,
    eval_passed: bool | None = None,
    eval_reason: str | None = None,
) -> tuple[UserQuest, bool]:
    """Attach a session to a conversation mission. Completes iff ``user_turns >= min_turns``
    and, when a brief LLM evaluator runs, ``eval_passed`` is not ``False``.

    Returns (updated_user_quest, newly_completed). On failure the attempt is
    recorded in ``brief_state`` so the client can show why and try another session.
    """
    state = await _brief_state(conn, quest.id)
    turns_ok = user_turns >= min_turns
    passed = turns_ok and (eval_passed is not False)
    attempt: dict[str, Any] = {
        "session_id": str(session_id),
        "user_turns": user_turns,
        "min_turns": min_turns,
        "passed": passed,
    }
    if eval_passed is not None:
        attempt["eval_passed"] = eval_passed
        if eval_reason:
            attempt["eval_reason"] = eval_reason
    state["last_attach"] = attempt
    if passed:
        state["attached_session_id"] = str(session_id)
    newly_completed = (not quest.is_completed) and passed
    is_completed = quest.is_completed or newly_completed
    row = await conn.fetchrow(
        f"""
        UPDATE user_quests
        SET brief_state = $2::jsonb,
            progress = CASE WHEN $5 THEN target ELSE progress END,
            is_completed = $3,
            completed_at = CASE WHEN $4 THEN NOW() ELSE completed_at END
        WHERE id = $1
        RETURNING {_USER_QUEST_COLS}
        """,
        quest.id,
        json.dumps(state),
        is_completed,
        newly_completed,
        passed,
    )
    assert row is not None
    return _user_quest(row), newly_completed


async def bump_quest_progress_by_action(
    conn: asyncpg.Connection,
    *,
    user_id: UUID,
    action_type: str,
    delta: int = 1,
    on_date: date | None = None,
) -> UserQuest | None:
    """Advance the user's incomplete daily quest matching ``action_type``; award XP on completion.

    Returns the updated quest, or ``None`` if there is no matching incomplete quest today.
    """
    day = on_date or datetime.now(tz=UTC).date()
    target = await conn.fetchrow(
        """
        SELECT uq.id, qd.xp_reward, qd.title
        FROM user_quests uq JOIN quest_definitions qd ON qd.id = uq.quest_id
        WHERE uq.user_id = $1 AND uq.assigned_date = $2
          AND uq.is_completed = false AND qd.action_type = $3
        ORDER BY uq.created_at ASC LIMIT 1
        """,
        user_id,
        day,
        action_type,
    )
    if target is None:
        return None
    updated = await increment_quest_progress(conn, user_quest_id=target["id"], delta=delta)
    if updated is None:
        return None
    if updated.is_completed:
        await award_quest_xp_once(
            conn,
            user_quest_id=updated.id,
            user_id=user_id,
            xp_reward=int(target["xp_reward"] or 0),
            title=str(target["title"] or "Daily quest"),
        )
    return updated
