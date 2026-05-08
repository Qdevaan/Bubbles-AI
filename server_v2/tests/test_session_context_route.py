from unittest.mock import MagicMock, patch
from datetime import datetime
from fastapi.testclient import TestClient

from app.main import app
from app.utils.auth_guard import get_verified_user


def _override_user(uid="u1"):
    return MagicMock(id=uid)


def test_post_session_context_writes_jsonb_for_owned_session():
    client = TestClient(app)
    payload = {
        "scenario": "lecture",
        "role_mode": "mentor",
        "notes": "intro to thermo",
        "set_at": datetime.utcnow().isoformat(),
    }
    app.dependency_overrides[get_verified_user] = lambda: _override_user("u1")
    try:
        with patch("app.routes.sessions._set_session_context") as mock_set:
            mock_set.return_value = True
            r = client.post(
                "/v1/sessions/sess-123/context",
                json=payload,
                headers={"Authorization": "Bearer t"},
            )
        assert r.status_code == 200
        mock_set.assert_called_once()
    finally:
        app.dependency_overrides.pop(get_verified_user, None)


def test_post_session_context_rejects_invalid_scenario():
    client = TestClient(app)
    payload = {
        "scenario": "tea_party",
        "set_at": datetime.utcnow().isoformat(),
    }
    app.dependency_overrides[get_verified_user] = lambda: _override_user("u1")
    try:
        r = client.post(
            "/v1/sessions/sess-123/context",
            json=payload,
            headers={"Authorization": "Bearer t"},
        )
        assert r.status_code == 422
    finally:
        app.dependency_overrides.pop(get_verified_user, None)


def test_post_session_context_returns_403_when_not_owner():
    client = TestClient(app)
    payload = {
        "scenario": "lecture",
        "set_at": datetime.utcnow().isoformat(),
    }
    app.dependency_overrides[get_verified_user] = lambda: _override_user("u1")
    try:
        with patch("app.routes.sessions._set_session_context") as mock_set:
            mock_set.return_value = False  # RLS denied
            r = client.post(
                "/v1/sessions/foreign-sess/context",
                json=payload,
                headers={"Authorization": "Bearer t"},
            )
        assert r.status_code == 403
    finally:
        app.dependency_overrides.pop(get_verified_user, None)
