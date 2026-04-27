"""
GamificationService — XP awards, streak tracking, daily quest management, and
achievement detection.

Design contract:
  - NEVER raises — all exceptions are caught and printed.
  - NEVER blocks critical paths — all callers use fire_and_forget() or
    asyncio.create_task() so gamification failures never fail a session/consultant call.
  - Idempotent XP: if source_id is provided, duplicate awards are silently skipped.
  - Daily XP cap: automated sources (sessions, extraction) are capped at 500 XP/day.
"""

import asyncio
import math
import random
from datetime import date, datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from app.database import db


# ── XP constants ──────────────────────────────────────────────────────────────
XP_SESSION_COMPLETE = 30
XP_CONSULTANT_QA = 15
XP_ENTITY_EXTRACTION = 5       # per entity, max 5 entities per session
XP_FIRST_ACTION_TODAY = 10
XP_DAILY_CAP = 500             # automated sources only (quests + achievements exempt)
MAX_STREAK_BONUS = 50          # streak_days * 5, capped at 50

# Milestone XP bursts on hitting these streak lengths (idempotent per length)
STREAK_MILESTONES: Dict[int, int] = {
    3: 50,
    7: 150,
    14: 300,
    30: 750,
    60: 1500,
    100: 3000,
    365: 10000,
}


# ── Level formula ─────────────────────────────────────────────────────────────
# cumulative_xp(level) = 50 × level × (level - 1)
# level_for_xp(xp)     = floor((1 + sqrt(1 + 4*xp/50)) / 2)

def _xp_for_level(level: int) -> int:
    """Cumulative XP required to reach `level`."""
    return 50 * level * (level - 1)


def _level_for_xp(total_xp: int) -> int:
    """Current level for a given total XP amount."""
    if total_xp <= 0:
        return 1
    level = int((1 + math.sqrt(1 + 4 * total_xp / 50)) / 2)
    return max(1, level)


