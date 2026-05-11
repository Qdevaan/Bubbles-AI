"""FastAPI dependency providers.

All long-lived resources (DB pool, Redis, AI router, embeddings) are stored
on ``app.state`` by the lifespan and exposed here as ``Depends`` injectables.

If a resource is missing (lifespan not run, infra wiped) we raise
``UpstreamUnavailable`` so the client sees a 503 with ``Retry-After`` instead
of a 500 that leaks internals.
"""

from __future__ import annotations

from typing import Annotated, TypeVar

import asyncpg
import redis.asyncio as redis_async
from fastapi import Depends, Request

from bubbles.ai.embeddings import EmbeddingService
from bubbles.ai.router import LLMRouter
from bubbles.core.cache import Cache
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.ratelimit import RateLimiter

_T = TypeVar("_T")


def _require(request: Request, attr: str, label: str, _typ: type[_T]) -> _T:
    value: _T | None = getattr(request.app.state, attr, None)
    if value is None:
        raise UpstreamUnavailable(f"{label} is not ready")
    return value


def get_pool(request: Request) -> asyncpg.Pool:
    return _require(request, "db", "database", asyncpg.Pool)


def get_redis(request: Request) -> redis_async.Redis:
    return _require(request, "redis", "redis", redis_async.Redis)


def get_cache(request: Request) -> Cache:
    return _require(request, "cache", "cache", Cache)


def get_ratelimiter(request: Request) -> RateLimiter:
    return _require(request, "ratelimit", "rate limiter", RateLimiter)


def get_router(request: Request) -> LLMRouter:
    return _require(request, "router", "LLM router", LLMRouter)


def get_embeddings(request: Request) -> EmbeddingService:
    return _require(request, "embeddings", "embedding service", EmbeddingService)


PoolDep = Annotated[asyncpg.Pool, Depends(get_pool)]
RedisDep = Annotated[redis_async.Redis, Depends(get_redis)]
CacheDep = Annotated[Cache, Depends(get_cache)]
RateLimiterDep = Annotated[RateLimiter, Depends(get_ratelimiter)]
RouterDep = Annotated[LLMRouter, Depends(get_router)]
EmbeddingsDep = Annotated[EmbeddingService, Depends(get_embeddings)]
