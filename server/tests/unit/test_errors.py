"""Error handlers and envelope shape."""

from __future__ import annotations

from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.core.errors import (
    BadRequest,
    NotFound,
    RateLimited,
    UpstreamUnavailable,
    register_error_handlers,
)


def _build() -> FastAPI:
    app = FastAPI()
    register_error_handlers(app)

    @app.get("/bad")
    async def _bad() -> None:
        raise BadRequest("nope")

    @app.get("/missing")
    async def _missing() -> None:
        raise NotFound()

    @app.get("/limited")
    async def _limited() -> None:
        raise RateLimited(retry_after=7)

    @app.get("/upstream")
    async def _upstream() -> None:
        raise UpstreamUnavailable()

    @app.get("/boom")
    async def _boom() -> None:
        raise RuntimeError("kaboom")

    return app


async def test_envelope_shape() -> None:
    transport = ASGITransport(app=_build())
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        r = await ac.get("/bad")
        assert r.status_code == 400
        body = r.json()
        assert body["error"]["code"] == "bad_request"
        assert body["error"]["message"] == "nope"


async def test_rate_limited_sets_retry_after() -> None:
    transport = ASGITransport(app=_build())
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        r = await ac.get("/limited")
        assert r.status_code == 429
        assert r.headers["retry-after"] == "7"


async def test_unhandled_becomes_internal() -> None:
    # raise_app_exceptions=False so the test transport returns the 500
    # response built by our handler instead of re-raising.
    transport = ASGITransport(app=_build(), raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        r = await ac.get("/boom")
        assert r.status_code == 500
        body = r.json()
        assert body["error"]["code"] == "internal_error"
        assert "kaboom" not in body["error"]["message"]


async def test_upstream_status() -> None:
    transport = ASGITransport(app=_build())
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        r = await ac.get("/upstream")
        assert r.status_code == 503


async def test_not_found_default_message() -> None:
    transport = ASGITransport(app=_build())
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        r = await ac.get("/missing")
        assert r.status_code == 404
        assert r.json()["error"]["code"] == "not_found"
