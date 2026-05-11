"""Timezone-aware time helpers.

Never use naive datetimes. Always UTC at the boundary; convert at display.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta


def utcnow() -> datetime:
    """Current time as a tz-aware UTC datetime."""
    return datetime.now(tz=UTC)


def utc_iso(dt: datetime | None = None) -> str:
    """ISO-8601 UTC string with Z suffix."""
    target = dt if dt is not None else utcnow()
    if target.tzinfo is None:
        raise ValueError("naive datetime is not allowed")
    return target.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_iso(value: str) -> datetime:
    """Parse ISO-8601, accept Z suffix, return tz-aware datetime."""
    cleaned = value.replace("Z", "+00:00")
    parsed = datetime.fromisoformat(cleaned)
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def seconds_since(dt: datetime) -> float:
    return (utcnow() - dt).total_seconds()


def expires_in(seconds: int) -> datetime:
    return utcnow() + timedelta(seconds=seconds)
