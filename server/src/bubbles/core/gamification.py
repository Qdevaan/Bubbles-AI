"""Pure XP/level math — no I/O. Formula ported from server_v2.

cumulative_xp(level) = 50 * level * (level - 1)
level_for_xp(xp)     = floor((1 + sqrt(1 + 4 * xp / 50)) / 2), clamped to >= 1
"""

from __future__ import annotations

import math
from dataclasses import dataclass


def xp_for_level(level: int) -> int:
    """Cumulative XP required to *reach* ``level``."""
    return 50 * level * (level - 1)


def level_for_xp(total_xp: int) -> int:
    """Current level for a given total XP amount (>= 1)."""
    if total_xp <= 0:
        return 1
    level = int((1 + math.sqrt(1 + 4 * total_xp / 50)) / 2)
    return max(1, level)


@dataclass(frozen=True, slots=True)
class LevelProgress:
    level: int
    xp_into_level: int  # total_xp - xp_for_level(level)
    xp_to_next_level: int  # xp_for_level(level + 1) - total_xp
    progress_pct: float  # xp_into_level / band_width, always in [0.0, 1.0)


def level_progress(total_xp: int) -> LevelProgress:
    xp = max(0, total_xp)
    level = level_for_xp(xp)
    floor_xp = xp_for_level(level)
    next_xp = xp_for_level(level + 1)
    band = next_xp - floor_xp  # 100 * level, always > 0 for level >= 1
    into = xp - floor_xp
    return LevelProgress(
        level=level,
        xp_into_level=into,
        xp_to_next_level=next_xp - xp,
        progress_pct=into / band,
    )
