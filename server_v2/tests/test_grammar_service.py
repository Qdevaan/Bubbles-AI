import pytest
from unittest.mock import AsyncMock, MagicMock, patch


@pytest.mark.asyncio
async def test_uses_embedded_when_no_url(monkeypatch):
    from app.services.grammar_service import GrammarService
    monkeypatch.setattr(
        "app.services.grammar_service.settings.LANGUAGETOOL_URL", None,
    )
    gs = GrammarService()

    fake_match = MagicMock()
    fake_match.ruleId = "EN_AGREEMENT_1"
    fake_match.category = "GRAMMAR"
    fake_match.matchedText = "don't goes"
    fake_match.replacements = ["doesn't go"]

    fake_lt = MagicMock()
    fake_lt.check.return_value = [fake_match]
    gs._embedded = fake_lt

    out = await gs.check("she don't goes")
    assert len(out) == 1
    assert out[0]["rule_id"] == "EN_AGREEMENT_1"
    assert out[0]["source"] == "lt"


@pytest.mark.asyncio
async def test_uses_http_when_url_set(monkeypatch):
    from app.services.grammar_service import GrammarService
    monkeypatch.setattr(
        "app.services.grammar_service.settings.LANGUAGETOOL_URL",
        "https://api.languagetool.org/v2/check",
    )
    gs = GrammarService()

    fake_resp_data = {
        "matches": [{
            "rule": {"id": "EN_GRAMMAR_1", "category": {"id": "GRAMMAR"}},
            "context": {"text": "don't goes", "offset": 0, "length": 10},
            "replacements": [{"value": "doesn't go"}],
            "message": "subj/verb",
        }]
    }

    class _Resp:
        status_code = 200

        def json(self):
            return fake_resp_data

    with patch("httpx.AsyncClient") as MockClient:
        instance = MockClient.return_value.__aenter__.return_value
        instance.post = AsyncMock(return_value=_Resp())
        out = await gs.check("she don't goes")

    assert len(out) == 1
    assert out[0]["rule_id"] == "EN_GRAMMAR_1"


@pytest.mark.asyncio
async def test_http_failure_returns_empty(monkeypatch):
    from app.services.grammar_service import GrammarService
    monkeypatch.setattr(
        "app.services.grammar_service.settings.LANGUAGETOOL_URL",
        "https://api.languagetool.org/v2/check",
    )
    gs = GrammarService()

    with patch("httpx.AsyncClient") as MockClient:
        instance = MockClient.return_value.__aenter__.return_value
        instance.post = AsyncMock(side_effect=Exception("boom"))
        out = await gs.check("hi")
    assert out == []


def test_category_mapping():
    from app.services.grammar_service import _map_lt_category
    assert _map_lt_category("GRAMMAR") == "grammar"
    assert _map_lt_category("STYLE") == "style"
    assert _map_lt_category("PUNCTUATION") == "grammar"
    assert _map_lt_category("agreement") == "agreement"
    assert _map_lt_category("UNKNOWN_THING") == "grammar"
