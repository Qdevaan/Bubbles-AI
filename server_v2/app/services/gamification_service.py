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

            # Award streak bonus: 5 × streak_days, capped at 50 XP
            if current_streak > 1:
                bonus = min(current_streak * 5, MAX_STREAK_BONUS)
                await self.award_xp(
                    user_id, bonus, "streak_bonus",
                    source_id=f"streak_{today.isoformat()}",
                    description=f"{current_streak}-day streak bonus",
                )

        except Exception as e:
            print(f"⚠️ GamificationService.update_streak error: {e}")

    # ══════════════════════════════════════════════════════════════════════════
    # Quest Management
    # ══════════════════════════════════════════════════════════════════════════

    async def get_or_assign_daily_quests(self, user_id: str) -> List[Dict]:
        """
        Return today's assigned quests. If none exist, randomly assign 3 from
        active daily quest definitions.
        """
        if not db:
            return []
        try:
            today = date.today().isoformat()

            # Check for already-assigned quests today
            existing = await asyncio.to_thread(
                lambda: db.table("user_quests")
                .select("id, quest_id, progress, target, is_completed, assigned_date, completed_at, xp_awarded")
                .eq("user_id", user_id)
                .eq("assigned_date", today)
                .execute()
            )

            if existing is not None and existing.data:
                # Enrich with quest definition metadata
                return await self._enrich_quests(existing.data)

            # Assign new quests for today
            defs_res = await asyncio.to_thread(
                lambda: db.table("quest_definitions")
                .select("id, title, description, action_type, target, xp_reward")
                .eq("is_active", True)
                .eq("quest_type", "daily")
                .execute()
            )

            defs = defs_res.data or []
            if not defs:
                return []

            # Randomly pick 3 (or all if fewer than 3 exist)
            selected = random.sample(defs, min(3, len(defs)))

            rows = [{
                "user_id": user_id,
                "quest_id": d["id"],
                "progress": 0,
                "target": d["target"],
                "is_completed": False,
                "assigned_date": today,
                "xp_awarded": False,
            } for d in selected]

            insert_res = await asyncio.to_thread(
                lambda: db.table("user_quests").insert(rows).execute()
            )

            return await self._enrich_quests(insert_res.data or [])

        except Exception as e:
            print(f"⚠️ GamificationService.get_or_assign_daily_quests error: {e}")
            return []

    async def _enrich_quests(self, user_quests: List[Dict]) -> List[Dict]:
        """Join user_quests with quest_definitions to add title/description/xp_reward."""
        if not user_quests or not db:
            return user_quests
        try:
            quest_ids = list({q["quest_id"] for q in user_quests})
            defs_res = await asyncio.to_thread(
                lambda: db.table("quest_definitions")
                .select("id, title, description, xp_reward, action_type")
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
    # Achievement Detection
    # ══════════════════════════════════════════════════════════════════════════

    async def check_achievements(self, user_id: str) -> None:
        """
        Check all achievement definitions against user stats and unlock any
        newly earned ones. Called automatically after every XP award.
        """
        if not db:
            return
        try:
            # Fetch all achievements and already-earned ones
            all_achiev_res = await asyncio.to_thread(
                lambda: db.table("achievements")
                .select("id, criteria_type, criteria_value, xp_reward")
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
                return

            # Gather user stats
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

                if user_value >= cvalue:
                    # Unlock achievement
                    try:
                        await asyncio.to_thread(
                            lambda aid=achiev["id"]: db.table("user_achievements").insert({
                                "user_id": user_id,
                                "achievement_id": aid,
                                "awarded_at": datetime.now(timezone.utc).isoformat(),
                            }).execute()
                        )
                    except Exception:
                        pass  # Unique constraint violation = already exists (race)

                    # Award XP bonus (bounded: only if xp_reward > 0)
                    if achiev.get("xp_reward", 0) > 0:
                        await self.award_xp(
                            user_id,
                            achiev["xp_reward"],
                            "achievement_unlock",
                            source_id=achiev["id"],
                            description=f"Achievement unlocked: {achiev['id']}",
                        )

        except Exception as e:
            print(f"⚠️ GamificationService.check_achievements error: {e}")

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

            return {
                "xp": total_xp,
                "level": level,
                "xp_current_level": xp_current_level,
                "xp_next_level": xp_next_level,
                "xp_to_next_level": max(xp_to_next, 0),
                "xp_progress_pct": round(max(0.0, min(1.0, progress_pct)), 4),
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
