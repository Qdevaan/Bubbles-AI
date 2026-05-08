from datetime import datetime
import pytest
from pydantic import ValidationError

from app.models.persona import (
    UserPersona,
    UserPersonaUpdate,
    SessionContext,
)


def _base_payload():
    return {
        "user_id": "00000000-0000-0000-0000-000000000001",
        "role_primary": "teacher",
        "native_language": "en",
        "learning_language": "en",
        "role_family": "educator",
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow(),
    }


def test_user_persona_minimal_required_fields():
    p = UserPersona(**_base_payload())
    assert p.role_primary == "teacher"
    assert p.role_family == "educator"
    assert p.expertise_tags == []
    assert p.formality_preference == "neutral"


def test_user_persona_rejects_invalid_role_primary():
    bad = _base_payload()
    bad["role_primary"] = "wizard"
    with pytest.raises(ValidationError):
        UserPersona(**bad)


def test_user_persona_update_array_max_lengths():
    # expertise_tags max 5
    with pytest.raises(ValidationError):
        UserPersonaUpdate(expertise_tags=["a", "b", "c", "d", "e", "f"])
    # communication_style max 3
    with pytest.raises(ValidationError):
        UserPersonaUpdate(communication_style=["a", "b", "c", "d"])
    # primary_goals max 3
    with pytest.raises(ValidationError):
        UserPersonaUpdate(primary_goals=["a", "b", "c", "d"])
    # typical_scenarios max 4
    with pytest.raises(ValidationError):
        UserPersonaUpdate(typical_scenarios=["a", "b", "c", "d", "e"])


def test_session_context_required_scenario():
    ctx = SessionContext(
        scenario="lecture",
        role_mode="mentor",
        notes="intro to thermodynamics",
        set_at=datetime.utcnow(),
    )
    assert ctx.scenario == "lecture"
    with pytest.raises(ValidationError):
        SessionContext(scenario="invalid_scenario", set_at=datetime.utcnow())
