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

# How much transcript we feed an extraction prompt verbatim. Longer transcripts
# are condensed segment-by-segment (map-reduce) so the *whole* conversation is
# represented — not just the tail, which is what the old hard-truncate-to-4 KB
# did (it dropped every conversation's opening, skewing talk-time %, topics and
# tone in the coaching report). Call ``prepare_transcript`` once per worker job
# and pass the result to the extraction functions below.
_TRANSCRIPT_BUDGET_CHARS = 32_000
_CONDENSE_CHUNK_CHARS = 16_000
_SEGMENT_FALLBACK_CHARS = 2_000


def _split_on_line_boundaries(text: str, max_chars: int) -> list[str]:
    chunks: list[str] = []
    current: list[str] = []
    current_len = 0
    for line in text.splitlines(keepends=True):
        if current and current_len + len(line) > max_chars:
            chunks.append("".join(current))
            current, current_len = [], 0
        current.append(line)
        current_len += len(line)
    if current:
        chunks.append("".join(current))
    return chunks


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


async def _condense_segment(router: LLMRouter, segment: str) -> str:
    prompt = render("wingman/condense_segment.jinja", segment=segment)
    try:
        data = await _wingman_json(router, prompt)
    except UpstreamUnavailable:
        return segment[:_SEGMENT_FALLBACK_CHARS]
    summary = data.get("summary")
    if isinstance(summary, str) and summary.strip():
        return summary.strip()
    return segment[:_SEGMENT_FALLBACK_CHARS]


_MAX_CONDENSE_PASSES = 3


async def prepare_transcript(router: LLMRouter, transcript: str, *, _pass: int = 0) -> str:
    """Return a transcript that fits the extraction budget.

    Short transcripts pass through unchanged. Long ones are split on line
    boundaries, each segment condensed by the LLM (``[Segment N] …``), and the
    join re-condensed (up to ``_MAX_CONDENSE_PASSES`` times) if still over
    budget — finally hard-clipped only if a single un-splittable segment is
    still too long or the pass cap is hit. Best-effort: a failed segment falls
    back to its (clipped) raw text.
    """
    if len(transcript) <= _TRANSCRIPT_BUDGET_CHARS:
        return transcript
    chunks = _split_on_line_boundaries(transcript, _CONDENSE_CHUNK_CHARS)
    if len(chunks) <= 1 or _pass >= _MAX_CONDENSE_PASSES:
        return transcript[-_TRANSCRIPT_BUDGET_CHARS:]
    condensed_parts = [
        f"[Segment {i}] {await _condense_segment(router, chunk)}"
        for i, chunk in enumerate(chunks, start=1)
    ]
    condensed = "\n\n".join(condensed_parts)
    if len(condensed) > _TRANSCRIPT_BUDGET_CHARS:
        return await prepare_transcript(router, condensed, _pass=_pass + 1)
    return condensed


async def extract_entities(router: LLMRouter, transcript: str) -> dict[str, Any]:
    prompt = render("wingman/extract_entities.jinja", transcript=transcript)
    return await _wingman_json(router, prompt)


async def extract_highlights(router: LLMRouter, transcript: str) -> dict[str, Any]:
    prompt = render("wingman/highlights.jinja", transcript=transcript)
    return await _wingman_json(router, prompt)


async def generate_title(router: LLMRouter, transcript: str) -> str:
    prompt = render("wingman/title.jinja", transcript=transcript)
    data = await _wingman_json(router, prompt)
    title = data.get("title")
    return title if isinstance(title, str) else ""


async def generate_summary(router: LLMRouter, transcript: str) -> str:
    prompt = render("wingman/summary.jinja", transcript=transcript)
    data = await _wingman_json(router, prompt)
    summary = data.get("summary")
    return summary if isinstance(summary, str) else ""


async def correct_grammar(router: LLMRouter, snippet: str) -> dict[str, Any]:
    prompt = render("wingman/grammar_correct.jinja", snippet=snippet)
    return await _wingman_json(router, prompt)


async def generate_coaching_report(router: LLMRouter, transcript: str) -> dict[str, Any]:
    prompt = render("coaching/report.jinja", transcript=transcript)
    completion = await router.complete(
        "analytics.coaching",
        [ChatMessage(role=Role.user, content=prompt)],
        response_format="json",
    )
    return _parse_json(completion.text)
