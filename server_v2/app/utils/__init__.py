"""
Shared utilities — fire_and_forget helper lives here to avoid circular imports
with main.py (routes import it, main.py also imports routes).
"""

import asyncio
from typing import Coroutine

# Tracked background task set — drained on graceful shutdown
_background_tasks: set = set()


def fire_and_forget(coro: Coroutine) -> asyncio.Task:
    """
    Schedule a coroutine as a tracked background task.
    Suppresses all exceptions (prints a warning on failure).
    Use instead of bare asyncio.create_task() for non-critical work
    (gamification XP, quest progress, streak updates) so they drain
    cleanly on server shutdown.
    """
    async def _safe():
        try:
            await coro
        except Exception as e:
            print(f"⚠️ fire_and_forget error: {e}")

    task = asyncio.create_task(_safe())
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)
    return task
