import pytest
from unittest.mock import AsyncMock, MagicMock
from fastapi.testclient import TestClient


@pytest.fixture
def mock_brain_svc(mocker):
    mock = MagicMock()
    mock.get_wingman_suggestions = AsyncMock(
        return_value={
            "suggestions": ["Reply 1", "Reply 2", "Reply 3"],
            "latency_ms": 320,
        }
    )
    mocker.patch("app.services.brain_svc", mock)
    return mock


@pytest.fixture
def client():
    from app.main import app
    return TestClient(app)
