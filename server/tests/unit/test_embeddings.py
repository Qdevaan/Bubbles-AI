"""Embedding service: cache hit, cache miss, error path."""

from __future__ import annotations

from typing import Any

import pytest

from bubbles.ai.embeddings import EmbeddingService
from bubbles.core.cache import Cache
from bubbles.core.errors import UpstreamUnavailable


class _FakeRedis:
    def __init__(self) -> None:
        self.store: dict[str, bytes] = {}

    async def get(self, key: str) -> bytes | None:
        return self.store.get(key)

    async def set(self, key: str, value: bytes, *, ex: int | None = None) -> None:
        self.store[key] = value

    async def delete(self, key: str) -> None:
        self.store.pop(key, None)


class _FakeGemini:
    def __init__(self) -> None:
        self.calls = 0

    async def embed(self, text: str, *, model: str = "text-embedding-004") -> list[float]:
        self.calls += 1
        return [0.1, 0.2, 0.3]


_MISSING: Any = object()


def _make_service(
    gemini: Any = _MISSING,
) -> tuple[EmbeddingService, _FakeGemini | None, _FakeRedis]:
    redis = _FakeRedis()
    cache = Cache(redis)  # type: ignore[arg-type]
    g: _FakeGemini | None = _FakeGemini() if gemini is _MISSING else gemini
    svc = EmbeddingService(gemini=g, cache=cache)  # type: ignore[arg-type]
    return svc, g, redis


async def test_embed_caches_after_first_call() -> None:
    svc, gemini, _ = _make_service()
    assert gemini is not None
    a = await svc.embed("hi")
    b = await svc.embed("hi")
    assert a == b == [0.1, 0.2, 0.3]
    assert gemini.calls == 1


async def test_embed_empty_text_raises() -> None:
    svc, _, _ = _make_service()
    with pytest.raises(ValueError):
        await svc.embed("   ")


async def test_embed_no_provider_raises() -> None:
    svc, _, _ = _make_service(gemini=None)
    with pytest.raises(UpstreamUnavailable):
        await svc.embed("x")
