# Purpose: Background job that dispatches push notifications for streak reminders and upcoming quest deadlines.
"""Daily reminder dispatch.

Selects users whose reminder hour matches the current UTC hour and whose
``last_reminder_sent_date`` is not today, then writes a notification row.
Push delivery via FCM is queued downstream by another job to keep this one
DB-only and easy to test.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from bubbles.core.logging import get_logger
from bubbles.db.uow import UnitOfWork

log = get_logger(__name__)


async def run(ctx: dict[str, Any], *, before_utc: datetime) -> int:
    bub = ctx["bubbles"]
    sent = 0
    async with UnitOfWork(bub.pool) as uow:
        rows = await uow.conn.fetch(
            """
            SELECT user_id
            FROM user_settings
            WHERE reminder_hour = $1
              AND (last_reminder_sent_date IS NULL OR last_reminder_sent_date < CURRENT_DATE)
            LIMIT 1000
            """,
            before_utc.hour,
        )
        for row in rows:
            await uow.conn.execute(
                """
                INSERT INTO notifications (user_id, title, body, notif_type)
                VALUES ($1, $2, $3, 'reminder')
                """,
                row["user_id"],
                "Daily Bubbles practice",
                "Take a few minutes to reflect or chat.",
            )
            await uow.conn.execute(
                """
                UPDATE user_settings
                SET last_reminder_sent_date = CURRENT_DATE
                WHERE user_id = $1
                """,
                row["user_id"],
            )
            sent += 1
    log.info("send_reminders_done", sent=sent)
    return sent
