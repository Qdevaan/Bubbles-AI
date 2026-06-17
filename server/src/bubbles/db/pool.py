# Purpose: Async SQLAlchemy engine and session-pool factory; configured via Settings for prod vs. test.
"""Async Postgres pool to Supabase via PgBouncer.

PgBouncer transaction mode requires:
- statement cache disabled
- prepared statements disabled (or using `__asyncpg_stmt_<id>__` rotation)

We disable both. asyncpg ≥ 0.30 honours ``statement_cache_size=0``.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import asyncpg

from bubbles.core.logging import get_logger
from bubbles.settings import Settings

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

log = get_logger(__name__)


async def create_pool(settings: Settings) -> asyncpg.Pool:
    dsn = settings.database_url.get_secret_value()
    pool = await asyncpg.create_pool(
        dsn=dsn,
        min_size=settings.db_pool_min,
        max_size=settings.db_pool_max,
        command_timeout=settings.db_command_timeout_s,
        statement_cache_size=0,  # PgBouncer transaction mode
        max_inactive_connection_lifetime=300,
    )
    if pool is None:  # pragma: no cover — asyncpg returns Pool | None
        raise RuntimeError("asyncpg.create_pool returned None")
    log.info("db_pool_created", min=settings.db_pool_min, max=settings.db_pool_max)
    return pool


async def ping(pool: asyncpg.Pool) -> bool:
    try:
        async with pool.acquire() as con:
            await con.execute("SELECT 1")
        return True
    except Exception as exc:
        log.warning("db_ping_failed", error=str(exc))
        return False


async def close_pool(pool: asyncpg.Pool) -> None:
    await pool.close()
    log.info("db_pool_closed")


async def acquire(pool: asyncpg.Pool) -> AsyncIterator[asyncpg.Connection]:
    """Reusable async generator for FastAPI dependencies."""
    async with pool.acquire() as con:
        yield con
