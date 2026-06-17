# Purpose: Module: lifespan.
"""Application lifespan.

Startup order:
    1. Logging (sync, no IO).
    2. Tracing (sync, no IO).
    3. Settings validated (already by Settings()).
    4. Redis client + ping (warn-only on fail).
    5. DB pool + ping (warn-only on fail).
    6. JWKS cache warmed (best effort).

Shutdown reverses, with a timeout to drain background work.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import TYPE_CHECKING

from bubbles.ai.wiring import AIStack, build_ai_stack
from bubbles.auth.jwt import JWKSCache, warm_jwks
from bubbles.core.cache import Cache
from bubbles.core.concurrency import FireAndForget
from bubbles.core.logging import configure_logging, get_logger
from bubbles.core.logtail import attach_if_configured as attach_logtail
from bubbles.core.ratelimit import RateLimiter
from bubbles.core.redis import make_redis
from bubbles.core.redis import ping as ping_redis
from bubbles.core.sentry import configure_sentry
from bubbles.core.tracing import configure_tracing
from bubbles.db.pool import close_pool, create_pool
from bubbles.db.pool import ping as ping_db
from bubbles.settings import Settings, get_settings
from bubbles.workers.client import make_arq_pool

if TYPE_CHECKING:
    from fastapi import FastAPI

log = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings: Settings = get_settings()
    configure_logging(settings)
    attach_logtail(
        settings.logtail_source_token.get_secret_value()
        if settings.logtail_source_token is not None
        else None
    )
    configure_sentry(settings)
    configure_tracing(settings)
    log.info("lifespan_starting", env=settings.app_env.value)

    redis_client = make_redis(settings)
    app.state.redis = redis_client
    redis_ok = await ping_redis(redis_client)
    log.info("redis_ready", ok=redis_ok)

    cache = Cache(redis_client)
    app.state.cache = cache
    app.state.ratelimit = RateLimiter(redis_client)

    pool = await create_pool(settings)
    app.state.db = pool
    db_ok = await ping_db(pool)
    log.info("db_ready", ok=db_ok)

    try:
        app.state.arq = await make_arq_pool(settings)
        log.info("arq_ready", ok=True)
    except Exception as exc:
        app.state.arq = None
        log.warning("arq_unavailable", error=str(exc))

    jwks = JWKSCache(str(settings.supabase_jwks_url))
    app.state.jwks = jwks
    await warm_jwks(jwks)

    ai: AIStack = build_ai_stack(settings, cache)
    app.state.ai = ai
    app.state.router = ai.router
    app.state.embeddings = ai.embeddings

    app.state.bg = FireAndForget()

    log.info("lifespan_started")
    try:
        yield
    finally:
        log.info("lifespan_stopping")
        bg: FireAndForget | None = getattr(app.state, "bg", None)
        if bg is not None:
            await bg.drain(timeout_s=10.0)
        arq_pool = getattr(app.state, "arq", None)
        if arq_pool is not None:
            await arq_pool.aclose()
        await ai.http_client.aclose()
        await close_pool(pool)
        await redis_client.aclose()
        log.info("lifespan_stopped")
