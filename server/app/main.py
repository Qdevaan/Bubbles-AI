"""
Bubbles Brain API — FastAPI entry point.
Mounts all routers, configures CORS, rate-limiting, and background tasks.
"""

import asyncio
from datetime import datetime, timedelta

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.config import settings
from app.utils.rate_limit import limiter

from app.routes import health, sessions, consultant, voice, analytics, entities

# ── FastAPI App ───────────────────────────────────────────────────────────────

app = FastAPI(
    title="Bubbles Brain API",
    description="Backend API for the Bubbles conversation assistant",
    version="2.0.0",
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
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Mount Routers ─────────────────────────────────────────────────────────────

# Health & root (no prefix)
app.include_router(health.router)

# All business endpoints under /v1/
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
    """Every 30 min, purge sessions older than TTL from in-memory state."""
    while True:
        await asyncio.sleep(30 * 60)
        cutoff = datetime.now() - timedelta(hours=_SESSION_TTL_HOURS)
        stale = [
            sid
            for sid, ts in sessions.SESSION_TIMESTAMPS.items()
            if ts < cutoff
        ]
        for sid in stale:
            sessions.SESSION_TIMESTAMPS.pop(sid, None)
            sessions.TURN_COUNTERS.pop(sid, None)
            sessions.SESSION_METADATA.pop(sid, None)
            for k, v in list(sessions.LIVE_SESSIONS.items()):
                if v == sid:
                    del sessions.LIVE_SESSIONS[k]
        if stale:
            print(f"🧹 TTL cleanup: removed {len(stale)} stale session(s)")


@app.on_event("startup")
async def _start_cleanup_task():
    asyncio.create_task(_cleanup_stale_sessions())
    print("🚀 Bubbles Brain API v2.0 — Ready")


# ── Direct Execution ──────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=True,
    )
