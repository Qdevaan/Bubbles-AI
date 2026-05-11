"""ARQ worker configuration.

Defines the ``WorkerSettings`` ARQ loads on ``arq bubbles.workers.arq_settings.WorkerSettings``.
The worker shares the same persistence stack as the API but loads it from the
same ``Settings`` instance so credentials / model choices stay in one place.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

import asyncpg
from arq.connections import RedisSettings
from arq.cron import cron

from bubbles.ai.wiring import AIStack, build_ai_stack
from bubbles.core.cache import Cache
from bubbles.core.logging import configure_logging, get_logger
from bubbles.core.redis import make_redis
from bubbles.db.pool import close_pool, create_pool
from bubbles.settings import Settings, get_settings
from bubbles.workers.jobs import (
    compute_embeddings,
    compute_session_analytics,
    extract_knowledge,
    grammar_scan,
    seed_quests,
    send_reminders,
    speaker_enroll,
)

log = get_logger(__name__)


@dataclass(slots=True)
class WorkerCtx:
    settings: Settings
    pool: asyncpg.Pool
    cache: Cache
    ai: AIStack


def _redis_settings(settings: Settings) -> RedisSettings:
    url = settings.redis_url.get_secret_value()
    return RedisSettings.from_dsn(url)


async def _on_startup(ctx: dict[str, Any]) -> None:
    settings = get_settings()
    configure_logging(settings)
    log.info("worker_starting", env=settings.app_env.value)
    redis_client = make_redis(settings)
    cache = Cache(redis_client)
    pool = await create_pool(settings)
    ai = build_ai_stack(settings, cache)
    ctx["bubbles"] = WorkerCtx(settings=settings, pool=pool, cache=cache, ai=ai)
    ctx["redis_aux"] = redis_client
    log.info("worker_started")


async def _on_shutdown(ctx: dict[str, Any]) -> None:
    log.info("worker_stopping")
    bub: WorkerCtx | None = ctx.get("bubbles")
    if bub is not None:
        await bub.ai.http_client.aclose()
        await close_pool(bub.pool)
    redis_aux = ctx.get("redis_aux")
    if redis_aux is not None:
        await redis_aux.aclose()
    log.info("worker_stopped")


# --- registered functions --------------------------------------------------

functions = [
    compute_embeddings.run,
    extract_knowledge.run,
    compute_session_analytics.run,
    grammar_scan.run,
    send_reminders.run,
    speaker_enroll.run,
    seed_quests.run,
]


# --- cron entries ----------------------------------------------------------


def _at(hour: int, minute: int, fn: Any, *, run_at_startup: bool = False) -> Any:
    return cron(fn, hour={hour}, minute={minute}, run_at_startup=run_at_startup)


async def _wrap_seed_quests(ctx: dict[str, Any]) -> None:
    await seed_quests.run(ctx)


async def _wrap_send_reminders(ctx: dict[str, Any]) -> None:
    await send_reminders.run(ctx, before_utc=datetime.now(tz=UTC))


cron_jobs = [
    cron(_wrap_seed_quests, hour={0}, minute={5}, run_at_startup=True),
    # 19:00 UTC daily reminder dispatch
    cron(_wrap_send_reminders, hour={19}, minute={0}),
]


class WorkerSettings:
    functions = functions
    cron_jobs = cron_jobs
    on_startup = _on_startup
    on_shutdown = _on_shutdown
    max_jobs = 10
    job_timeout = 60
    keep_result = 600
    health_check_interval = 30

    @staticmethod
    def redis_settings() -> RedisSettings:
        return _redis_settings(get_settings())
