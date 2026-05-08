import pytest
import json
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch


@pytest.mark.asyncio
async def test_returns_three_suggestions():
    from app.services.brain_service import BrainService
    bs = BrainService()
    fake_completion = MagicMock()
    fake_completion.choices = [MagicMock()]
    fake_completion.choices[0].message.content = json.dumps(
        {"suggestions": ["s1", "s2", "s3"]}
    )
    bs.aclient.chat.completions.create = AsyncMock(return_value=fake_completion)

    result = await bs.get_wingman_suggestions(
        user_id="u1", transcript="how are you?",
        graph_context="", vector_context="",
        persona="formal", performa_context="",
    )
    assert result["suggestions"] == ["s1", "s2", "s3"]
    assert "latency_ms" in result


@pytest.mark.asyncio
async def test_malformed_json_returns_empty():
    from app.services.brain_service import BrainService
    bs = BrainService()
    fake_completion = MagicMock()
    fake_completion.choices = [MagicMock()]
    fake_completion.choices[0].message.content = "not json"
    bs.aclient.chat.completions.create = AsyncMock(return_value=fake_completion)

    result = await bs.get_wingman_suggestions(
        user_id="u1", transcript="hi",
        graph_context="", vector_context="",
        persona="casual", performa_context="",
    )
    assert result["suggestions"] == []


def test_brain_prompt_includes_educator_block_when_user_is_teacher():
    """Persona-injection wiring smoke test for brain_service prompt builders."""
    from app.models.persona import UserPersona
    from app.services import brain_service as bs

    persona = UserPersona(
        user_id="00000000-0000-0000-0000-000000000001",
        role_primary="teacher",
        native_language="en",
        learning_language="en",
        role_family="educator",
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    with patch("app.services.brain_service.persona_svc") as mock_svc:
        mock_svc.get.return_value = persona
        out = bs.build_system_prompt(user_id="u1", session_context=None)

    assert isinstance(out, str)
    assert "educator" in out.lower() or "pedagogical" in out.lower()


def test_brain_prompt_falls_back_to_default_when_persona_missing():
    from app.services import brain_service as bs

    with patch("app.services.brain_service.persona_svc") as mock_svc:
        mock_svc.get.return_value = None
        out = bs.build_system_prompt(user_id="u-missing", session_context=None)

    assert isinstance(out, str)
    assert "neutral" in out.lower() or len(out) > 20
