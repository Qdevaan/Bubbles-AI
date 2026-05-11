"""/metrics endpoint + auth gate."""

from __future__ import annotations

import base64

from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient


async def test_metrics_requires_basic_auth(app: FastAPI) -> None:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        resp = await ac.get("/metrics")
    assert resp.status_code == 401
    assert "WWW-Authenticate" in resp.headers


async def test_metrics_returns_prometheus_text(app: FastAPI) -> None:
    # Test password is first 32 chars of "test-service-key" → "test-service-key" (16 chars)
    creds = base64.b64encode(b"metrics:test-service-key").decode()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        resp = await ac.get("/metrics", headers={"Authorization": f"Basic {creds}"})
    assert resp.status_code == 200
    body = resp.text
    assert "bubbles_http_requests_total" in body
    assert "bubbles_llm_calls_total" in body


async def test_metrics_records_request_counts(app: FastAPI) -> None:
    creds = base64.b64encode(b"metrics:test-service-key").decode()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        await ac.get("/health/live")
        resp = await ac.get("/metrics", headers={"Authorization": f"Basic {creds}"})
    body = resp.text
    assert 'route="/health/live"' in body
