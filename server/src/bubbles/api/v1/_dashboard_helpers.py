# Purpose: Private helper functions that assemble dashboard summary rows from multiple repo queries.
"""Pure helpers for the progress-dashboard route.

No I/O, no DB, no HTTP. ``resolve_range`` turns the ``range`` query
parameter into a ``(cur_start, cur_end, prev_start, prev_end, pg_step,
granularity)`` tuple. ``delta_pct`` computes the previous-window
comparison with the well-known edge cases handled explicitly.

The ``pg_step`` strings are PostgreSQL ``interval`` literals consumed by
the dashboard repo's ``generate_series`` queries.
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime, timedelta
from typing import Final

# (delta, pg_step, granularity label)
RANGES: Final[Mapping[str, tuple[timedelta, str, str]]] = {
    "30d": (timedelta(days=30), "1 day", "daily"),
    "90d": (timedelta(days=90), "1 week", "weekly"),
    "365d": (timedelta(days=365), "1 month", "monthly"),
}


def resolve_range(
    range_arg: str, now: datetime
) -> tuple[datetime, datetime, datetime, datetime, str, str]:
    """Resolve ``range_arg`` into ``(cur_start, cur_end, prev_start, prev_end, pg_step, granularity)``.

    ``cur_end`` is ``now``; ``cur_start`` is ``now - delta``. The previous
    window is the same-length window immediately before the current one:
    ``[cur_start - delta, cur_start)``. Raises ``ValueError`` if
    ``range_arg`` is not one of the three preset keys.
    """
    if range_arg not in RANGES:
        raise ValueError(f"unknown range: {range_arg!r}")
    delta, pg_step, granularity = RANGES[range_arg]
    cur_end = now
    cur_start = now - delta
    prev_end = cur_start
    prev_start = cur_start - delta
    return cur_start, cur_end, prev_start, prev_end, pg_step, granularity


def delta_pct(current: float, previous: float) -> float | None:
    """Return ``((current - previous) / previous) * 100`` rounded to 1 dp.

    Returns ``None`` when ``previous == 0 and current != 0`` (cannot
    divide). Returns ``0.0`` when both are exactly zero (no change).
    """
    if previous == 0:
        return 0.0 if current == 0 else None
    return round(((current - previous) / previous) * 100, 1)
