"""LLM router with per-task chains, circuit breaker, and budget.

Each task (e.g. ``consultant.stream``, ``wingman.json``) declares an ordered
list of providers. The router walks the chain on failure, skips tripped
breakers, and tracks ``fallback_depth`` for metrics.
"""

from __future__ import annotations

import asyncio
import time
from collections.abc import AsyncIterator, Iterable, Sequence
from dataclasses import dataclass
from typing import Any

from bubbles.ai.providers.base import (
    ChatMessage,
    Chunk,
    Completion,
    Provider,
    ResponseFormat,
)
from bubbles.core.circuit import CircuitBreaker
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger

log = get_logger(__name__)


@dataclass(frozen=True, slots=True)
class TaskChain:
    """Ordered fallback chain for a named task.

    ``providers`` are referenced by their ``Provider.name`` so a single
    Provider instance can serve many tasks.
    """

    task: str
    providers: tuple[str, ...]
    timeout_s: float = 25.0
    max_tokens: int = 1024
    temperature: float = 0.7


class LLMRouter:
    def __init__(
        self,
        providers: Iterable[Provider],
        chains: Iterable[TaskChain],
        *,
        breaker_error_rate: float = 0.5,
        breaker_window_s: int = 30,
        breaker_min_calls: int = 6,
        breaker_cool_down_s: float = 15.0,
    ) -> None:
        self._providers: dict[str, Provider] = {p.name: p for p in providers}
        self._chains: dict[str, TaskChain] = {c.task: c for c in chains}
        self._breakers: dict[str, CircuitBreaker] = {
            name: CircuitBreaker(
                f"llm:{name}",
                error_rate=breaker_error_rate,
                window_s=breaker_window_s,
                min_calls=breaker_min_calls,
                cool_down_s=breaker_cool_down_s,
            )
            for name in self._providers
        }
        self.last_fallback_depth: int = 0

    def _chain_for(self, task: str) -> TaskChain:
        chain = self._chains.get(task)
        if chain is None:
            raise KeyError(f"no chain configured for task {task!r}")
        return chain

    def _candidates(self, chain: TaskChain) -> Sequence[Provider]:
        out: list[Provider] = []
        for name in chain.providers:
            provider = self._providers.get(name)
            if provider is None:
                log.warning("router_unknown_provider", task=chain.task, provider=name)
                continue
            out.append(provider)
        if not out:
            raise UpstreamUnavailable(f"no providers available for {chain.task}")
        return out

    async def complete(
        self,
        task: str,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        response_format: ResponseFormat = "text",
        overrides: dict[str, Any] | None = None,
    ) -> Completion:
        chain = self._chain_for(task)
        opts = dict(overrides or {})
        last_exc: Exception | None = None
        for depth, provider in enumerate(self._candidates(chain)):
            breaker = self._breakers[provider.name]
            self.last_fallback_depth = depth
            started = time.perf_counter()
            try:

                async def call(p: Provider = provider) -> Completion:
                    return await p.complete(
                        messages,
                        model=model,
                        temperature=opts.get("temperature", chain.temperature),
                        max_tokens=opts.get("max_tokens", chain.max_tokens),
                        response_format=response_format,
                        timeout_s=opts.get("timeout_s", chain.timeout_s),
                    )

                completion = await breaker.call(call)
            except UpstreamUnavailable as exc:
                last_exc = exc
                log.warning(
                    "llm_provider_failed",
                    task=task,
                    provider=provider.name,
                    depth=depth,
                    elapsed_ms=(time.perf_counter() - started) * 1000,
                    error=str(exc),
                )
                continue
            log.info(
                "llm_completion",
                task=task,
                provider=provider.name,
                depth=depth,
                tokens_in=completion.usage.prompt_tokens,
                tokens_out=completion.usage.completion_tokens,
                elapsed_ms=(time.perf_counter() - started) * 1000,
            )
            return completion
        raise UpstreamUnavailable(f"{task} chain exhausted: {last_exc}") from last_exc

    async def stream(
        self,
        task: str,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        overrides: dict[str, Any] | None = None,
    ) -> AsyncIterator[Chunk]:
        """Stream chunks from the first healthy provider in the chain.

        We commit to a provider only after the first chunk arrives; until
        then a transport error falls through to the next candidate.
        """
        chain = self._chain_for(task)
        opts = dict(overrides or {})
        last_exc: Exception | None = None

        for depth, provider in enumerate(self._candidates(chain)):
            self.last_fallback_depth = depth
            stream_iter = provider.stream(
                messages,
                model=model,
                temperature=opts.get("temperature", chain.temperature),
                max_tokens=opts.get("max_tokens", chain.max_tokens),
                timeout_s=opts.get("timeout_s", chain.timeout_s),
            )
            try:
                first = await asyncio.wait_for(stream_iter.__anext__(), timeout=10.0)
            except (TimeoutError, UpstreamUnavailable, StopAsyncIteration) as exc:
                last_exc = exc if isinstance(exc, Exception) else None
                log.warning(
                    "llm_stream_first_chunk_failed",
                    task=task,
                    provider=provider.name,
                    depth=depth,
                    error=str(exc),
                )
                continue

            log.info("llm_stream_committed", task=task, provider=provider.name, depth=depth)
            yield first
            async for chunk in stream_iter:
                yield chunk
            return
        raise UpstreamUnavailable(f"{task} stream chain exhausted: {last_exc}") from last_exc


# Default chains for the canonical Bubbles tasks. App-level wiring picks
# providers from ``Settings`` and only registers ones whose API keys are set.
DEFAULT_CHAINS: tuple[TaskChain, ...] = (
    TaskChain("consultant.stream", ("gemini", "cerebras", "groq"), max_tokens=1024),
    TaskChain("consultant.complete", ("gemini", "cerebras", "groq"), max_tokens=1024),
    TaskChain("wingman.json", ("cerebras", "groq", "gemini"), temperature=0.2, max_tokens=600),
    TaskChain("wingman.short", ("cerebras", "groq"), temperature=0.3, max_tokens=300),
    TaskChain("wingman.advice", ("cerebras", "groq", "gemini"), temperature=0.4, max_tokens=300),
    TaskChain("grammar.correct", ("groq", "cerebras"), temperature=0.0, max_tokens=400),
    TaskChain(
        "analytics.coaching", ("gemini", "cerebras", "groq"), temperature=0.3, max_tokens=900
    ),
)
