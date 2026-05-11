"""ID helpers.

ULIDs everywhere. Lex-sortable, time-ordered, 128 bit, base32.
"""

from __future__ import annotations

from uuid import UUID

import ulid


def new_id() -> str:
    """New ULID string (26 chars, lex-sortable by time)."""
    return ulid.new().str


def new_uuid() -> str:
    """New UUID4 string for legacy schemas that demand UUIDs."""
    return str(UUID(bytes=ulid.new().bytes))


def is_ulid(value: str) -> bool:
    if not isinstance(value, str) or len(value) != 26:
        return False
    try:
        ulid.from_str(value)
    except (ValueError, TypeError):
        return False
    return True
