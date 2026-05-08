from unittest.mock import MagicMock, patch
from datetime import datetime

from fastapi.testclient import TestClient

from app.main import app
from app.utils.auth_guard import get_verified_user


def _override_user():
    return MagicMock(id="u1")


@patch("app.routes.persona.persona_svc")
def test_get_persona_returns_404_when_missing(mock_svc):
    mock_svc.get.return_value = None
    app.dependency_overrides[get_verified_user] = _override_user
    try:
        client = TestClient(app)
        headers = {"Authorization": "Bearer test-token"}
        with patch("app.utils.auth_guard.get_verified_user", return_value=MagicMock(id="u1")):
            r = client.get("/v1/me/persona", headers=headers)
        assert r.status_code == 404
    finally:
        app.dependency_overrides.pop(get_verified_user, None)


@patch("app.routes.persona.persona_svc")
def test_get_persona_returns_200_when_present(mock_svc):
    from app.models.persona import UserPersona
    mock_svc.get.return_value = UserPersona(
        user_id="00000000-0000-0000-0000-000000000001",
        role_primary="teacher",
        native_language="en",
        learning_language="en",
        role_family="educator",
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    app.dependency_overrides[get_verified_user] = _override_user
    try:
        client = TestClient(app)
        with patch("app.utils.auth_guard.get_verified_user", return_value=MagicMock(id="u1")):
            r = client.get("/v1/me/persona", headers={"Authorization": "Bearer t"})
        assert r.status_code == 200
        assert r.json()["role_family"] == "educator"
    finally:
        app.dependency_overrides.pop(get_verified_user, None)


@patch("app.routes.persona.persona_svc")
def test_put_persona_upserts_and_returns_persona(mock_svc):
    from app.models.persona import UserPersona
    mock_svc.upsert.return_value = UserPersona(
        user_id="00000000-0000-0000-0000-000000000001",
        role_primary="student",
        native_language="en",
        learning_language="en",
        role_family="learner",
        completed_at=datetime.utcnow(),
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    app.dependency_overrides[get_verified_user] = _override_user
    try:
        client = TestClient(app)
        payload = {
            "role_primary": "student",
            "native_language": "en",
            "learning_language": "en",
        }
        with patch("app.utils.auth_guard.get_verified_user", return_value=MagicMock(id="u1")):
            r = client.put("/v1/me/persona", json=payload,
                           headers={"Authorization": "Bearer t"})
        assert r.status_code == 200
        assert r.json()["role_family"] == "learner"
        mock_svc.invalidate.assert_called_once_with("u1")
    finally:
        app.dependency_overrides.pop(get_verified_user, None)


@patch("app.routes.persona.persona_svc")
def test_put_persona_rejects_invalid_role_primary(mock_svc):
    app.dependency_overrides[get_verified_user] = _override_user
    try:
        client = TestClient(app)
        with patch("app.utils.auth_guard.get_verified_user", return_value=MagicMock(id="u1")):
            r = client.put("/v1/me/persona", json={"role_primary": "wizard"},
                           headers={"Authorization": "Bearer t"})
        assert r.status_code == 422
    finally:
        app.dependency_overrides.pop(get_verified_user, None)
