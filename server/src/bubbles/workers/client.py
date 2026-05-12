"""ARQ client for the API process.

The API enqueues background jobs but never runs them, so it only needs an
``ArqRedis`` connection — not the worker's job table or AI stack. This module
is deliberately import-light (no ``arq_settings`` import) to keep the API
process slim.
"""

from __future__ import annotations

from arq import create_pool
from arq.connections import ArqRedis, RedisSettings

from bubbles.settings import Settings


def _redis_settings(settings: Settings) -> RedisSettings:
    return RedisSettings.from_dsn(settings.redis_url.get_secret_value())


async def make_arq_pool(settings: Settings) -> ArqRedis:
    """Open an ARQ Redis pool. Caller owns it and must ``await pool.aclose()``."""
    return await create_pool(_redis_settings(settings))
