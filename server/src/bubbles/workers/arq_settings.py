# Purpose: ARQ worker configuration: Redis DSN, job timeout, max retry, and the full job function list.
"""ARQ worker configuration.

Defines the ``WorkerSettings`` ARQ loads on ``arq bubbles.workers.arq_settings.WorkerSettings``.
The worker shares the same persistence stack as the API but loads it from the
same ``Settings`` instance so credentials / model choices stay in one place.
"""

from __future__ import annotations

import json
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
    backfill_session_entities,
    compute_embeddings,
    compute_session_analytics,
    detect_achievements,
    extract_knowledge,
    generate_scenarios,
    grammar_scan,
    materialize_drill_cards,
    rolling_summarize,
    score_scenario,
    seed_quests,
    send_reminders,
    sentiment_scan,
    speaker_enroll,
    speaker_identify,
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
#
# Every job module exposes ``run``; ARQ identifies functions by name, so we
# can't register all the ``run``s directly (they'd collide). Instead a single
# dispatcher named ``run`` is registered and routes on the ``_job_name`` kwarg
# the ``workers.enqueue`` helpers pass. Cron jobs use their own wrappers below.

_JOB_REGISTRY: dict[str, Any] = {
    "backfill_session_entities": backfill_session_entities.run,
    "compute_embeddings": compute_embeddings.run,
    "compute_session_analytics": compute_session_analytics.run,
    "detect_achievements": detect_achievements.run,
    "extract_knowledge": extract_knowledge.run,
    "generate_scenarios": generate_scenarios.run,
    "grammar_scan": grammar_scan.run,
    "materialize_drill_cards": materialize_drill_cards.run,
    "rolling_summarize": rolling_summarize.run,
    "score_scenario": score_scenario.run,
    "sentiment_scan": sentiment_scan.run,
    "speaker_enroll": speaker_enroll.run,
    "speaker_identify": speaker_identify.run,
}


MAX_TRIES = 5
# Redis list jobs land in after exhausting MAX_TRIES — a dead-letter queue an
# operator (or the API's /metrics, which exposes its length) can watch.
DEAD_LETTER_KEY = "arq:dead_letter"
_DEAD_LETTER_MAX = 1000


async def _dead_letter(
    ctx: dict[str, Any], *, job_name: str, kwargs: dict[str, Any], error: str
) -> None:
    redis = ctx.get("redis_aux")
    if redis is None:
        return
    payload = json.dumps(
        {
            "job_name": job_name,
            "kwargs": {k: str(v)[:500] for k, v in kwargs.items()},
            "error": error[:1000],
            "failed_at": datetime.now(tz=UTC).isoformat(),
        }
    )
    try:
        await redis.rpush(DEAD_LETTER_KEY, payload)
        await redis.ltrim(DEAD_LETTER_KEY, -_DEAD_LETTER_MAX, -1)
    except Exception as exc:
        log.warning("dead_letter_write_failed", error=str(exc))


async def run(ctx: dict[str, Any], *, _job_name: str, **kwargs: Any) -> Any:
    """Dispatch an enqueued job to its handler by name; dead-letter on final failure."""
    handler = _JOB_REGISTRY.get(_job_name)
    if handler is None:
        raise ValueError(f"unknown job: {_job_name!r}")
    try:
        return await handler(ctx, **kwargs)
    except Exception as exc:
        if int(ctx.get("job_try", 1) or 1) >= MAX_TRIES:
            log.error("job_dead_lettered", job_name=_job_name, error=str(exc))
            await _dead_letter(ctx, job_name=_job_name, kwargs=kwargs, error=str(exc))
        raise


functions = [run]


# --- cron entries ----------------------------------------------------------


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
    max_tries = MAX_TRIES
    job_timeout = 60
    keep_result = 600
    health_check_interval = 30

    @staticmethod
    def redis_settings() -> RedisSettings:
        return _redis_settings(get_settings())
