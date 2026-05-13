"""sentiment_scan worker — scores session_logs turns, re-enqueues analytics."""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any
from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.workers.jobs import sentiment_scan

pytestmark = pytest.mark.integration


class _FakeArq:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    async def enqueue_job(self, *_args: Any, **kwargs: Any) -> str:
        self.calls.append(kwargs)
        return str(kwargs.get("_job_id", "job"))


async def _make_session(pool: asyncpg.Pool, owner: UUID) -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'active') RETURNING id",
            owner,
        )
    assert row is not None
    sid: UUID = row["id"]
    return sid


async def test_sentiment_scan_writes_scores_and_reenqueues(
    pool: asyncpg.Pool, user_id: UUID, monkeypatch: pytest.MonkeyPatch
) -> None:
    sid = await _make_session(pool, user_id)
    async with pool.acquire() as con:
        await session_logs_repo.append(con, session_id=sid, role="user", content="this is great")
        await session_logs_repo.append(con, session_id=sid, role="others", content="ugh, no")
        await session_logs_repo.append(con, session_id=sid, role="llm", content="advice here")

    async def _fake_score(
        _router: Any, turns: list[dict[str, Any]]
    ) -> dict[int, tuple[float | None, str | None]]:
        assert all(t["role"] != "llm" for t in turns)  # llm turns excluded
        return {0: (0.8, "pleased"), 1: (-0.7, "frustrated")}

    monkeypatch.setattr(sentiment_scan, "score_turn_sentiments", _fake_score)
    arq = _FakeArq()
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool),
        "redis": arq,
    }
    result = await sentiment_scan.run(ctx, user_id=str(user_id), session_id=str(sid))
    assert result["scored"] == 2

    async with pool.acquire() as con:
        rows = await con.fetch(
            "SELECT turn_index, sentiment_score, sentiment_label FROM session_logs "
            "WHERE session_id = $1 ORDER BY turn_index",
            sid,
        )
    assert [
        (
            r["turn_index"],
            float(r["sentiment_score"]) if r["sentiment_score"] is not None else None,
            r["sentiment_label"],
        )
        for r in rows
    ] == [
        (0, 0.8, "pleased"),
        (1, -0.7, "frustrated"),
        (2, None, None),  # llm turn untouched
    ]
    # Re-enqueued compute_session_analytics with the post-sentiment suffix.
    names = [c.get("_job_name") for c in arq.calls]
    assert "compute_session_analytics" in names
    assert any("post_sentiment" in str(c.get("_job_id", "")) for c in arq.calls)


async def test_sentiment_scan_noop_when_nothing_to_score(pool: asyncpg.Pool, user_id: UUID) -> None:
    sid = await _make_session(pool, user_id)
    ctx: dict[str, Any] = {
        "bubbles": SimpleNamespace(ai=SimpleNamespace(router=object()), pool=pool),
        "redis": _FakeArq(),
    }
    assert await sentiment_scan.run(ctx, user_id=str(user_id), session_id=str(sid)) == {"scored": 0}
