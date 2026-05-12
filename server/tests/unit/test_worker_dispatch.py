"""ARQ job dispatcher (workers.arq_settings.run)."""

from __future__ import annotations

from typing import Any

import pytest

from bubbles.workers import arq_settings


async def test_dispatch_routes_by_job_name(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: dict[str, Any] = {}

    async def _fake(ctx: dict[str, Any], *, user_id: str) -> str:
        seen["ctx"] = ctx
        seen["user_id"] = user_id
        return "ok"

    monkeypatch.setitem(arq_settings._JOB_REGISTRY, "compute_embeddings", _fake)
    out = await arq_settings.run({"x": 1}, _job_name="compute_embeddings", user_id="u1")
    assert out == "ok"
    assert seen == {"ctx": {"x": 1}, "user_id": "u1"}


async def test_dispatch_unknown_job_raises() -> None:
    with pytest.raises(ValueError, match="unknown job"):
        await arq_settings.run({}, _job_name="does_not_exist")


class _FakeRedis:
    def __init__(self) -> None:
        self.pushes: list[tuple[str, str]] = []
        self.trims: list[tuple[str, int, int]] = []

    async def rpush(self, key: str, value: str) -> int:
        self.pushes.append((key, value))
        return len(self.pushes)

    async def ltrim(self, key: str, start: int, stop: int) -> None:
        self.trims.append((key, start, stop))


async def _boom(ctx: dict[str, Any]) -> None:
    raise RuntimeError("kaboom")


async def test_dead_letter_on_final_try(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setitem(arq_settings._JOB_REGISTRY, "extract_knowledge", _boom)
    redis = _FakeRedis()
    ctx = {"redis_aux": redis, "job_try": arq_settings.MAX_TRIES}
    with pytest.raises(RuntimeError, match="kaboom"):
        await arq_settings.run(ctx, _job_name="extract_knowledge")
    assert len(redis.pushes) == 1
    key, payload = redis.pushes[0]
    assert key == arq_settings.DEAD_LETTER_KEY
    assert "extract_knowledge" in payload and "kaboom" in payload
    assert redis.trims == [(arq_settings.DEAD_LETTER_KEY, -1000, -1)]


async def test_no_dead_letter_before_final_try(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setitem(arq_settings._JOB_REGISTRY, "extract_knowledge", _boom)
    redis = _FakeRedis()
    ctx = {"redis_aux": redis, "job_try": 1}
    with pytest.raises(RuntimeError, match="kaboom"):
        await arq_settings.run(ctx, _job_name="extract_knowledge")
    assert redis.pushes == []
