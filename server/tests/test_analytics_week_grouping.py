"""Unit tests for the ISO-week grouping helper used by communication_trends."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from bubbles.api.v1.analytics import _group_by_week


def _rec(computed_at: datetime, **kw: object) -> dict[str, object]:
    base: dict[str, object] = {
        "total_turns": 0,
        "user_word_count": 0,
        "assistant_word_count": 0,
        "avg_sentiment_score": None,
        "total_duration_seconds": 0,
        "computed_at": computed_at,
    }
    base.update(kw)
    return base


def test_empty_input() -> None:
    assert _group_by_week([]) == []


def test_single_row() -> None:
    rows = [_rec(datetime(2026, 5, 12, tzinfo=UTC), total_turns=5, user_word_count=10)]
    out = _group_by_week(rows)
    assert len(out) == 1
    assert out[0].week == "2026-W20"
    assert out[0].sessions == 1
    assert out[0].total_turns == 5
    assert out[0].user_words == 10
    assert out[0].avg_sentiment_score is None


def test_multiple_rows_same_week_are_aggregated() -> None:
    d1 = datetime(2026, 5, 11, tzinfo=UTC)
    d2 = datetime(2026, 5, 13, tzinfo=UTC)
    rows = [
        _rec(
            d1,
            total_turns=3,
            user_word_count=5,
            assistant_word_count=4,
            avg_sentiment_score=0.2,
            total_duration_seconds=60,
        ),
        _rec(
            d2,
            total_turns=7,
            user_word_count=15,
            assistant_word_count=6,
            avg_sentiment_score=0.6,
            total_duration_seconds=90,
        ),
    ]
    out = _group_by_week(rows)
    assert len(out) == 1
    w = out[0]
    assert w.week == "2026-W20"
    assert w.sessions == 2
    assert w.total_turns == 10
    assert w.user_words == 20
    assert w.ai_words == 10
    assert w.total_duration_seconds == 150.0
    assert w.avg_sentiment_score == pytest.approx(0.4)


def test_rows_spanning_weeks_sorted_newest_first() -> None:
    early = datetime(2026, 5, 4, tzinfo=UTC)  # 2026-W19
    late = datetime(2026, 5, 12, tzinfo=UTC)  # 2026-W20
    out = _group_by_week([_rec(early), _rec(late)])
    assert [w.week for w in out] == ["2026-W20", "2026-W19"]


def test_null_sentiment_ignored_in_average() -> None:
    d = datetime(2026, 5, 12, tzinfo=UTC)
    rows = [_rec(d, avg_sentiment_score=None), _rec(d, avg_sentiment_score=0.5)]
    out = _group_by_week(rows)
    assert out[0].avg_sentiment_score == 0.5
