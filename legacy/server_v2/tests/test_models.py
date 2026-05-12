import pytest
from pydantic import ValidationError
from app.models.requests import SuggestReplyRequest, SuggestReplyResponse


def test_request_accepts_valid_tone():
    req = SuggestReplyRequest(
        user_id="u1", session_id="s1",
        partner_utterance="hello", tone="formal", is_draft=False,
    )
    assert req.tone == "formal"


def test_request_rejects_bad_tone():
    with pytest.raises(ValidationError):
        SuggestReplyRequest(
            user_id="u1", session_id="s1",
            partner_utterance="hi", tone="rude",
        )


def test_response_round_trip():
    r = SuggestReplyResponse(
        suggestions=["a", "b", "c"], kind="final",
        latency_ms=320, request_id="r1",
    )
    assert r.kind == "final"
    assert len(r.suggestions) == 3
