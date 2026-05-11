"""
Input sanitization — strips prompt-injection patterns and caps input length.
"""

import re

# Patterns that attempt to override system-level LLM instructions
_INJECTION_PATTERNS = re.compile(
    r"(?i)"
    r"(?:ignore\s+(?:all\s+)?(?:previous|above|prior)\s+instructions)"
    r"|(?:you\s+are\s+now\s+(?:a|an|the)\b)"
    r"|(?:system\s*:\s*)"
    r"|(?:assistant\s*:\s*)"
    r"|(?:\[INST\])"
    r"|(?:\[/INST\])"
    r"|(?:<\|im_start\|>)"
    r"|(?:<\|im_end\|>)"
    r"|(?:###\s*(?:System|Human|Assistant))"
)


def sanitize_input(text: str, max_length: int = 5000) -> str:
    """Strip prompt-injection patterns and cap length to prevent abuse."""
    if not text:
        return ""
    text = text[:max_length]
    text = _INJECTION_PATTERNS.sub("[filtered]", text)
    return text.strip()
