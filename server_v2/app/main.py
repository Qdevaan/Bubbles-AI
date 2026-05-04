"""
Bubbles Brain API v4 — FastAPI entry point.

Changes from v3:
  - Uses lifespan() context manager instead of deprecated @app.on_event("startup").
  - fire_and_forget() lives in app.utils to avoid circular imports.
  - gamification.router mounted under /v1.
  - Global exception handlers for consistent ErrorResponse format.
  - LiveKit env vars set in lifespan (moved from config.py side-effects).
"""

import asyncio
import os
import socket
from contextlib import asynccontextmanager
from datetime import datetime, timedelta

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.config import settings
from app.utils import _background_tasks
from app.utils.rate_limit import limiter
from app.utils.session_store import session_store

from app.routes import health, sessions, consultant, voice, analytics, entities, gamification, stt, performance


# ── Session TTL ───────────────────────────────────────────────────────────────
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


async def _self_ping():
    """Every 14 min, ping own /health to prevent cold-start sleep on Render/Railway.
    No-op when SELF_URL is empty (EC2 / Oracle Cloud deployments)."""
    if not settings.SELF_URL:
        return
    import httpx
    while True:
        await asyncio.sleep(14 * 60)
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.get(f"{settings.SELF_URL}/health")
                print(f"🏓 Self-ping: {r.status_code}")
        except Exception as e:
            print(f"⚠️  Self-ping failed: {e}")


# ── Lifespan ──────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    # === Startup ===
    # Expose LiveKit env vars so SDK picks them up automatically
    os.environ["LIVEKIT_URL"] = settings.LIVEKIT_URL
    os.environ["LIVEKIT_API_KEY"] = settings.LIVEKIT_API_KEY
    os.environ["LIVEKIT_API_SECRET"] = settings.LIVEKIT_API_SECRET

    # Warm up session store (triggers Redis connection if configured)
    await session_store.evict_stale(datetime.now())

    # Ensure quest_definitions table has default daily quest seeds.
    # This is idempotent — it only inserts if the table is empty.
    try:
        from app.services import gamification_svc
        await gamification_svc.seed_quest_definitions()
        print("🎯 Quest definitions seeded (or already present)")
    except Exception as _seed_err:
        print(f"⚠️  Quest seeding failed: {_seed_err}")

    # Start background stale-session cleanup task
    cleanup_task = asyncio.create_task(_cleanup_stale_sessions())
    ping_task = asyncio.create_task(_self_ping())

    auth_mode = "DEBUG (no JWT)" if settings.DEBUG_SKIP_AUTH else "JWT Verified"
    store_mode = "Redis" if settings.REDIS_URL else "In-Memory"

    # Detect the host machine's LAN IP for physical device connections
    try:
        _sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        _sock.connect(("8.8.8.8", 80))
        _lan_ip = _sock.getsockname()[0]
        _sock.close()
    except Exception:
        _lan_ip = "unknown"

    print(f"🚀 Bubbles Brain API v4.0 — Ready")
    print(f"   Auth: {auth_mode}  |  Session Store: {store_mode}  |  Env: {settings.APP_ENV}")
    print(f"")
    print(f"   ┌─────────────────────────────────────────────────────────┐")
    print(f"   │  Local:         http://localhost:8000                   │")
    print(f"   │  Docs:          http://localhost:8000/docs              │")
    print(f"   │  Health:        http://localhost:8000/health            │")
    print(f"   │  Android (LAN): http://{_lan_ip}:8000          │")
    print(f"   └─────────────────────────────────────────────────────────┘")
    print(f"")

    public_url = None
    if settings.NGROK_AUTHTOKEN:
        try:
            from pyngrok import ngrok
            ngrok.set_auth_token(settings.NGROK_AUTHTOKEN)
            public_url = ngrok.connect(settings.PORT).public_url
            print(f"   🚀 ngrok Public URL: {public_url}")
            print(f"")
        except Exception as e:
            print(f"   ⚠️ ngrok failed to start: {e}")
            print(f"")

    yield  # Server is running

    # === Shutdown: drain tracked background tasks (XP, quests, streaks) ===
    cleanup_task.cancel()
    ping_task.cancel()
    if _background_tasks:
        print(f"⏳ Draining {len(_background_tasks)} background task(s)...")
        done, pending = await asyncio.wait(_background_tasks, timeout=10)
        if pending:
            print(f"⚠️  {len(pending)} background task(s) did not complete in time")
            
    if public_url:
        try:
            from pyngrok import ngrok
            ngrok.disconnect(public_url)
        except Exception:
            pass
            
    print("👋 Server shut down cleanly")


# ── FastAPI App ───────────────────────────────────────────────────────────────

app = FastAPI(
    title="Bubbles Brain API",
    description="Backend API for the Bubbles AI conversation assistant",
    version="4.0.0",
    lifespan=lifespan,
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


# ── Global Exception Handlers ─────────────────────────────────────────────────

@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=400,
        content={
            "error": "validation_error",
            "message": "Invalid request parameters",
            "details": {"errors": exc.errors()},
            "request_id": request.headers.get("X-Request-ID"),
        },
    )


@app.exception_handler(Exception)
async def generic_error_handler(request: Request, exc: Exception):
    # Don't swallow HTTP exceptions — let FastAPI's default handler deal with them
    from fastapi import HTTPException
    if isinstance(exc, HTTPException):
        raise exc
    print(f"❌ Unhandled exception on {request.url.path}: {exc}")
    return JSONResponse(
        status_code=500,
        content={
            "error": "internal_error",
            "message": "An unexpected server error occurred.",
            "request_id": request.headers.get("X-Request-ID"),
        },
    )


# ── Mount Routers ─────────────────────────────────────────────────────────────

# Health & root — no prefix, no auth
app.include_router(health.router)

# All business endpoints under /v1/
from fastapi import APIRouter

v1 = APIRouter(prefix="/v1")
v1.include_router(sessions.router)
v1.include_router(consultant.router)
v1.include_router(voice.router)
v1.include_router(analytics.router)
v1.include_router(entities.router)
v1.include_router(gamification.router)
v1.include_router(stt.router)
v1.include_router(performance.router)

app.include_router(v1)


# ── Direct Execution ──────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=True,
    )
