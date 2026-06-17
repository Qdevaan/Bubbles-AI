# Purpose: Pure Leitner-box math for spaced-repetition drill scheduling — no I/O, fully unit-testable.
"""Pure helpers for the drill (spaced-repetition) subsystem.

Leitner-box transition math. No I/O, no DB, no LLM — unit-testable.

``BOX_INTERVALS`` maps each box (1..5) to the wait between consecutive
reviews. ``next_state(box, result)`` returns the post-review box, the new
interval, and a ``"{from}->{to}"`` transition label used as part of the
XP-idempotency source-id.
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import timedelta
from typing import Final, Literal

ReviewResult = Literal["correct", "wrong"]

BOX_INTERVALS: Final[Mapping[int, timedelta]] = {
    1: timedelta(days=1),
    2: timedelta(days=3),
    3: timedelta(days=7),
    4: timedelta(days=14),
    5: timedelta(days=30),
}

_MAX_BOX: Final[int] = 5
_MIN_BOX: Final[int] = 1


def next_state(box: int, result: ReviewResult) -> tuple[int, timedelta, str]:
    """Return ``(new_box, interval_to_next_due, transition_label)`` for a Leitner step.

    Correct → box advances by 1 (capped at 5).
    Wrong → box resets to 1.
    The interval is ``BOX_INTERVALS[new_box]``. The transition label is
    ``f"{from_box}->{new_box}"`` and is part of the XP idempotency key.
    """
    if box < _MIN_BOX or box > _MAX_BOX:
        raise ValueError("box must be 1..5")
    if result not in ("correct", "wrong"):
        raise ValueError("result must be 'correct' or 'wrong'")
    new_box = min(box + 1, _MAX_BOX) if result == "correct" else _MIN_BOX
    return new_box, BOX_INTERVALS[new_box], f"{box}->{new_box}"
