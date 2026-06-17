# Purpose: OpenTelemetry trace span context propagation helpers for distributed request tracing.
"""OpenTelemetry setup.

OTLP/HTTP exporter to Grafana Tempo (or any OTLP collector). Auto-
instrumentation for FastAPI, asyncpg, httpx, redis happens lazily when those
modules are first imported.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from bubbles import __version__
from bubbles.settings import Settings

if TYPE_CHECKING:
    from fastapi import FastAPI

_configured = False


def configure_tracing(settings: Settings, *, service_name: str = "bubbles-api") -> None:
    """Idempotent. No-op when OTLP endpoint is unset."""
    global _configured
    if _configured or settings.otel_exporter_otlp_endpoint is None:
        return

    resource = Resource.create(
        {
            "service.name": service_name,
            "service.version": __version__,
            "deployment.environment": settings.app_env.value,
        }
    )
    provider = TracerProvider(resource=resource)
    exporter = OTLPSpanExporter(endpoint=str(settings.otel_exporter_otlp_endpoint))
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)
    _configured = True


def instrument_app(app: FastAPI) -> None:
    """Attach FastAPI instrumentation. Safe to call when tracing is disabled."""
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

    FastAPIInstrumentor.instrument_app(app)


def get_tracer(name: str) -> trace.Tracer:
    return trace.get_tracer(name)
