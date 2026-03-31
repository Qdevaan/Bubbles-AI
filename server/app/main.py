"""
Bubbles Brain API — FastAPI entry point.
Mounts all routers, configures CORS, rate-limiting, and background tasks.

CHANGES:
  - Background cleanup now uses session_store (Redis or in-memory) instead of
    direct dict access on the sessions module.
  - JWT auth applied globally to all /v1/ routes via dependency injection on
    individual endpoints (not middleware, to allow public health check).
"""

import asyncio
from datetime import datetime, timedelta

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.config import settings
from app.utils.rate_limit import limiter
from app.utils.session_store import session_store

from app.routes import health, sessions, consultant, voice, analytics, entities

# ── FastAPI App ───────────────────────────────────────────────────────────────

app = FastAPI(
    title="Bubbles Brain API",
    description="Backend API for the Bubbles conversation assistant",
    version="3.0.0",
)

# Rate limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS
_allowed_origins = (
    [o.strip() for o in settings.ALLOWED_ORIGINS.split(",")]
    if settings.ALLOWED_ORIGINS != "*"
    else ["*"]
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Mount Routers ─────────────────────────────────────────────────────────────

# Health & root (no prefix, no auth — public endpoint)
app.include_router(health.router)

# All business endpoints under /v1/ (auth is applied per-endpoint via Depends)
from fastapi import APIRouter

v1 = APIRouter(prefix="/v1")
v1.include_router(sessions.router)
v1.include_router(consultant.router)
v1.include_router(voice.router)
v1.include_router(analytics.router)
v1.include_router(entities.router)

app.include_router(v1)


# ── Background Cleanup ───────────────────────────────────────────────────────

_SESSION_TTL_HOURS = 6

async def _cleanup_stale_sessions():
    """Every 30 min, purge sessions older than TTL from session store."""
    while True:
        await asyncio.sleep(30 * 60)
        try:
            cutoff = datetime.now() - timedelta(hours=_SESSION_TTL_HOURS)
            evicted = await session_store.evict_stale(cutoff)
            if evicted:
                print(f"🧹 TTL cleanup: removed {evicted} stale session(s)")
        except Exception as e:
            print(f"❌ Cleanup task error: {e}")


@app.on_event("startup")
async def _startup():
    asyncio.create_task(_cleanup_stale_sessions())
    # Initialize session store (triggers Redis connection if REDIS_URL is set)
    await session_store.evict_stale(datetime.now())  # no-op but warms connection
    auth_mode = "DEBUG (no JWT)" if settings.DEBUG_SKIP_AUTH else "JWT Verified"
    store_mode = "Redis" if settings.REDIS_URL else "In-Memory"
    print(f"🚀 Bubbles Brain API v3.0 — Ready")
    print(f"   Auth: {auth_mode}  |  Session Store: {store_mode}")


# ── Direct Execution ──────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=True,
    )
