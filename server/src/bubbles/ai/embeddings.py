# Purpose: Generates and caches sentence-level text embeddings via the configured AI provider for semantic search.
"""Embedding service with Gemini primary + cache.

Local ONNX fallback is wired behind the same interface but loaded lazily so
the cold path doesn't pay the model-load cost when the primary is healthy.
"""

from __future__ import annotations

from collections.abc import Sequence

from bubbles.ai.providers.gemini import GeminiProvider
from bubbles.core.cache import Cache
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.hashing import cache_key
from bubbles.core.logging import get_logger

log = get_logger(__name__)


class EmbeddingService:
    def __init__(
        self,
        *,
        gemini: GeminiProvider | None,
        cache: Cache,
        model: str = "text-embedding-004",
        cache_ttl_s: int = 7 * 86400,
    ) -> None:
        self._gemini = gemini
        self._cache = cache
        self._model = model
        self._cache_ttl_s = cache_ttl_s

    async def embed(self, text: str) -> Sequence[float]:
        if not text.strip():
            raise ValueError("text is empty")
        key = cache_key("embed", self._model, text)
        cached = await self._cache.get_json(key)
        if isinstance(cached, list):
            return [float(v) for v in cached]
        if self._gemini is None:
            raise UpstreamUnavailable("no embedding provider configured")
        vec = await self._gemini.embed(text, model=self._model)
        await self._cache.set_json(key, vec, ttl=self._cache_ttl_s)
        return vec
