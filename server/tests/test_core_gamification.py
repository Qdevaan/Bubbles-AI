"""Unit tests for the pure level-math helpers."""

from __future__ import annotations

import math

import pytest

from bubbles.core.gamification import (
    LevelProgress,
    level_for_xp,
    level_progress,
    xp_for_level,
)


def test_xp_for_level_formula() -> None:
    # cumulative_xp(level) = 50 * level * (level - 1)
    assert xp_for_level(1) == 0
    assert xp_for_level(2) == 100
    assert xp_for_level(3) == 300
    assert xp_for_level(5) == 1000


def test_level_for_xp_basics() -> None:
    assert level_for_xp(0) == 1
    assert level_for_xp(-50) == 1  # negative clamps to 1
    assert level_for_xp(99) == 1
    assert level_for_xp(100) == 2  # exact boundary
    assert level_for_xp(299) == 2
    assert level_for_xp(300) == 3


def test_level_progress_at_zero() -> None:
    lp = level_progress(0)
    assert isinstance(lp, LevelProgress)
    assert lp.level == 1
    assert lp.xp_into_level == 0
    assert lp.xp_to_next_level == 100  # xp_for_level(2) - 0
    assert lp.progress_pct == 0.0


def test_level_progress_at_boundary() -> None:
    lp = level_progress(100)  # exactly level 2
    assert lp.level == 2
    assert lp.xp_into_level == 0
    assert lp.xp_to_next_level == 200  # xp_for_level(3)=300 minus 100
    assert lp.progress_pct == 0.0


def test_level_progress_midway() -> None:
    lp = level_progress(200)  # level 2 (100..299), 100 into a 200-wide band
    assert lp.level == 2
    assert lp.xp_into_level == 100
    assert lp.xp_to_next_level == 100
    assert math.isclose(lp.progress_pct, 0.5)


@pytest.mark.parametrize("xp", [0, 1, 50, 99, 100, 250, 999, 1000, 5000, 123456])
def test_progress_pct_invariant(xp: int) -> None:
    lp = level_progress(xp)
    assert 0.0 <= lp.progress_pct < 1.0
    assert lp.level >= 1
    assert lp.xp_into_level >= 0
    assert lp.xp_to_next_level >= 1
