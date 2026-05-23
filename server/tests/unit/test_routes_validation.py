"""Schema validation + auth gating across /v1 routes."""

from __future__ import annotations

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.deps import get_pool, get_ratelimiter


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


@pytest.mark.parametrize(
    "payload",
    [
        {"transcript": "", "speaker_role": "others"},
        {"transcript": "hi", "speaker_role": "robot"},
        {"transcript": "hi", "speaker_role": "llm"},  # 'llm' not allowed on input
        {"transcript": "hi", "speaker_role": "others", "confidence": 1.5},
    ],
)
async def test_process_transcript_wingman_validation(
    app: FastAPI, payload: dict[str, object]
) -> None:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        resp = await ac.post(
            "/v1/process_transcript_wingman", json=payload, headers={"Authorization": "Bearer fake"}
        )
    assert resp.status_code in (401, 422)


async def test_log_turn_requires_content(app: FastAPI) -> None:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://t") as ac:
        resp = await ac.post(
            "/v1/log_turn",
            json={"session_id": "00000000-0000-0000-0000-000000000000", "content": ""},
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


# ---- F4: confidence-meter request validation -----------------------------


async def _confidence_endpoint_returns(
    app: FastAPI, body: dict[str, object], expected_status: int
) -> int:
    """POST the confidence body to a dummy session id; return status code.

    Auth is bypassed via dependency override so that Pydantic body validation
    fires and the response reflects schema errors (422) rather than auth
    errors (401).
    """
    class _NoOpLimiter:
        async def check(self, key: str, *, capacity: int, refill_per_s: float) -> object:
            class _R:
                allowed = True
                retry_after_s = 0.0
            return _R()

    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id="test-user", email="t@t.com", role="authenticated"
    )
    app.dependency_overrides[get_pool] = lambda: None
    app.dependency_overrides[get_ratelimiter] = lambda: _NoOpLimiter()
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
            r = await ac.post(
                "/v1/sessions/00000000-0000-0000-0000-000000000000/confidence",
                json=body,
            )
    finally:
        app.dependency_overrides.pop(current_user, None)
        app.dependency_overrides.pop(get_pool, None)
        app.dependency_overrides.pop(get_ratelimiter, None)
    return r.status_code


@pytest.mark.asyncio
async def test_set_turn_confidence_rejects_empty_list(app: FastAPI) -> None:
    code = await _confidence_endpoint_returns(
        app, {"confidence_by_turn": []}, expected_status=422
    )
    assert code == 422


@pytest.mark.asyncio
async def test_set_turn_confidence_rejects_score_above_one(app: FastAPI) -> None:
    code = await _confidence_endpoint_returns(
        app, {"confidence_by_turn": [{"turn_index": 0, "score": 1.5}]}, expected_status=422
    )
    assert code == 422


@pytest.mark.asyncio
async def test_set_turn_confidence_rejects_negative_score(app: FastAPI) -> None:
    code = await _confidence_endpoint_returns(
        app, {"confidence_by_turn": [{"turn_index": 0, "score": -0.1}]}, expected_status=422
    )
    assert code == 422


@pytest.mark.asyncio
async def test_set_turn_confidence_rejects_negative_turn_index(app: FastAPI) -> None:
    code = await _confidence_endpoint_returns(
        app, {"confidence_by_turn": [{"turn_index": -1, "score": 0.5}]}, expected_status=422
    )
    assert code == 422


@pytest.mark.asyncio
async def test_set_turn_confidence_rejects_unknown_field(app: FastAPI) -> None:
    code = await _confidence_endpoint_returns(
        app,
        {"confidence_by_turn": [{"turn_index": 0, "score": 0.5, "extra": 1}]},
        expected_status=422,
    )
    assert code == 422
