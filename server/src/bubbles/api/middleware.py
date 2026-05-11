"""Request middleware: id, timing, body-size cap, security headers."""

from __future__ import annotations

import time
from collections.abc import Awaitable, Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from starlette.types import ASGIApp

from bubbles.core.ids import new_id
from bubbles.core.logging import bind_request, get_logger, unbind_request

log = get_logger(__name__)

_AUDIO_PATHS = ("/v1/process_audio", "/v1/enroll", "/v1/identify_speaker", "/v1/tts")


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Assigns a request-id, logs request/response, exposes ``X-Request-ID``."""

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        rid = request.headers.get("x-request-id") or new_id()
        bind_request(request_id=rid)
        start = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            elapsed_ms = (time.perf_counter() - start) * 1000
            log.exception(
                "request_failed",
                method=request.method,
                path=request.url.path,
                elapsed_ms=round(elapsed_ms, 2),
            )
            raise
        else:
            elapsed_ms = (time.perf_counter() - start) * 1000
            response.headers["X-Request-ID"] = rid
            log.info(
                "request",
                method=request.method,
                path=request.url.path,
                status=response.status_code,
                elapsed_ms=round(elapsed_ms, 2),
            )
            return response
        finally:
            unbind_request()


class BodySizeLimitMiddleware(BaseHTTPMiddleware):
    """Enforce body-size caps. Audio routes get a higher cap.

    Uses Content-Length header — clients without it pass through; the route
    handler still bounds chunks via ``request.stream`` if needed.
    """

    def __init__(
        self,
        app: ASGIApp,
        *,
        default_limit: int,
        audio_limit: int,
    ) -> None:
        super().__init__(app)
        self.default_limit = default_limit
        self.audio_limit = audio_limit

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        cl = request.headers.get("content-length")
        if cl is not None:
            try:
                size = int(cl)
            except ValueError:
                size = 0
            limit = self.audio_limit if request.url.path in _AUDIO_PATHS else self.default_limit
            if size > limit:
                from bubbles.core.errors import BadRequest

                raise BadRequest(f"Request body exceeds {limit} bytes.")
        return await call_next(request)


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Conservative defaults — TLS layer adds HSTS at the proxy."""

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault(
            "Permissions-Policy",
            "geolocation=(), microphone=(), camera=()",
        )
        return response
