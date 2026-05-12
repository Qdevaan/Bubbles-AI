import pytest

from app.services.prompt_loader import render_persona_block, render_scenario_header


def _persona(role_family="educator"):
    return {
        "display_name": "Ada",
        "profession_detail": "physics teacher",
        "native_language": "en",
        "learning_language": "en",
        "formality_preference": "neutral",
        "communication_style": ["concise", "friendly"],
        "expertise_tags": ["physics", "education"],
        "avoid_list": "no slang",
        "role_family": role_family,
    }


@pytest.mark.parametrize("rf", ["educator", "learner", "professional", "casual", "default"])
def test_each_role_family_fragment_renders(rf):
    out = render_persona_block(_persona(role_family=rf))
    assert isinstance(out, str)
    assert len(out) > 20


def test_educator_fragment_mentions_pedagogical():
    out = render_persona_block(_persona(role_family="educator"))
    assert "pedagogical" in out.lower() or "educator" in out.lower()


def test_default_fragment_renders_for_unknown_role_family():
    p = _persona(role_family="weird_family")
    out = render_persona_block(p)
    assert "neutral" in out.lower() or len(out) > 20


def test_scenario_header_includes_scenario_and_role_mode():
    ctx = {"scenario": "lecture", "role_mode": "mentor", "notes": "thermo"}
    out = render_scenario_header(ctx)
    assert "lecture" in out
    assert "mentor" in out
    assert "thermo" in out


def test_scenario_header_empty_when_ctx_none():
    assert render_scenario_header(None).strip() == ""
