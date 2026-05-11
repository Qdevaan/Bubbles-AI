"""Phase 0/1 smoke: liveness endpoint is reachable without lifespan deps."""

from __future__ import annotations

from httpx import AsyncClient


async def test_live_returns_ok(client: AsyncClient) -> None:
    resp = await client.get("/health/live")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


async def test_request_id_header_set(client: AsyncClient) -> None:
    resp = await client.get("/health/live")
    assert "x-request-id" in {k.lower() for k in resp.headers}


async def test_security_headers_set(client: AsyncClient) -> None:
    resp = await client.get("/health/live")
    assert resp.headers["x-content-type-options"] == "nosniff"
    assert resp.headers["x-frame-options"] == "DENY"
