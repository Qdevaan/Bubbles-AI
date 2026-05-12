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
