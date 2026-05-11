"""Prompt template loader tests."""

from __future__ import annotations

import pytest
from jinja2 import UndefinedError

from bubbles.ai.prompts.loader import render, render_persona_block


def _full_persona(**over: object) -> dict[str, object]:
    base: dict[str, object] = {
        "display_name": "x",
        "age_range": "25-34",
        "role_primary": "manager",
        "role_family": "default",
        "profession_detail": None,
        "expertise_tags": [],
        "native_language": "en",
        "learning_language": "en",
        "proficiency_self_rated": "intermediate",
        "formality_preference": "neutral",
        "communication_style": [],
        "primary_goals": [],
        "typical_scenarios": [],
        "cultural_context": None,
        "avoid_list": None,
    }
    base.update(over)
    return base


def test_persona_block_falls_back_to_default() -> None:
    out = render_persona_block(_full_persona(role_family="alien"))
    assert out  # something rendered


def test_persona_block_uses_known_family() -> None:
    out = render_persona_block(
        _full_persona(
            role_family="professional",
            display_name="Mx. M",
            expertise_tags=["tech"],
            primary_goals=["clarity"],
            communication_style=["concise"],
            typical_scenarios=["standups"],
        )
    )
    assert "professional" in out.lower() or "manager" in out.lower()


def test_render_strict_undefined() -> None:
    with pytest.raises(UndefinedError):
        render("wingman/title.jinja")  # missing transcript var


def test_render_extract_entities_template() -> None:
    out = render("wingman/extract_entities.jinja", transcript="Alice met Bob.")
    assert "Alice met Bob" in out
    assert "JSON" in out
