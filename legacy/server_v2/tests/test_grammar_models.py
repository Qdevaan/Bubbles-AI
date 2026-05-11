import pytest
from pydantic import ValidationError
from app.models.requests import (
    CheckUserTurnRequest, CheckUserTurnResponse, MistakeOut,
)


def test_request_accepts_minimal():
    r = CheckUserTurnRequest(
        user_id="u1", session_id="s1", transcript="she don't goes",
    )
    assert r.language == "en-US"


def test_response_round_trip():
    item = MistakeOut(
        id="m1", category="grammar", snippet="don't goes",
        suggestion="doesn't go", rule_id="LT_1", source="lt",
    )
    r = CheckUserTurnResponse(
        count=1, by_category={"grammar": 1}, items=[item], latency_ms=400,
    )
    assert r.count == 1
    assert r.items[0].category == "grammar"


def test_rejects_unknown_category():
    with pytest.raises(ValidationError):
        MistakeOut(
            id="m1", category="banana", snippet="x", rule_id="r", source="lt",
        )


def test_rejects_unknown_source():
    with pytest.raises(ValidationError):
        MistakeOut(
            id="m1", category="grammar", snippet="x", rule_id="r", source="abc",
        )
