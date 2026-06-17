# Purpose: Loads and renders Jinja2 prompt templates from disk, injecting persona and session context variables.
"""Jinja2 template loader for prompts.

Templates live under ``src/bubbles/ai/prompts/`` so they ship with the
package. The loader auto-strips trailing whitespace and renders strict —
undefined variables raise.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any

from jinja2 import Environment, FileSystemLoader, StrictUndefined, select_autoescape

_PROMPTS_DIR = Path(__file__).parent


@lru_cache(maxsize=1)
def _env() -> Environment:
    return Environment(
        loader=FileSystemLoader(str(_PROMPTS_DIR)),
        undefined=StrictUndefined,
        autoescape=select_autoescape(default=False),
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=False,
    )


def render(template: str, **ctx: Any) -> str:
    """Render ``template`` (path relative to ``ai/prompts/``)."""
    return _env().get_template(template).render(**ctx).strip()


_ALLOWED_PERSONAS = {"casual", "default", "educator", "learner", "professional"}


def render_persona_block(persona: dict[str, Any]) -> str:
    family = persona.get("role_family") or "default"
    if family not in _ALLOWED_PERSONAS:
        family = "default"
    return render(f"personas/{family}.jinja", persona=persona)


def render_scenario_header(ctx: dict[str, Any] | None) -> str:
    if not ctx:
        return ""
    return render("personas/_scenario_header.jinja", ctx=ctx)
