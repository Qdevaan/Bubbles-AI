"""Pure-helper tests for ai.drills.next_state."""

from __future__ import annotations

from datetime import timedelta

import pytest

from bubbles.ai.drills import BOX_INTERVALS, next_state


def test_box_intervals_table_is_complete() -> None:
    assert set(BOX_INTERVALS.keys()) == {1, 2, 3, 4, 5}
    assert BOX_INTERVALS[1] == timedelta(days=1)
    assert BOX_INTERVALS[2] == timedelta(days=3)
    assert BOX_INTERVALS[3] == timedelta(days=7)
    assert BOX_INTERVALS[4] == timedelta(days=14)
    assert BOX_INTERVALS[5] == timedelta(days=30)


@pytest.mark.parametrize(
    ("from_box", "expected_new_box", "expected_interval"),
    [
        (1, 2, timedelta(days=3)),
        (2, 3, timedelta(days=7)),
        (3, 4, timedelta(days=14)),
        (4, 5, timedelta(days=30)),
        (5, 5, timedelta(days=30)),  # cap at 5
    ],
)
def test_correct_review_advances_box(
    from_box: int, expected_new_box: int, expected_interval: timedelta
) -> None:
    new_box, interval, transition = next_state(from_box, "correct")
    assert new_box == expected_new_box
    assert interval == expected_interval
    assert transition == f"{from_box}->{expected_new_box}"


@pytest.mark.parametrize("from_box", [1, 2, 3, 4, 5])
def test_wrong_review_resets_to_box_one(from_box: int) -> None:
    new_box, interval, transition = next_state(from_box, "wrong")
    assert new_box == 1
    assert interval == timedelta(days=1)
    assert transition == f"{from_box}->1"


def test_invalid_box_raises() -> None:
    with pytest.raises(ValueError, match=r"box must be 1\.\.5"):
        next_state(0, "correct")
    with pytest.raises(ValueError, match=r"box must be 1\.\.5"):
        next_state(6, "correct")


def test_invalid_result_raises() -> None:
    with pytest.raises(ValueError, match=r"result must be 'correct' or 'wrong'"):
        next_state(1, "ok")  # type: ignore[arg-type]
