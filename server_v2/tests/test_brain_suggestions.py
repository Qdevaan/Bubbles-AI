import pytest
import json
from unittest.mock import AsyncMock, MagicMock


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
