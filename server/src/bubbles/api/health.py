"""Health endpoints.

- ``/health/live`` — process is up. Always 200.
- ``/health/ready`` — DB + Redis + JWKS reachable. 200 or 503.
- ``/health/deep`` — auth-only; pings each LLM provider with a 1-token probe.
"""

from __future__ import annotations

from fastapi import APIRouter, Request, status
from fastapi.responses import ORJSONResponse

from bubbles import __version__
from bubbles.auth.current_user import CurrentUserDep
from bubbles.core.redis import ping as ping_redis
from bubbles.db.pool import ping as ping_db

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live")
async def live() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/ready")
async def ready(request: Request) -> ORJSONResponse:
    db_ok = await ping_db(request.app.state.db)
    redis_ok = await ping_redis(request.app.state.redis)
    ok = db_ok and redis_ok
    return ORJSONResponse(
        {
            "status": "ok" if ok else "degraded",
            "version": __version__,
            "db": db_ok,
            "redis": redis_ok,
        },
        status_code=status.HTTP_200_OK if ok else status.HTTP_503_SERVICE_UNAVAILABLE,
    )


@router.get("/deep")
async def deep(user: CurrentUserDep) -> dict[str, object]:
    """Auth-gated. Phase 3 fills in provider probes."""
    return {"status": "ok", "user": user.id, "providers": {}}
