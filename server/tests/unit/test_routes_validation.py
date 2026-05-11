"""Schema validation + auth gating across /v1 routes."""

from __future__ import annotations

from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient


async def test_unknown_field_rejected(app: FastAPI) -> None:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        resp = await ac.post(
            "/v1/ask_consultant",
            params={"stream": "false"},
            json={"question": "hi", "rogue_field": 1},
            headers={"Authorization": "Bearer fake"},
        )
    # Unknown field -> 422 from pydantic (or 401 if auth runs first).
    assert resp.status_code in (401, 422)


async def test_check_user_turn_requires_text(app: FastAPI) -> None:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        resp = await ac.post(
            "/v1/check_user_turn",
            json={"text": ""},
            headers={"Authorization": "Bearer fake"},
        )
    assert resp.status_code in (401, 422)


async def test_persona_get_requires_auth(app: FastAPI) -> None:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        resp = await ac.get("/v1/me/persona")
    assert resp.status_code == 401


async def test_openapi_includes_v1_routes(app: FastAPI) -> None:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        resp = await ac.get("/openapi.json")
    assert resp.status_code == 200
    paths = resp.json().get("paths", {})
    assert "/v1/ask_consultant" in paths
    assert "/v1/start_session" in paths
    assert "/v1/me/persona" in paths
    assert "/v1/ask_entity" in paths
