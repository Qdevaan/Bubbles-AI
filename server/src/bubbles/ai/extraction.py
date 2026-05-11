"""Structured-output extraction tasks."""

from __future__ import annotations

import json
from typing import Any

from bubbles.ai.prompts.loader import render
from bubbles.ai.providers.base import ChatMessage, Role
from bubbles.ai.router import LLMRouter
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger

log = get_logger(__name__)

_MAX_TRANSCRIPT_CHARS = 4000


def _truncate(transcript: str) -> str:
    if len(transcript) <= _MAX_TRANSCRIPT_CHARS:
        return transcript
    return transcript[-_MAX_TRANSCRIPT_CHARS:]


def _parse_json(text: str) -> dict[str, Any]:
    try:
        decoded = json.loads(text)
    except json.JSONDecodeError as exc:
        raise UpstreamUnavailable(f"non-JSON extraction output: {exc!s}") from exc
    if not isinstance(decoded, dict):
        raise UpstreamUnavailable("extraction output was not a JSON object")
    return decoded


async def _wingman_json(router: LLMRouter, prompt: str) -> dict[str, Any]:
    completion = await router.complete(
        "wingman.json",
        [ChatMessage(role=Role.user, content=prompt)],
        response_format="json",
    )
    return _parse_json(completion.text)


async def extract_entities(router: LLMRouter, transcript: str) -> dict[str, Any]:
    prompt = render("wingman/extract_entities.jinja", transcript=_truncate(transcript))
    return await _wingman_json(router, prompt)


async def extract_highlights(router: LLMRouter, transcript: str) -> dict[str, Any]:
    prompt = render("wingman/highlights.jinja", transcript=_truncate(transcript))
    return await _wingman_json(router, prompt)


async def generate_title(router: LLMRouter, transcript: str) -> str:
    prompt = render("wingman/title.jinja", transcript=_truncate(transcript))
    data = await _wingman_json(router, prompt)
    title = data.get("title")
    return title if isinstance(title, str) else ""


async def generate_summary(router: LLMRouter, transcript: str) -> str:
    prompt = render("wingman/summary.jinja", transcript=_truncate(transcript))
    data = await _wingman_json(router, prompt)
    summary = data.get("summary")
    return summary if isinstance(summary, str) else ""


async def correct_grammar(router: LLMRouter, snippet: str) -> dict[str, Any]:
    prompt = render("wingman/grammar_correct.jinja", snippet=snippet)
    return await _wingman_json(router, prompt)
