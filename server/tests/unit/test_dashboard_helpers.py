"""Pure-helper tests for api.v1._dashboard_helpers."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from bubbles.api.v1._dashboard_helpers import RANGES, delta_pct, resolve_range

_NOW = datetime(2026, 5, 23, 12, 0, 0, tzinfo=UTC)


def test_ranges_table_has_three_entries() -> None:
    assert set(RANGES.keys()) == {"30d", "90d", "365d"}


@pytest.mark.parametrize(
    ("range_arg", "expected_delta_days", "expected_step", "expected_granularity"),
    [
        ("30d", 30, "1 day", "daily"),
        ("90d", 90, "1 week", "weekly"),
        ("365d", 365, "1 month", "monthly"),
    ],
)
def test_resolve_range_returns_expected_window_and_step(
    range_arg: str, expected_delta_days: int, expected_step: str, expected_granularity: str
) -> None:
    cur_start, cur_end, prev_start, prev_end, step, granularity = resolve_range(range_arg, _NOW)
    assert cur_end == _NOW
    assert cur_start == _NOW - timedelta(days=expected_delta_days)
    assert prev_end == cur_start
    assert prev_start == cur_start - timedelta(days=expected_delta_days)
    assert step == expected_step
    assert granularity == expected_granularity


def test_resolve_range_rejects_unknown_value() -> None:
    with pytest.raises(ValueError, match=r"unknown range"):
        resolve_range("7d", _NOW)


def test_delta_pct_basic_increase() -> None:
    assert delta_pct(120, 100) == 20.0


def test_delta_pct_basic_decrease() -> None:
    assert delta_pct(50, 100) == -50.0


def test_delta_pct_previous_zero_returns_none() -> None:
    assert delta_pct(10, 0) is None


def test_delta_pct_both_zero_returns_zero() -> None:
    assert delta_pct(0, 0) == 0.0


def test_delta_pct_rounds_to_one_decimal() -> None:
    assert delta_pct(123, 100) == 23.0
    assert delta_pct(1234, 1000) == 23.4
    assert delta_pct(12345, 10000) == 23.4  # 23.45 → 23.4 (banker's rounding)
