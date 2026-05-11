import json
import pytest
from unittest.mock import AsyncMock, MagicMock


@pytest.mark.asyncio
async def test_returns_categorized_issues():
    from app.services.brain_service import BrainService
    bs = BrainService()
    fake = MagicMock()
    fake.choices = [MagicMock()]
    fake.choices[0].message.content = json.dumps({
        "issues": [
            {"category": "filler", "snippet": "um", "suggestion": ""},
            {"category": "awkward", "snippet": "I do go was",
             "suggestion": "I went"},
        ]
    })
    bs.aclient.chat.completions.create = AsyncMock(return_value=fake)

    out = await bs.check_filler_awkward("um I do go was yesterday")
    assert len(out["issues"]) == 2
    assert out["issues"][0]["category"] == "filler"


@pytest.mark.asyncio
async def test_malformed_returns_empty():
    from app.services.brain_service import BrainService
    bs = BrainService()
    fake = MagicMock()
    fake.choices = [MagicMock()]
    fake.choices[0].message.content = "not json"
    bs.aclient.chat.completions.create = AsyncMock(return_value=fake)

    out = await bs.check_filler_awkward("hi")
    assert out["issues"] == []


@pytest.mark.asyncio
async def test_filters_unknown_categories():
    from app.services.brain_service import BrainService
    bs = BrainService()
    fake = MagicMock()
    fake.choices = [MagicMock()]
    fake.choices[0].message.content = json.dumps({
        "issues": [
            {"category": "filler", "snippet": "um"},
            {"category": "wizard", "snippet": "x"},
        ]
    })
    bs.aclient.chat.completions.create = AsyncMock(return_value=fake)

    out = await bs.check_filler_awkward("hi")
    assert len(out["issues"]) == 1
    assert out["issues"][0]["category"] == "filler"
