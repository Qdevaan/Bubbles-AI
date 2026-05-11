"""Timezone-aware time helpers."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from bubbles.core.time import expires_in, parse_iso, seconds_since, utc_iso, utcnow


def test_utcnow_is_aware() -> None:
    assert utcnow().tzinfo is UTC


def test_utc_iso_round_trip() -> None:
    now = utcnow()
    s = utc_iso(now)
    assert s.endswith("Z")
    assert parse_iso(s) == now.replace(microsecond=now.microsecond)


def test_utc_iso_rejects_naive() -> None:
    with pytest.raises(ValueError):
        utc_iso(datetime(2026, 1, 1))


def test_seconds_since_is_positive_for_past() -> None:
    past = datetime(2026, 1, 1, tzinfo=UTC)
    assert seconds_since(past) > 0


def test_expires_in_returns_future() -> None:
    future = expires_in(60)
    assert future > utcnow()
