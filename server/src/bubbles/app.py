"""FastAPI application factory."""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.responses import ORJSONResponse
from starlette.middleware.cors import CORSMiddleware
from starlette.middleware.gzip import GZipMiddleware

from bubbles import __version__
from bubbles.api.health import router as health_router
from bubbles.api.metrics import MetricsMiddleware
from bubbles.api.metrics import router as metrics_router
from bubbles.api.middleware import (
    BodySizeLimitMiddleware,
    RequestContextMiddleware,
    SecurityHeadersMiddleware,
)
from bubbles.api.router import v1_router
from bubbles.core.errors import register_error_handlers
from bubbles.core.tracing import instrument_app
from bubbles.lifespan import lifespan
from bubbles.settings import AppEnv, Settings, get_settings


def _cors_origins(settings: Settings) -> list[str]:
    if settings.app_env is AppEnv.development:
        return ["*"]
    # Phase 8 will read an env-driven allowlist; default lock-down for now.
    return []


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build the FastAPI app for this process / test."""
    settings = settings or get_settings()

    app = FastAPI(
        title="Bubbles Brain API",
        version=__version__,
        default_response_class=ORJSONResponse,
        docs_url="/docs" if not settings.is_production else None,
        redoc_url=None,
        openapi_url="/openapi.json" if not settings.is_production else None,
        lifespan=lifespan,
    )

    # Order matters: outermost first.
    app.add_middleware(SecurityHeadersMiddleware)
    app.add_middleware(GZipMiddleware, minimum_size=1024)
    app.add_middleware(
        BodySizeLimitMiddleware,
        default_limit=settings.request_body_limit,
        audio_limit=settings.audio_body_limit,
    )
    app.add_middleware(RequestContextMiddleware)
    app.add_middleware(MetricsMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_cors_origins(settings),
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
        max_age=600,
    )

    register_error_handlers(app)

    app.include_router(health_router)
    app.include_router(metrics_router)
    app.include_router(v1_router)

    instrument_app(app)
    return app
