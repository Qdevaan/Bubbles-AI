# Purpose: Project-wide exception hierarchy (BubblesError, UpstreamUnavailable, NotFound, ValidationError, etc.).
"""Typed errors + JSON envelope handlers.

Public envelope::

    {"error": {"code": "<machine_code>", "message": "<safe text>", "request_id": "..."}}

Never echo raw upstream messages — they may leak provider keys, SQL, or PII.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import ORJSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from bubbles.core.logging import current_request_id, get_logger

if TYPE_CHECKING:
    from collections.abc import Awaitable, Callable

log = get_logger(__name__)


class AppError(Exception):
    """Base class for typed application errors."""

    code: str = "internal_error"
    status_code: int = status.HTTP_500_INTERNAL_SERVER_ERROR
    public_message: str = "An unexpected error occurred."

    def __init__(self, message: str | None = None, **extra: Any) -> None:
        super().__init__(message or self.public_message)
        self.public_message = message or self.public_message
        self.extra = extra


class BadRequest(AppError):
    code = "bad_request"
    status_code = status.HTTP_400_BAD_REQUEST
    public_message = "Invalid request."


class Unauthorized(AppError):
    code = "unauthorized"
    status_code = status.HTTP_401_UNAUTHORIZED
    public_message = "Authentication required."


class Forbidden(AppError):
    code = "forbidden"
    status_code = status.HTTP_403_FORBIDDEN
    public_message = "Not allowed."


class NotFound(AppError):
    code = "not_found"
    status_code = status.HTTP_404_NOT_FOUND
    public_message = "Resource not found."


class Conflict(AppError):
    code = "conflict"
    status_code = status.HTTP_409_CONFLICT
    public_message = "Conflicting state."


class ValidationFailed(AppError):
    code = "validation_failed"
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    public_message = "Request validation failed."


class RateLimited(AppError):
    code = "rate_limited"
    status_code = status.HTTP_429_TOO_MANY_REQUESTS
    public_message = "Too many requests."

    def __init__(self, retry_after: int, **extra: Any) -> None:
        super().__init__(self.public_message, **extra)
        self.retry_after = retry_after


class UpstreamUnavailable(AppError):
    code = "upstream_unavailable"
    status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    public_message = "An upstream service is unavailable."


def _envelope(code: str, message: str, request_id: str | None) -> dict[str, dict[str, Any]]:
    return {"error": {"code": code, "message": message, "request_id": request_id}}


async def _app_error_handler(request: Request, exc: AppError) -> ORJSONResponse:
    rid = current_request_id()
    log.warning("app_error", code=exc.code, status=exc.status_code, message=str(exc))
    headers: dict[str, str] = {}
    if isinstance(exc, RateLimited):
        headers["Retry-After"] = str(exc.retry_after)
    return ORJSONResponse(
        _envelope(exc.code, exc.public_message, rid),
        status_code=exc.status_code,
        headers=headers,
    )


async def _validation_error_handler(
    request: Request, exc: RequestValidationError
) -> ORJSONResponse:
    rid = current_request_id()
    log.info("validation_error", errors=exc.errors())
    return ORJSONResponse(
        _envelope("validation_failed", "Request validation failed.", rid)
        | {"detail": exc.errors()},
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
    )


async def _http_exception_handler(request: Request, exc: StarletteHTTPException) -> ORJSONResponse:
    rid = current_request_id()
    code_map = {
        400: "bad_request",
        401: "unauthorized",
        403: "forbidden",
        404: "not_found",
        405: "method_not_allowed",
        409: "conflict",
        413: "payload_too_large",
        415: "unsupported_media_type",
        422: "validation_failed",
        429: "rate_limited",
        500: "internal_error",
        502: "bad_gateway",
        503: "upstream_unavailable",
        504: "gateway_timeout",
    }
    return ORJSONResponse(
        _envelope(code_map.get(exc.status_code, "http_error"), str(exc.detail), rid),
        status_code=exc.status_code,
        headers=exc.headers,
    )


async def _generic_handler(request: Request, exc: Exception) -> ORJSONResponse:
    rid = current_request_id()
    log.exception("unhandled_exception", exc_type=type(exc).__name__)
    return ORJSONResponse(
        _envelope("internal_error", "An unexpected error occurred.", rid),
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
    )


def register_error_handlers(app: FastAPI) -> None:
    # Starlette's add_exception_handler signature is wider than each handler's;
    # we group the registrations to keep call sites simple.
    handlers: list[tuple[type[Exception], Callable[[Request, Any], Awaitable[Any]]]] = [
        (AppError, _app_error_handler),
        (RequestValidationError, _validation_error_handler),
        (StarletteHTTPException, _http_exception_handler),
        (Exception, _generic_handler),
    ]
    for exc_class, handler in handlers:
        app.add_exception_handler(exc_class, handler)
