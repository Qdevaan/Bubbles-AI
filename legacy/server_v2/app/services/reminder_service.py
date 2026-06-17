# Purpose: Sends streak-reminder push notifications via Supabase Edge Functions on inactivity.
"""Daily reminder push: top-3 mistake categories per user via FCM."""
from __future__ import annotations

import asyncio
import datetime as dt
from typing import Optional

from app.config import settings


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _humanize(cat: str) -> str:
    return cat.replace("_", " ")


class ReminderService:
    def __init__(self):
        self._fcm_ready = False
        self._db = None

    def init_fcm(self) -> None:
        """Initialise firebase-admin from FCM_CREDENTIALS_PATH. Idempotent."""
        path = settings.FCM_CREDENTIALS_PATH
        if not path:
            print("⚠️  ReminderService: FCM_CREDENTIALS_PATH unset — disabled")
            return
        try:
            import firebase_admin  # type: ignore
            from firebase_admin import credentials  # type: ignore

            cred = credentials.Certificate(path)
            try:
                firebase_admin.initialize_app(cred)
            except ValueError:
                # already initialised
                pass
            from app.database import db as _db
            self._db = _db
            self._fcm_ready = True
            print("📨 ReminderService: FCM ready")
        except Exception as e:
            print(f"⚠️  ReminderService init failed: {e}")
            self._fcm_ready = False

    async def fire_due_reminders(self) -> int:
        """Send reminders for users whose local hour matches now."""
        if not self._fcm_ready or self._db is None:
            return 0

        now_utc = _utcnow()

        try:
            res = await asyncio.to_thread(
                lambda: self._db.table("user_settings")
                    .select("user_id, reminder_hour, reminder_timezone, "
                            "last_reminder_sent_date")
                    .execute()
            )
            rows = res.data or []
        except Exception as e:
            print(f"⚠️  ReminderService user_settings select: {e}")
            return 0

        from firebase_admin import messaging  # type: ignore

        pushed = 0
        for row in rows:
            try:
                tz_name = row.get("reminder_timezone") or "UTC"
                hour = row.get("reminder_hour")
                if hour is None:
                    continue
                tz_now = self._convert_tz(now_utc, tz_name)
                if tz_now.hour != int(hour):
                    continue
                today_iso = tz_now.date().isoformat()
                if row.get("last_reminder_sent_date") == today_iso:
                    continue

                user_id = row["user_id"]
                top = await asyncio.to_thread(
                    lambda: self._db.rpc(
                        "top_mistake_categories",
                        {"p_user": user_id, "p_days": 7},
                    ).execute()
                )
                top_data = top.data or []
                if not top_data:
                    continue

                token_res = await asyncio.to_thread(
                    lambda: self._db.table("notification_tokens")
                        .select("token")
                        .eq("user_id", user_id)
                        .eq("is_active", True)
                        .limit(1)
                        .execute()
                )
                tokens = token_res.data or []
                if not tokens:
                    continue
                token = tokens[0]["token"]

                cats = ", ".join(_humanize(r["category"]) for r in top_data)
                body = f"Today's review: {cats}"
                msg = messaging.Message(
                    notification=messaging.Notification(
                        title="Bubbles", body=body,
                    ),
                    token=token,
                )
                await asyncio.to_thread(messaging.send, msg)
                await asyncio.to_thread(
                    lambda: self._db.table("user_settings")
                        .update({"last_reminder_sent_date": today_iso})
                        .eq("user_id", user_id)
                        .execute()
                )
                pushed += 1
            except Exception as e:
                print(f"⚠️  ReminderService row failed: {e}")
                err_str = str(e).lower()
                if "unregistered" in err_str or "not_found" in err_str:
                    try:
                        await asyncio.to_thread(
                            lambda: self._db.table("notification_tokens")
                                .update({"is_active": False})
                                .eq("user_id", row["user_id"])
                                .execute()
                        )
                    except Exception:
                        pass

        return pushed

    @staticmethod
    def _convert_tz(now_utc: dt.datetime, tz_name: str) -> dt.datetime:
        try:
            from zoneinfo import ZoneInfo
            return now_utc.astimezone(ZoneInfo(tz_name))
        except Exception:
            return now_utc
