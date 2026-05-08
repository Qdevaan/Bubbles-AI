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


def test_grammar_prompt_includes_persona_role_family():
    from datetime import datetime, timezone

    from app.services.grammar_service import GrammarService
    from app.models.persona import UserPersona

    persona = UserPersona(
        user_id="00000000-0000-0000-0000-000000000001",
        role_primary="teacher",
        native_language="en",
        learning_language="en",
        role_family="educator",
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )

    svc = GrammarService()
    with patch("app.services.grammar_service.persona_svc") as mock_svc:
        mock_svc.get.return_value = persona
        prompt = svc.build_check_prompt(
            user_id="u1", text="he go to school", session_context=None,
        )

    assert "educator" in prompt.lower() or "pedagogical" in prompt.lower()
    assert "he go to school" in prompt
