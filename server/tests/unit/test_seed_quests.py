"""seed_quests skips when defs already present, inserts otherwise."""

from __future__ import annotations

from typing import Any

from bubbles.workers.jobs import seed_quests


class _FakeConn:
    def __init__(self, count: int) -> None:
        self._count = count
        self.exec_calls: list[tuple[Any, ...]] = []

    async def fetchval(self, query: str) -> int:
        return self._count

    async def execute(self, *args: Any, **kwargs: Any) -> None:
        self.exec_calls.append(args)


class _FakeUoW:
    def __init__(self, conn: _FakeConn) -> None:
        self.conn = conn

    async def __aenter__(self) -> _FakeUoW:
        return self

    async def __aexit__(self, *exc: Any) -> None:
        return None


def _ctx(conn: _FakeConn) -> dict[str, Any]:
    class _Stub:
        pool = object()

    return {"bubbles": _Stub()}


async def test_seed_skips_when_existing(monkeypatch: Any) -> None:
    conn = _FakeConn(count=3)
    monkeypatch.setattr(seed_quests, "UnitOfWork", lambda _pool: _FakeUoW(conn))
    out = await seed_quests.run(_ctx(conn))
    assert out == 0
    assert not conn.exec_calls


async def test_seed_inserts_defaults(monkeypatch: Any) -> None:
    conn = _FakeConn(count=0)
    monkeypatch.setattr(seed_quests, "UnitOfWork", lambda _pool: _FakeUoW(conn))
    out = await seed_quests.run(_ctx(conn))
    assert out == len(seed_quests._DEFAULTS)
    assert len(conn.exec_calls) == len(seed_quests._DEFAULTS)
