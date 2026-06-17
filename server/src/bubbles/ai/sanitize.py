# Purpose: Strips AI self-disclosure phrases ("as an AI...") and normalises LLM output before returning it to the client.
"""Post-LLM text sanitisers used by the wingman advice loop.

Roleplay output sometimes leaks the model's AI self-disclosure ("as an
AI…"). Legacy ``server_v2`` stripped those phrases before returning the
advice; we do the same here so the wingman never breaks character.
"""

from __future__ import annotations

import re

_AI_DISCLAIMER_PATTERNS = re.compile(
    r"\b(as an ai|as a language model|as an ai assistant|"
    r"i am an ai|i'm an ai|i am a language model|"
    r"as an artificial intelligence|as a large language model)\b[^.!?]*[.!?]?",
    re.IGNORECASE,
)


def sanitize_ai_disclaimer(text: str, *, is_roleplay: bool) -> str:
    """Strip AI self-disclosure sentences from ``text`` when in roleplay mode."""
    if not is_roleplay:
        return text
    return _AI_DISCLAIMER_PATTERNS.sub("", text).strip()
