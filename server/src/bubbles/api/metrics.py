# Purpose: Exposes Prometheus-format metrics at GET /metrics for scraping by the observability stack.
"""``/metrics`` endpoint with basic-auth gate.

Cardinality safety: we label by ``method`` and ``route.path`` (the path
template, not the resolved URL) so unbounded user IDs never become labels.
"""

from __future__ import annotations

import secrets
import time
from collections.abc import Awaitable, Callable

from fastapi import APIRouter, HTTPException, Request, Response, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from starlette.middleware.base import BaseHTTPMiddleware

from bubbles.core import metrics as m
from bubbles.core.logging import get_logger
from bubbles.settings import Settings, get_settings

router = APIRouter(tags=["ops"])
log = get_logger(__name__)

_security = HTTPBasic(auto_error=False)
# Mirrors workers.arq_settings.DEAD_LETTER_KEY (kept here to avoid importing the
# worker module — and its AI stack — into the API process).
_ARQ_DEAD_LETTER_KEY = "arq:dead_letter"


def _check_metrics_auth(creds: HTTPBasicCredentials | None, settings: Settings) -> None:
    """Compare basic-auth creds in constant time.

    Defaults: user ``metrics``, password = first 32 chars of the supabase
    service key. Override via ``METRICS_PASSWORD`` env when settings grows it.
    """
    expected_user = "metrics"
    expected_password = settings.supabase_service_key.get_secret_value()[:32]
    if creds is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="metrics auth required",
            headers={"WWW-Authenticate": "Basic"},
        )
    user_ok = secrets.compare_digest(creds.username, expected_user)
    pwd_ok = secrets.compare_digest(creds.password, expected_password)
    if not (user_ok and pwd_ok):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid metrics credentials",
            headers={"WWW-Authenticate": "Basic"},
        )


@router.get("/metrics")
async def metrics_endpoint(request: Request) -> Response:
    settings = get_settings()
    creds_obj = await _security(request)
    _check_metrics_auth(creds_obj, settings)

    pool = getattr(request.app.state, "db", None)
    if pool is not None:
        try:
            in_use = pool.get_size() - pool.get_idle_size()
            m.db_pool_in_use.set(max(in_use, 0))
            m.db_pool_size.set(pool.get_max_size())
        except Exception as exc:
            log.warning("metrics_pool_probe_failed", error=str(exc))

    redis = getattr(request.app.state, "redis", None)
    if redis is not None:
        try:
            m.arq_dead_letter_queue_size.set(int(await redis.llen(_ARQ_DEAD_LETTER_KEY)))
        except Exception as exc:
            log.warning("metrics_dlq_probe_failed", error=str(exc))

    body, content_type = m.render()
    return Response(content=body, media_type=content_type)


class MetricsMiddleware(BaseHTTPMiddleware):
    """Record request count + latency keyed by route template (low cardinality)."""

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        start = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            elapsed = time.perf_counter() - start
            route_path = _route_template(request)
            m.http_requests_total.labels(request.method, route_path, "500").inc()
            m.http_request_duration_seconds.labels(request.method, route_path).observe(elapsed)
            raise
        elapsed = time.perf_counter() - start
        route_path = _route_template(request)
        m.http_requests_total.labels(request.method, route_path, str(response.status_code)).inc()
        m.http_request_duration_seconds.labels(request.method, route_path).observe(elapsed)
        return response


def _route_template(request: Request) -> str:
    route = request.scope.get("route")
    if route is not None and hasattr(route, "path"):
        return str(route.path)
    return request.url.path
