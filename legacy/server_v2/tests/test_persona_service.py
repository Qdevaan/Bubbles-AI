from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest

from app.services.persona_service import PersonaService
from app.models.persona import UserPersonaUpdate


@pytest.fixture
def fake_db():
    db = MagicMock()
    return db


@pytest.fixture
def svc(fake_db):
    return PersonaService(db=fake_db)


def _row(role_primary="teacher", completed=True):
    return {
        "user_id": "00000000-0000-0000-0000-000000000001",
        "display_name": "Ada",
        "role_primary": role_primary,
        "profession_detail": None,
        "expertise_tags": [],
        "native_language": "en",
        "learning_language": "en",
        "proficiency_self_rated": None,
        "formality_preference": "neutral",
        "communication_style": [],
        "primary_goals": [],
        "typical_scenarios": [],
        "cultural_context": None,
        "avoid_list": None,
        "age_range": None,
        "role_family": "educator",
        "completed_at": datetime.now(timezone.utc).isoformat() if completed else None,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


def test_get_returns_persona_when_row_exists(svc, fake_db):
    fake_db.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value.data = _row()
    p = svc.get("00000000-0000-0000-0000-000000000001")
    assert p is not None
    assert p.role_family == "educator"


def test_get_returns_none_when_missing(svc, fake_db):
    fake_db.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value.data = None
    p = svc.get("00000000-0000-0000-0000-000000000002")
    assert p is None


def test_upsert_computes_role_family_and_sets_completed_at(svc, fake_db):
    captured = {}
    def upsert_side_effect(payload):
        captured["payload"] = payload
        m = MagicMock()
        m.execute.return_value.data = [{**payload, **_row(role_primary=payload["role_primary"])}]
        return m
    fake_db.table.return_value.upsert.side_effect = upsert_side_effect
    fake_db.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value.data = None

    update = UserPersonaUpdate(
        role_primary="student",
        native_language="en",
        learning_language="en",
    )
    p = svc.upsert("00000000-0000-0000-0000-000000000001", update)
    assert captured["payload"]["role_family"] == "learner"
    assert captured["payload"]["completed_at"] is not None
    assert p.role_family == "learner"


def test_cache_hit_skips_db(svc, fake_db):
    fake_db.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value.data = _row()
    uid = "00000000-0000-0000-0000-000000000001"
    svc.get(uid)
    fake_db.table.reset_mock()
    svc.get(uid)
    fake_db.table.assert_not_called()


def test_invalidate_busts_cache(svc, fake_db):
    fake_db.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value.data = _row()
    uid = "00000000-0000-0000-0000-000000000001"
    svc.get(uid)
    svc.invalidate(uid)
    fake_db.table.reset_mock()
    fake_db.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value.data = _row()
    svc.get(uid)
    fake_db.table.assert_called()