class GamificationService:
    """
    Handles all gamification logic. All methods are async and never raise.
    Call via fire_and_forget() from routes to avoid blocking responses.
    """

    def __init__(self):
        print("🎮 Gamification Service: Initialized")

    # ══════════════════════════════════════════════════════════════════════════
    # XP Awarding
    # ══════════════════════════════════════════════════════════════════════════

    async def award_xp(
        self,
        user_id: str,
        amount: int,
        source_type: str,
        source_id: Optional[str] = None,
        description: Optional[str] = None,
    ) -> None:
        """
        Award XP to a user and update their gamification profile.
        - Skips silently if source_id was already awarded (idempotency).
        - Enforces daily cap for automated sources.
        - Triggers achievement check after awarding.
        """
        if not db or amount <= 0:
            return
        try:
            # Anti-duplicate guard
            if source_id:
                existing = await asyncio.to_thread(
                    lambda: db.table("xp_transactions")
                    .select("id")
                    .eq("user_id", user_id)
                    .eq("source_type", source_type)
                    .eq("source_id", source_id)
                    .maybe_single()
                    .execute()
                )
                if existing is not None and existing.data:
                    return  # Already awarded — skip silently

            # Daily cap check for automated sources
            automated = {"session_complete", "consultant_qa", "entity_extraction"}
            if source_type in automated:
                today_start = datetime.now(timezone.utc).replace(
                    hour=0, minute=0, second=0, microsecond=0
                ).isoformat()
                today_xp_res = await asyncio.to_thread(
                    lambda: db.table("xp_transactions")
                    .select("amount")
                    .eq("user_id", user_id)
                    .in_("source_type", list(automated))
                    .gte("created_at", today_start)
                    .execute()
                )
                today_xp = sum(r["amount"] for r in (today_xp_res.data or []))
                if today_xp >= XP_DAILY_CAP:
                    return  # Cap reached for today

            # Insert XP transaction
            tx_row: Dict[str, Any] = {
                "user_id": user_id,
                "amount": amount,
                "source_type": source_type,
                "created_at": datetime.now(timezone.utc).isoformat(),
            }
            if source_id:
                tx_row["source_id"] = source_id
            if description:
                tx_row["description"] = description

            await asyncio.to_thread(
                lambda: db.table("xp_transactions").insert(tx_row).execute()
            )

            # Upsert gamification profile — increment total_xp and update level
            profile_res = await asyncio.to_thread(
                lambda: db.table("user_gamification")
                .select("total_xp, last_active_date")
                .eq("user_id", user_id)
                .maybe_single()
                .execute()
            )

            current_xp = 0
            if profile_res is not None and profile_res.data:
                current_xp = profile_res.data.get("total_xp", 0) or 0

            new_xp = current_xp + amount
            new_level = _level_for_xp(new_xp)

            await asyncio.to_thread(
                lambda: db.table("user_gamification").upsert({
                    "user_id": user_id,
                    "total_xp": new_xp,
                    "level": new_level,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                }, on_conflict="user_id").execute()
            )

            # Check for newly unlocked achievements
            await self.check_achievements(user_id)

        except Exception as e:
            print(f"⚠️ GamificationService.award_xp error: {e}")

    # ══════════════════════════════════════════════════════════════════════════
    # Streak Management
    # ══════════════════════════════════════════════════════════════════════════

    async def update_streak(self, user_id: str) -> None:
        """
        Update the user's daily usage streak.
        - Increments streak if last_active_date was yesterday.
        - Consumes a streak freeze if last_active_date was 2 days ago.
        - Resets streak to 1 if gap > 2 days (or no freeze available).
        - Awards a streak bonus XP proportional to current_streak.

        Note: All dates are in server UTC. A "day" resets at midnight UTC.
        """
        if not db:
            return
        try:
            today = date.today()
            yesterday = today - timedelta(days=1)
            two_days_ago = today - timedelta(days=2)

            profile_res = await asyncio.to_thread(
                lambda: db.table("user_gamification")
                .select("current_streak, longest_streak, last_active_date, streak_freezes")
                .eq("user_id", user_id)
                .maybe_single()
                .execute()
            )

            if profile_res is None or not profile_res.data:
                # First ever activity — create profile
                await asyncio.to_thread(
                    lambda: db.table("user_gamification").upsert({
                        "user_id": user_id,
                        "current_streak": 1,
                        "longest_streak": 1,
                        "last_active_date": today.isoformat(),
                        "streak_freezes": 1,
                        "total_xp": 0,
                        "level": 1,
                    }, on_conflict="user_id").execute()
                )
                return

            data = profile_res.data
            last_date_str = data.get("last_active_date")
            current_streak = data.get("current_streak", 0) or 0
            longest_streak = data.get("longest_streak", 0) or 0
            streak_freezes = data.get("streak_freezes", 1) or 1

            last_date = None
            if last_date_str:
                try:
                    last_date = date.fromisoformat(last_date_str)
                except ValueError:
                    pass

            # Determine new streak value
            if last_date == today:
                return  # Already counted today — no-op

            if last_date == yesterday:
                current_streak += 1
            elif last_date == two_days_ago and streak_freezes > 0:
                streak_freezes -= 1   # Consume freeze, streak preserved
            else:
                current_streak = 1    # Reset with "Welcome back!" (ethical UX)

            if current_streak > longest_streak:
                longest_streak = current_streak

            await asyncio.to_thread(
                lambda: db.table("user_gamification").upsert({
                    "user_id": user_id,
                    "current_streak": current_streak,
                    "longest_streak": longest_streak,
                    "last_active_date": today.isoformat(),
                    "streak_freezes": streak_freezes,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                }, on_conflict="user_id").execute()
            )

            # Daily streak bonus: 5 × streak_days, capped at 50 XP
            if current_streak > 1:
                bonus = min(current_streak * 5, MAX_STREAK_BONUS)
                await self.award_xp(
                    user_id, bonus, "streak_bonus",
                    source_id=f"streak_{today.isoformat()}",
                    description=f"{current_streak}-day streak bonus",
                )

            # Milestone burst (idempotent — source_id pinned to the milestone length)
            milestone_bonus = STREAK_MILESTONES.get(current_streak)
            if milestone_bonus:
                await self.award_xp(
                    user_id, milestone_bonus, "streak_milestone",
                    source_id=f"milestone_{current_streak}",
                    description=f"{current_streak}-day streak milestone reached!",
                )

        except Exception as e:
            print(f"⚠️ GamificationService.update_streak error: {e}")

    # ══════════════════════════════════════════════════════════════════════════
    # Quest Management
    # ══════════════════════════════════════════════════════════════════════════

    async def get_or_assign_daily_quests(self, user_id: str) -> List[Dict]:
        """
        Return today's assigned quests. If none exist, adaptively pick 3 from
        active daily quest definitions, weighted by the user's focus areas and
        recommended difficulty (falls back to random when no signal exists).
        """
        if not db:
            return []
        try:
            today = date.today().isoformat()

            # Check for already-assigned quests today
            existing = await asyncio.to_thread(
                lambda: db.table("user_quests")
                .select("id, quest_id, progress, target, is_completed, assigned_date, completed_at, xp_awarded, reason, brief_state")
                .eq("user_id", user_id)
                .eq("assigned_date", today)
                .execute()
            )

            if existing is not None and existing.data:
                return await self._enrich_quests(existing.data)

            defs_res = await asyncio.to_thread(
                lambda: db.table("quest_definitions")
                .select("id, title, description, action_type, target, xp_reward, focus_area, difficulty, mission_type, brief")
                .eq("is_active", True)
                .eq("quest_type", "daily")
                .execute()
            )

            defs = defs_res.data or []
            if not defs:
                return []

            focus_areas, difficulty = await self._compute_focus_and_difficulty(user_id)
            picks = self._adaptive_pick_quests(defs, focus_areas, difficulty, k=3)

            rows = []
            for d, reason in picks:
                mtype = d.get("mission_type") or "action"
                brief = d.get("brief") or {}
                target = d.get("target") or 1
                if mtype == "question_set":
                    target = max(len(brief.get("questions") or []), 1)
                elif mtype == "conversation":
                    target = 1

                rows.append({
                    "user_id": user_id,
                    "quest_id": d["id"],
                    "progress": 0,
                    "target": target,
                    "is_completed": False,
                    "assigned_date": today,
                    "xp_awarded": False,
                    "reason": reason,
                    "brief_state": {},
                })

            insert_res = await asyncio.to_thread(
                lambda: db.table("user_quests").insert(rows).execute()
            )

            return await self._enrich_quests(insert_res.data or [])

        except Exception as e:
            print(f"⚠️ GamificationService.get_or_assign_daily_quests error: {e}")
            return []

    # ── Adaptive mission helpers ──────────────────────────────────────────
    async def _compute_focus_and_difficulty(
        self, user_id: str
    ) -> tuple[List[str], str]:
        """
        Derive focus_areas + recommended difficulty from last 7 days of activity.
        Mirrors the performance_summary route so quest assignment stays aligned
        with the user-facing performance tier.
        """
        focus_areas: List[str] = []
        difficulty = "medium"
        try:
            week_ago = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()

            analytics_res = await asyncio.to_thread(
                lambda: db.table("session_analytics")
                .select("mutual_engagement_score, user_filler_count, avg_sentiment_score")
                .eq("user_id", user_id)
                .gte("created_at", week_ago)
                .limit(20)
                .execute()
            )
            rows = analytics_res.data or []

            def _avg(key, default):
                vals = [r.get(key) for r in rows if r.get(key) is not None]
                return sum(vals) / len(vals) if vals else default

            engagement_avg = _avg("mutual_engagement_score", 5.0)
            sentiment_avg = _avg("avg_sentiment_score", 0.0)
            sentiment_norm = (sentiment_avg + 1) * 5
            avg_fillers = _avg("user_filler_count", 0)

            sess_res = await asyncio.to_thread(
                lambda: db.table("sessions")
                .select("id", count="exact")
                .eq("user_id", user_id)
                .eq("status", "completed")
                .gte("created_at", week_ago)
                .execute()
            )
            session_freq = min((sess_res.count or 0) / 7 * 10, 10)

            quest_res = await asyncio.to_thread(
                lambda: db.table("user_quests")
                .select("id, is_completed")
                .eq("user_id", user_id)
                .gte("assigned_date", (date.today() - timedelta(days=7)).isoformat())
                .execute()
            )
            qdata = quest_res.data or []
            completion_rate = (
                sum(1 for q in qdata if q.get("is_completed")) / len(qdata)
                if qdata else 0.5
            )

            if engagement_avg < 5: focus_areas.append("engagement")
            if avg_fillers > 3: focus_areas.append("filler_words")
            if sentiment_norm < 5: focus_areas.append("positivity")
            if session_freq < 4: focus_areas.append("consistency")
            if completion_rate < 0.5: focus_areas.append("quest_completion")

            composite = (
                engagement_avg * 0.3
                + sentiment_norm * 0.15
                + session_freq * 0.2
                + completion_rate * 10 * 0.15
                + max(0, 10 - avg_fillers) * 0.1
            )
            if composite >= 7.5:
                difficulty = "challenge"
            elif composite >= 5.0:
                difficulty = "hard"
            elif composite >= 3.0:
                difficulty = "medium"
            else:
                difficulty = "easy"

        except Exception as e:
            print(f"⚠️ _compute_focus_and_difficulty error: {e}")

        return focus_areas, difficulty

    def _adaptive_pick_quests(
        self,
        defs: List[Dict],
        focus_areas: List[str],
        difficulty: str,
        k: int = 3,
    ) -> List[tuple]:
        """
        Weighted selection of k quests. Returns list of (definition, reason) tuples.
        Score: +3 focus_area match, +2 difficulty match, +1 baseline.
        Picked via jittered top-k so high-score defs win without collapsing
        to the same pick for every user.
        """
        focus_set = set(focus_areas)
        scored = []
        for d in defs:
            area = d.get("focus_area")
            diff = d.get("difficulty") or "medium"

            score = 1
            reason = "Daily variety pick"
            if area and area in focus_set:
                score = 3
                reason = f"Targets your weak area: {area.replace('_', ' ')}"
            elif diff == difficulty:
                score = 2
                reason = f"Tuned to your current level ({difficulty})"

            jitter = random.random()
            scored.append((score + jitter, d, reason))

        scored.sort(key=lambda t: t[0], reverse=True)
        return [(d, reason) for _, d, reason in scored[:k]]

    async def _enrich_quests(self, user_quests: List[Dict]) -> List[Dict]:
        """Join user_quests with quest_definitions to add title/description/xp_reward."""
        if not user_quests or not db:
            return user_quests
        try:
            quest_ids = list({q["quest_id"] for q in user_quests})
            defs_res = await asyncio.to_thread(
                lambda: db.table("quest_definitions")
                .select("id, title, description, xp_reward, action_type, focus_area, difficulty, mission_type, brief")
                .in_("id", quest_ids)
                .execute()
            )
            defs_map = {d["id"]: d for d in (defs_res.data or [])}

            enriched = []
            for uq in user_quests:
                qdef = defs_map.get(uq["quest_id"], {})
                enriched.append({
                    **uq,
                    "title": qdef.get("title", uq["quest_id"]),
                    "description": qdef.get("description", ""),
                    "xp_reward": qdef.get("xp_reward", 0),
                    "action_type": qdef.get("action_type", ""),
                    "focus_area": qdef.get("focus_area"),
                    "difficulty": qdef.get("difficulty"),
                    "mission_type": qdef.get("mission_type") or "action",
                    "brief": qdef.get("brief") or {},
                })
            return enriched
        except Exception:
            return user_quests

    async def increment_quest_progress(
        self,
        user_id: str,
        action_type: str,
        count: int = 1,
    ) -> None:
        """
        Advance progress on today's active quests matching action_type.
        Auto-completes and awards XP when progress >= target.
        """
        if not db:
            return
        try:
            today = date.today().isoformat()
            quests_res = await asyncio.to_thread(
                lambda: db.table("user_quests")
                .select("id, quest_id, progress, target, is_completed, xp_awarded")
                .eq("user_id", user_id)
                .eq("assigned_date", today)
                .eq("is_completed", False)
                .execute()
            )
            active_quests = quests_res.data or []

            # Get matching quest definitions
            if not active_quests:
                return

            quest_ids = [q["quest_id"] for q in active_quests]
            defs_res = await asyncio.to_thread(
                lambda: db.table("quest_definitions")
                .select("id, action_type, xp_reward")
                .in_("id", quest_ids)
                .execute()
            )
            defs_map = {d["id"]: d for d in (defs_res.data or [])}

            for quest in active_quests:
                qdef = defs_map.get(quest["quest_id"], {})
                if qdef.get("action_type") != action_type:
                    continue

                new_progress = (quest["progress"] or 0) + count
                is_complete = new_progress >= quest["target"]

                update: Dict[str, Any] = {"progress": new_progress}
                if is_complete:
                    update["is_completed"] = True
                    update["completed_at"] = datetime.now(timezone.utc).isoformat()

                await asyncio.to_thread(
                    lambda qid=quest["id"], upd=update: db.table("user_quests")
                    .update(upd)
                    .eq("id", qid)
                    .execute()
                )

                if is_complete and not quest.get("xp_awarded"):
                    xp_reward = qdef.get("xp_reward", 0)
                    if xp_reward > 0:
                        await self.award_xp(
                            user_id, xp_reward, "quest_complete",
                            source_id=quest["id"],
                            description=f"Completed quest: {quest['quest_id']}",
                        )
                    # Mark xp_awarded to prevent double-award
                    await asyncio.to_thread(
                        lambda qid=quest["id"]: db.table("user_quests")
                        .update({"xp_awarded": True})
                        .eq("id", qid)
                        .execute()
                    )

        except Exception as e:
            print(f"⚠️ GamificationService.increment_quest_progress error: {e}")

    # ══════════════════════════════════════════════════════════════════════════
    # Mission-Type Handlers (Phase 2)
    # ══════════════════════════════════════════════════════════════════════════

    async def submit_question_answer(
        self,
        user_id: str,
        user_quest_id: str,
        question_id: str,
        answer: str,
    ) -> Dict[str, Any]:
        """
        Record an answer for a question_set mission. Increments progress and
        completes the quest (awarding XP) when every brief question is answered.
        Returns the updated user_quest row plus the resolved mission_type.
        Raises ValueError on invalid quest, wrong type, or unknown question id.
        """
        if not db:
            raise RuntimeError("Database unavailable")

        uq_res = await asyncio.to_thread(
            lambda: db.table("user_quests")
            .select("id, user_id, quest_id, progress, target, is_completed, xp_awarded, brief_state")
            .eq("id", user_quest_id)
            .maybe_single()
            .execute()
        )
        if uq_res is None or not uq_res.data:
            raise ValueError("Quest assignment not found")
        uq = uq_res.data
        if uq["user_id"] != user_id:
            raise PermissionError("Quest belongs to another user")

        qdef_res = await asyncio.to_thread(
            lambda: db.table("quest_definitions")
            .select("id, mission_type, brief, xp_reward")
            .eq("id", uq["quest_id"])
            .maybe_single()
            .execute()
        )
        if qdef_res is None or not qdef_res.data:
            raise ValueError("Quest definition missing")
        qdef = qdef_res.data
        if (qdef.get("mission_type") or "action") != "question_set":
            raise ValueError("Quest is not a question_set mission")

        questions = (qdef.get("brief") or {}).get("questions") or []
        valid_ids = {q.get("id") for q in questions}
        if question_id not in valid_ids:
            raise ValueError(f"Unknown question id: {question_id}")

        state = uq.get("brief_state") or {}
        answers = dict(state.get("answers") or {})
        already_answered = question_id in answers
        answers[question_id] = answer
        state["answers"] = answers

        new_progress = len(answers)
        target = uq.get("target") or len(questions) or 1
        is_complete = (not uq.get("is_completed")) and new_progress >= target

        update: Dict[str, Any] = {
            "brief_state": state,
            "progress": new_progress,
        }
        if is_complete:
            update["is_completed"] = True
            update["completed_at"] = datetime.now(timezone.utc).isoformat()

        await asyncio.to_thread(
            lambda: db.table("user_quests")
            .update(update)
            .eq("id", user_quest_id)
            .execute()
        )

        if is_complete and not uq.get("xp_awarded"):
            xp_reward = qdef.get("xp_reward", 0) or 0
            if xp_reward > 0:
                await self.award_xp(
                    user_id, xp_reward, "quest_complete",
                    source_id=user_quest_id,
                    description=f"Completed question_set quest: {qdef['id']}",
                )
            await asyncio.to_thread(
                lambda: db.table("user_quests")
                .update({"xp_awarded": True})
                .eq("id", user_quest_id)
                .execute()
            )

        return {
            "user_quest_id": user_quest_id,
            "mission_type": "question_set",
            "progress": new_progress,
            "target": target,
            "is_completed": is_complete or bool(uq.get("is_completed")),
            "answers_count": new_progress,
            "answer_replaced": already_answered,
        }

    async def attach_conversation_session(
        self,
        user_id: str,
        user_quest_id: str,
        session_id: str,
    ) -> Dict[str, Any]:
        """
        Attach a session to a conversation mission and evaluate the transcript
        against the brief. Mission completes (and XP awards) only if:
          • the session has at least brief.min_turns user turns, AND
          • the brain evaluator returns passed=True for the brief criteria.

        On failure, brief_state stores the score/feedback so the user sees why
        it didn't qualify and can attach a different session.
        """
        if not db:
            raise RuntimeError("Database unavailable")

        uq_res = await asyncio.to_thread(
            lambda: db.table("user_quests")
            .select("id, user_id, quest_id, progress, target, is_completed, xp_awarded, brief_state")
            .eq("id", user_quest_id)
            .maybe_single()
            .execute()
        )
        if uq_res is None or not uq_res.data:
            raise ValueError("Quest assignment not found")
        uq = uq_res.data
        if uq["user_id"] != user_id:
            raise PermissionError("Quest belongs to another user")

        qdef_res = await asyncio.to_thread(
            lambda: db.table("quest_definitions")
            .select("id, mission_type, brief, xp_reward")
            .eq("id", uq["quest_id"])
            .maybe_single()
            .execute()
        )
        if qdef_res is None or not qdef_res.data:
            raise ValueError("Quest definition missing")
        qdef = qdef_res.data
        if (qdef.get("mission_type") or "action") != "conversation":
            raise ValueError("Quest is not a conversation mission")

        sess_res = await asyncio.to_thread(
            lambda: db.table("sessions")
            .select("id, user_id, status")
            .eq("id", session_id)
            .maybe_single()
            .execute()
        )
        if sess_res is None or not sess_res.data:
            raise ValueError("Session not found")
        if sess_res.data.get("user_id") != user_id:
            raise PermissionError("Session belongs to another user")

        # Pull transcript
        logs_res = await asyncio.to_thread(
            lambda: db.table("session_logs")
            .select("role, content, turn_index")
            .eq("session_id", session_id)
            .order("turn_index")
            .limit(500)
            .execute()
        )
        logs = logs_res.data or []
        user_turn_count = sum(1 for r in logs if (r.get("role") or "").lower() == "user")

        brief = qdef.get("brief") or {}
        min_turns = int(brief.get("min_turns") or 0)

        transcript_lines = []
        for r in logs:
            role = (r.get("role") or "").strip()
            content = (r.get("content") or "").strip()
            if not role or not content:
                continue
            transcript_lines.append(f"{role.upper()}: {content}")
        transcript = "\n".join(transcript_lines)

        # Lazy import to avoid circular dependency on app.services package init
        from app.services import brain_svc

        state = uq.get("brief_state") or {}
        state["session_id"] = session_id
        state["attached_at"] = datetime.now(timezone.utc).isoformat()
        state["user_turn_count"] = user_turn_count

        # Hard gate on min_turns before spending an LLM call
        if user_turn_count < min_turns:
            state["passed"] = False
            state["score"] = 0.0
            state["feedback"] = (
                f"Session has {user_turn_count} user turns, need at least {min_turns}."
            )
            await asyncio.to_thread(
                lambda: db.table("user_quests")
                .update({"brief_state": state})
                .eq("id", user_quest_id)
                .execute()
            )
            return {
                "user_quest_id": user_quest_id,
                "mission_type": "conversation",
                "session_id": session_id,
                "is_completed": False,
                "passed": False,
                "score": 0.0,
                "feedback": state["feedback"],
                "criteria_met": [],
            }

        evaluation = await brain_svc.evaluate_conversation_mission(transcript, brief)
        state["score"] = evaluation.get("score", 0.0)
        state["passed"] = evaluation.get("passed", False)
        state["feedback"] = evaluation.get("feedback", "")
        state["criteria_met"] = evaluation.get("criteria_met", [])
        state["evaluated_at"] = datetime.now(timezone.utc).isoformat()

        passed = bool(evaluation.get("passed"))
        already_complete = bool(uq.get("is_completed"))
        will_complete = passed and not already_complete

        update: Dict[str, Any] = {"brief_state": state}
        if will_complete:
            update["progress"] = 1
            update["is_completed"] = True
            update["completed_at"] = datetime.now(timezone.utc).isoformat()

        await asyncio.to_thread(
            lambda: db.table("user_quests")
            .update(update)
            .eq("id", user_quest_id)
            .execute()
        )

        if will_complete and not uq.get("xp_awarded"):
            xp_reward = qdef.get("xp_reward", 0) or 0
            if xp_reward > 0:
                await self.award_xp(
                    user_id, xp_reward, "quest_complete",
                    source_id=user_quest_id,
                    description=f"Completed conversation quest: {qdef['id']}",
                )
            await asyncio.to_thread(
                lambda: db.table("user_quests")
                .update({"xp_awarded": True})
                .eq("id", user_quest_id)
                .execute()
            )

        return {
            "user_quest_id": user_quest_id,
            "mission_type": "conversation",
            "session_id": session_id,
            "is_completed": will_complete or already_complete,
            "passed": passed,
            "score": state["score"],
            "feedback": state["feedback"],
            "criteria_met": state["criteria_met"],
        }

    # ══════════════════════════════════════════════════════════════════════════
    # Rewards (Phase 3)
    # ══════════════════════════════════════════════════════════════════════════

    async def list_rewards(self, user_id: str) -> Dict[str, Any]:
        """
        Return the active reward catalog plus the user's current XP balance,
        owned reward ids, and per-item affordability + ownership flags.
        """
        if not db:
            return {"rewards": [], "owned_ids": [], "balance": 0, "total_xp": 0, "xp_spent": 0}

        try:
            catalog_res = await asyncio.to_thread(
                lambda: db.table("rewards")
                .select("id, title, description, icon, category, cost_xp, sort_order")
                .eq("is_active", True)
                .order("sort_order")
                .order("cost_xp")
                .execute()
            )
            catalog = catalog_res.data or []

            owned_res = await asyncio.to_thread(
                lambda: db.table("user_rewards")
                .select("reward_id, unlocked_at, cost_xp")
                .eq("user_id", user_id)
                .execute()
            )
            owned_rows = owned_res.data or []
            owned_map = {r["reward_id"]: r for r in owned_rows}

            profile_res = await asyncio.to_thread(
                lambda: db.table("user_gamification")
                .select("total_xp, xp_spent")
                .eq("user_id", user_id)
                .maybe_single()
                .execute()
            )
            total_xp = 0
            xp_spent = 0
            if profile_res is not None and profile_res.data:
                total_xp = profile_res.data.get("total_xp", 0) or 0
                xp_spent = profile_res.data.get("xp_spent", 0) or 0
            balance = max(total_xp - xp_spent, 0)

            enriched = []
            for r in catalog:
                owned = r["id"] in owned_map
                cost = r.get("cost_xp", 0) or 0
                enriched.append({
                    **r,
                    "owned": owned,
                    "unlocked_at": owned_map[r["id"]]["unlocked_at"] if owned else None,
                    "affordable": (not owned) and balance >= cost,
                })

            return {
                "rewards": enriched,
                "owned_ids": list(owned_map.keys()),
                "balance": balance,
                "total_xp": total_xp,
                "xp_spent": xp_spent,
            }
        except Exception as e:
            print(f"⚠️ GamificationService.list_rewards error: {e}")
            return {"rewards": [], "owned_ids": [], "balance": 0, "total_xp": 0, "xp_spent": 0}

    async def redeem_reward(self, user_id: str, reward_id: str) -> Dict[str, Any]:
        """
        Redeem a reward for the user. Validates active+affordable+not-owned,
        debits xp_spent, inserts user_rewards, and logs a negative xp_transaction.
        Raises ValueError on validation errors, PermissionError on auth misuse.
        """
        if not db:
            raise RuntimeError("Database unavailable")

        reward_res = await asyncio.to_thread(
            lambda: db.table("rewards")
            .select("id, title, cost_xp, is_active")
            .eq("id", reward_id)
            .maybe_single()
            .execute()
        )
        if reward_res is None or not reward_res.data:
            raise ValueError("Reward not found")
        reward = reward_res.data
        if not reward.get("is_active"):
            raise ValueError("Reward is not currently available")
        cost = int(reward.get("cost_xp") or 0)
        if cost <= 0:
            raise ValueError("Reward has invalid cost")

        existing_res = await asyncio.to_thread(
            lambda: db.table("user_rewards")
            .select("id")
            .eq("user_id", user_id)
            .eq("reward_id", reward_id)
            .maybe_single()
            .execute()
        )
        if existing_res is not None and existing_res.data:
            raise ValueError("Reward already owned")

        profile_res = await asyncio.to_thread(
            lambda: db.table("user_gamification")
            .select("total_xp, xp_spent")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        total_xp = 0
        xp_spent = 0
        if profile_res is not None and profile_res.data:
            total_xp = profile_res.data.get("total_xp", 0) or 0
            xp_spent = profile_res.data.get("xp_spent", 0) or 0
        balance = total_xp - xp_spent
        if balance < cost:
            raise ValueError(f"Insufficient XP: need {cost}, have {balance}")

        # Insert ownership row first; unique(user_id, reward_id) blocks races
        try:
            await asyncio.to_thread(
                lambda: db.table("user_rewards").insert({
                    "user_id": user_id,
                    "reward_id": reward_id,
                    "cost_xp": cost,
                    "unlocked_at": datetime.now(timezone.utc).isoformat(),
                }).execute()
            )
        except Exception as e:
            # Likely unique violation (race) — treat as already owned
            print(f"⚠️ redeem_reward insert race: {e}")
            raise ValueError("Reward already owned")

        # Debit balance
        new_spent = xp_spent + cost
        await asyncio.to_thread(
            lambda: db.table("user_gamification").upsert({
                "user_id": user_id,
                "xp_spent": new_spent,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }, on_conflict="user_id").execute()
        )

        # Audit row in xp_transactions (negative amount, descriptive source)
        try:
            await asyncio.to_thread(
                lambda: db.table("xp_transactions").insert({
                    "user_id": user_id,
                    "amount": -cost,
                    "source_type": "reward_redeem",
                    "source_id": reward_id,
                    "description": f"Redeemed reward: {reward.get('title') or reward_id}",
                    "created_at": datetime.now(timezone.utc).isoformat(),
                }).execute()
            )
        except Exception as e:
            print(f"⚠️ redeem_reward audit insert: {e}")

        return {
            "reward_id": reward_id,
            "title": reward.get("title"),
            "cost_xp": cost,
            "new_balance": max(total_xp - new_spent, 0),
            "xp_spent": new_spent,
            "total_xp": total_xp,
        }

    # ══════════════════════════════════════════════════════════════════════════
    # Leaderboards (Phase 4)
    # ══════════════════════════════════════════════════════════════════════════

    async def get_leaderboard(
        self,
        requesting_user_id: str,
        period: str = "all",
        limit: int = 25,
    ) -> Dict[str, Any]:
        """
        Return the global leaderboard for a period plus the requester's rank.
        period: daily | weekly | monthly | all
        Only users with leaderboard_opt_in=true are listed; the requester is
        always included in their own rank/value even if opted out.
        """
        if not db:
            return {"period": period, "rows": [], "self": None, "total_ranked": 0}

        period = period if period in ("daily", "weekly", "monthly", "all") else "all"
        limit = max(1, min(limit, 100))

        try:
            opted_res = await asyncio.to_thread(
                lambda: db.table("user_gamification")
                .select("user_id")
                .eq("leaderboard_opt_in", True)
                .execute()
            )
            opted_ids = {r["user_id"] for r in (opted_res.data or [])}

            # Build (user_id, score) ranking
            scores: Dict[str, int] = {}

            if period == "all":
                profiles_res = await asyncio.to_thread(
                    lambda: db.table("user_gamification")
                    .select("user_id, total_xp")
                    .eq("leaderboard_opt_in", True)
                    .gt("total_xp", 0)
                    .order("total_xp", desc=True)
                    .limit(500)
                    .execute()
                )
                for r in (profiles_res.data or []):
                    scores[r["user_id"]] = r.get("total_xp", 0) or 0
            else:
                window_start = self._period_window_start(period)
                tx_res = await asyncio.to_thread(
                    lambda: db.table("xp_transactions")
                    .select("user_id, amount")
                    .gte("created_at", window_start.isoformat())
                    .gt("amount", 0)
                    .limit(20000)
                    .execute()
                )
                for r in (tx_res.data or []):
                    uid = r.get("user_id")
                    if not uid or uid not in opted_ids:
                        continue
                    scores[uid] = scores.get(uid, 0) + (r.get("amount") or 0)

            ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)
            top = ranked[:limit]

            # Resolve display names + avatars
            user_ids = [uid for uid, _ in top]
            profile_map: Dict[str, Dict[str, Any]] = {}
            if user_ids:
                prof_res = await asyncio.to_thread(
                    lambda: db.table("profiles")
                    .select("id, full_name, avatar_url")
                    .in_("id", user_ids)
                    .execute()
                )
                profile_map = {p["id"]: p for p in (prof_res.data or [])}

            rows = []
            for rank, (uid, score) in enumerate(top, start=1):
                prof = profile_map.get(uid, {})
                rows.append({
                    "rank": rank,
                    "user_id": uid,
                    "display_name": prof.get("full_name") or "Anonymous",
                    "avatar_url": prof.get("avatar_url"),
                    "score": score,
                    "is_you": uid == requesting_user_id,
                })

            # Caller's own rank — even if outside top N or opted out
            self_score = await self._compute_user_period_score(
                requesting_user_id, period, ranked
            )
            self_rank = None
            for r, (uid, _) in enumerate(ranked, start=1):
                if uid == requesting_user_id:
                    self_rank = r
                    break

            self_prof_res = await asyncio.to_thread(
                lambda: db.table("profiles")
                .select("full_name, avatar_url")
                .eq("id", requesting_user_id)
                .maybe_single()
                .execute()
            )
            self_prof = self_prof_res.data if self_prof_res is not None else None

            opt_res = await asyncio.to_thread(
                lambda: db.table("user_gamification")
                .select("leaderboard_opt_in")
                .eq("user_id", requesting_user_id)
                .maybe_single()
                .execute()
            )
            opt_in = True
            if opt_res is not None and opt_res.data is not None:
                opt_in = bool(opt_res.data.get("leaderboard_opt_in", True))

            self_payload = {
                "rank": self_rank,
                "score": self_score,
                "display_name": (self_prof or {}).get("full_name") or "You",
                "avatar_url": (self_prof or {}).get("avatar_url"),
                "leaderboard_opt_in": opt_in,
                "total_ranked": len(ranked),
            }

            return {
                "period": period,
                "rows": rows,
                "self": self_payload,
                "total_ranked": len(ranked),
            }
        except Exception as e:
            print(f"⚠️ GamificationService.get_leaderboard error: {e}")
            return {"period": period, "rows": [], "self": None, "total_ranked": 0}

    async def set_leaderboard_opt_in(self, user_id: str, opt_in: bool) -> bool:
        """Toggle leaderboard visibility for a user."""
        if not db:
            return False
        try:
            await asyncio.to_thread(
                lambda: db.table("user_gamification").upsert({
                    "user_id": user_id,
                    "leaderboard_opt_in": opt_in,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                }, on_conflict="user_id").execute()
            )
            return True
        except Exception as e:
            print(f"⚠️ GamificationService.set_leaderboard_opt_in error: {e}")
            return False

    def _period_window_start(self, period: str) -> datetime:
        now = datetime.now(timezone.utc)
        if period == "daily":
            return now.replace(hour=0, minute=0, second=0, microsecond=0)
        if period == "weekly":
            start_of_day = now.replace(hour=0, minute=0, second=0, microsecond=0)
            return start_of_day - timedelta(days=now.weekday())
        if period == "monthly":
            return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        return datetime(1970, 1, 1, tzinfo=timezone.utc)

    async def _compute_user_period_score(
        self,
        user_id: str,
        period: str,
        ranked: List[tuple],
    ) -> int:
        """Pull caller's score from the ranked snapshot if present, else compute."""
        for uid, score in ranked:
            if uid == user_id:
                return score
        # Caller wasn't in the snapshot — usually means opt-out or zero. Compute.
        try:
            if period == "all":
                res = await asyncio.to_thread(
                    lambda: db.table("user_gamification")
                    .select("total_xp")
                    .eq("user_id", user_id)
                    .maybe_single()
                    .execute()
                )
                if res is not None and res.data:
                    return res.data.get("total_xp", 0) or 0
                return 0
            window_start = self._period_window_start(period)
            tx_res = await asyncio.to_thread(
                lambda: db.table("xp_transactions")
                .select("amount")
                .eq("user_id", user_id)
                .gte("created_at", window_start.isoformat())
                .gt("amount", 0)
                .execute()
            )
            return sum((r.get("amount") or 0) for r in (tx_res.data or []))
        except Exception:
            return 0

    # ══════════════════════════════════════════════════════════════════════════
    # Achievement Detection
    # ══════════════════════════════════════════════════════════════════════════

    async def check_achievements(self, user_id: str) -> List[Dict[str, Any]]:
        """
        Check all achievement definitions against user stats and unlock any
        newly earned ones. Returns the list of newly unlocked achievements
        (with title, description, icon, tier) so the caller can surface them
        to the client as toast notifications.
        """
        if not db:
            return []
        newly_unlocked: List[Dict[str, Any]] = []
        try:
            all_achiev_res = await asyncio.to_thread(
                lambda: db.table("achievements")
                .select("id, code, title, description, icon, category, tier, criteria_type, criteria_value, xp_reward")
                .execute()
            )
            earned_res = await asyncio.to_thread(
                lambda: db.table("user_achievements")
                .select("achievement_id")
                .eq("user_id", user_id)
                .execute()
            )

            all_achievements = all_achiev_res.data or []
            earned_ids = {r["achievement_id"] for r in (earned_res.data or [])}

            un_earned = [a for a in all_achievements if a["id"] not in earned_ids]
            if not un_earned:
                return []

            stats = await self._get_user_stats(user_id)

            criteria_map = {
                "total_xp": stats.get("total_xp", 0),
                "streak": stats.get("current_streak", 0),
                "session_count": stats.get("session_count", 0),
                "consultant_count": stats.get("consultant_count", 0),
                "entity_count": stats.get("entity_count", 0),
                "quest_count": stats.get("quest_count", 0),
            }

            for achiev in un_earned:
                ctype = achiev.get("criteria_type")
                cvalue = achiev.get("criteria_value", 0)
                user_value = criteria_map.get(ctype, 0)

                if user_value < cvalue:
                    continue

                # Unlock — guard against race via insert-then-catch
                inserted = False
                try:
                    res = await asyncio.to_thread(
                        lambda aid=achiev["id"]: db.table("user_achievements").insert({
                            "user_id": user_id,
                            "achievement_id": aid,
                            "awarded_at": datetime.now(timezone.utc).isoformat(),
                        }).execute()
                    )
                    inserted = bool(getattr(res, "data", None))
                except Exception:
                    inserted = False

                if not inserted:
                    continue

                newly_unlocked.append({
                    "id": achiev["id"],
                    "code": achiev.get("code"),
                    "title": achiev.get("title", ""),
                    "description": achiev.get("description", ""),
                    "icon": achiev.get("icon", "🏆"),
                    "category": achiev.get("category", "general"),
                    "tier": achiev.get("tier", "bronze"),
                    "xp_reward": achiev.get("xp_reward", 0),
                })

                if achiev.get("xp_reward", 0) > 0:
                    await self.award_xp(
                        user_id,
                        achiev["xp_reward"],
                        "achievement_unlock",
                        source_id=achiev["id"],
                        description=f"Achievement unlocked: {achiev.get('title') or achiev['id']}",
                    )

        except Exception as e:
            print(f"⚠️ GamificationService.check_achievements error: {e}")

        return newly_unlocked

    async def _get_user_stats(self, user_id: str) -> Dict[str, int]:
        """Fetch aggregate stats needed for achievement criteria evaluation."""
        stats: Dict[str, int] = {}
        try:
            profile_res = await asyncio.to_thread(
                lambda: db.table("user_gamification")
                .select("total_xp, current_streak")
                .eq("user_id", user_id)
                .maybe_single()
                .execute()
            )
            if profile_res is not None and profile_res.data:
                stats["total_xp"] = profile_res.data.get("total_xp", 0) or 0
                stats["current_streak"] = profile_res.data.get("current_streak", 0) or 0

            # Session count
            sess_res = await asyncio.to_thread(
                lambda: db.table("sessions")
                .select("id", count="exact")
                .eq("user_id", user_id)
                .eq("status", "completed")
                .execute()
            )
            stats["session_count"] = sess_res.count or 0

            # Consultant Q count
            cons_res = await asyncio.to_thread(
                lambda: db.table("consultant_logs")
                .select("id", count="exact")
                .eq("user_id", user_id)
                .execute()
            )
            stats["consultant_count"] = cons_res.count or 0

            # Entity count
            ent_res = await asyncio.to_thread(
                lambda: db.table("entities")
                .select("id", count="exact")
                .eq("user_id", user_id)
                .execute()
            )
            stats["entity_count"] = ent_res.count or 0

            # Completed quest count
            quest_res = await asyncio.to_thread(
                lambda: db.table("user_quests")
                .select("id", count="exact")
                .eq("user_id", user_id)
                .eq("is_completed", True)
                .execute()
            )
            stats["quest_count"] = quest_res.count or 0

        except Exception as e:
            print(f"⚠️ GamificationService._get_user_stats error: {e}")
        return stats

    # ══════════════════════════════════════════════════════════════════════════
    # Profile & Quests Response
    # ══════════════════════════════════════════════════════════════════════════

    async def get_gamification_profile(self, user_id: str) -> Dict:
        """
        Return full gamification profile for the /v1/gamification/{user_id} endpoint.
        Creates a default profile row if first-time user.
        """
        if not db:
            return {}
        try:
            # Ensure profile row exists
            profile_res = await asyncio.to_thread(
                lambda: db.table("user_gamification")
                .select("*")
                .eq("user_id", user_id)
                .maybe_single()
                .execute()
            )
            if profile_res is None or not profile_res.data:
                await asyncio.to_thread(
                    lambda: db.table("user_gamification").upsert({
                        "user_id": user_id,
                        "total_xp": 0,
                        "level": 1,
                        "current_streak": 0,
                        "longest_streak": 0,
                        "streak_freezes": 1,
                    }, on_conflict="user_id").execute()
                )
                profile = {
                    "total_xp": 0, "level": 1, "current_streak": 0,
                    "longest_streak": 0, "streak_freezes": 1, "last_active_date": None,
                }
            else:
                profile = profile_res.data

            total_xp = profile.get("total_xp", 0) or 0
            level = _level_for_xp(total_xp)
            xp_current_level = _xp_for_level(level)
            xp_next_level = _xp_for_level(level + 1)
            xp_to_next = xp_next_level - total_xp
            progress_pct = (
                (total_xp - xp_current_level) / max(xp_next_level - xp_current_level, 1)
            )

            # Earned badges
            badges_res = await asyncio.to_thread(
                lambda: db.table("user_achievements")
                .select("achievement_id, awarded_at, achievements(id, title, description, icon, category)")
                .eq("user_id", user_id)
                .execute()
            )
            badges = []
            for row in (badges_res.data or []):
                achiev = row.get("achievements") or {}
                badges.append({
                    "id": achiev.get("id", row["achievement_id"]),
                    "title": achiev.get("title", ""),
                    "description": achiev.get("description", ""),
                    "icon": achiev.get("icon", "🏆"),
                    "category": achiev.get("category", "general"),
                    "awarded_at": row.get("awarded_at"),
                })

            # Recent XP transactions (last 10)
            xp_res = await asyncio.to_thread(
                lambda: db.table("xp_transactions")
                .select("amount, source_type, description, created_at")
                .eq("user_id", user_id)
                .order("created_at", desc=True)
                .limit(10)
                .execute()
            )

            # Aggregate stats
            stats = await self._get_user_stats(user_id)

            xp_spent = profile.get("xp_spent", 0) or 0
            return {
                "xp": total_xp,
                "level": level,
                "xp_current_level": xp_current_level,
                "xp_next_level": xp_next_level,
                "xp_to_next_level": max(xp_to_next, 0),
                "xp_progress_pct": round(max(0.0, min(1.0, progress_pct)), 4),
                "xp_spent": xp_spent,
                "xp_balance": max(total_xp - xp_spent, 0),
                "current_streak": profile.get("current_streak", 0),
                "longest_streak": profile.get("longest_streak", 0),
                "streak_freezes": profile.get("streak_freezes", 1),
                "last_active_date": profile.get("last_active_date"),
                "badges": badges,
                "recent_xp": xp_res.data or [],
                "stats": {
                    "total_sessions": stats.get("session_count", 0),
                    "total_consultant_questions": stats.get("consultant_count", 0),
                    "total_entities": stats.get("entity_count", 0),
                    "total_quests_completed": stats.get("quest_count", 0),
                },
            }

        except Exception as e:
            print(f"⚠️ GamificationService.get_gamification_profile error: {e}")
            return {}
