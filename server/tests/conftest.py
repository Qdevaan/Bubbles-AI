"""Shared pytest fixtures."""

from __future__ import annotations

from collections.abc import AsyncIterator, Iterator
from pathlib import Path

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

# Set required env vars before any bubbles import resolves them.
_TEST_ENV: dict[str, str] = {
    "APP_ENV": "development",
    "SUPABASE_URL": "https://example.supabase.co",
    "SUPABASE_SERVICE_KEY": "test-service-key",
    "SUPABASE_JWKS_URL": "https://example.supabase.co/auth/v1/keys",
    "DATABASE_URL": "postgresql://user:pass@localhost:6543/postgres?pgbouncer=true",
    "REDIS_URL": "redis://localhost:6379/0",
}


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    for key, val in _TEST_ENV.items():
        monkeypatch.setenv(key, val)
    for stray in ("DEBUG_SKIP_AUTH", "SENTRY_DSN", "OTEL_EXPORTER_OTLP_ENDPOINT"):
        monkeypatch.delenv(stray, raising=False)
    from bubbles.settings import get_settings

    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture
def app() -> FastAPI:
    from bubbles.app import create_app

    return create_app()


@pytest.fixture
async def client(app: FastAPI) -> AsyncIterator[AsyncClient]:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.fixture
def project_root() -> Path:
    return Path(__file__).resolve().parent.parent
