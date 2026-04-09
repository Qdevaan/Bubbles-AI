"""
Input validation helpers — defense-in-depth beyond Pydantic field constraints.
These are plain functions, not FastAPI dependencies. Call them at the top of
route handlers before passing data to services.
"""

import unicodedata
from typing import List, Any

# ── Limits ────────────────────────────────────────────────────────────────────
MAX_TRANSCRIPT_LENGTH = 50_000   # ~12,500 words
MAX_BATCH_LOGS = 500             # Max turns in save_session.logs[]
MAX_BATCH_QUESTIONS = 20         # Max questions in ask_consultant/batch


def normalize_text(text: str) -> str:
    """NFC-normalize unicode input for consistent entity matching."""
    return unicodedata.normalize("NFC", text.strip())


def validate_transcript(transcript: str) -> str:
    """
    Normalize and truncate transcript input.
    Returns the sanitized string (never raises — truncation is silent).
    """
    normalized = normalize_text(transcript)
    if len(normalized) > MAX_TRANSCRIPT_LENGTH:
        normalized = normalized[:MAX_TRANSCRIPT_LENGTH]
    return normalized


def validate_batch_logs(logs: List[Any]) -> List[Any]:
    """
    Cap batch log size to prevent oversized save_session payloads.
    Returns at most MAX_BATCH_LOGS entries.
    """
    return logs[:MAX_BATCH_LOGS]


def validate_batch_questions(questions: List[str]) -> List[str]:
    """
    Cap batch consultant questions.
    Raises ValueError if the list is empty.
    """
    if not questions:
        raise ValueError("questions list must not be empty")
    return questions[:MAX_BATCH_QUESTIONS]
