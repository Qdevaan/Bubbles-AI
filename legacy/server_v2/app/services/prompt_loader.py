# Purpose: Loads Jinja2 prompt templates from disk and renders persona and scenario context blocks.
"""Jinja env + render helpers for persona prompt fragments."""

from pathlib import Path
from typing import Optional

from jinja2 import Environment, FileSystemLoader, select_autoescape


_PROMPTS_DIR = Path(__file__).resolve().parent.parent / "prompts"

_env = Environment(
    loader=FileSystemLoader(str(_PROMPTS_DIR)),
    autoescape=select_autoescape(disabled_extensions=("jinja",), default=False),
    trim_blocks=True,
    lstrip_blocks=True,
)

_VALID_FAMILIES = {"educator", "learner", "professional", "casual", "default"}


def render_persona_block(persona: dict) -> str:
    family = persona.get("role_family", "default")
    if family not in _VALID_FAMILIES:
        family = "default"
    template = _env.get_template(f"personas/{family}.jinja")
    return template.render(persona=persona)


def render_scenario_header(ctx: Optional[dict]) -> str:
    template = _env.get_template("personas/_scenario_header.jinja")
    return template.render(ctx=ctx)
