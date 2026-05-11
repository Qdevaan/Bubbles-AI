"""Build the AI router + embeddings stack from Settings.

We register only providers whose API keys are set. Empty chains short-circuit
to ``UpstreamUnavailable`` at request time; explicit and inspectable.
"""

from __future__ import annotations

from dataclasses import dataclass

import httpx

from bubbles.ai.embeddings import EmbeddingService
from bubbles.ai.providers.base import Provider, make_http_client
from bubbles.ai.providers.cerebras import make_cerebras_provider
from bubbles.ai.providers.gemini import GeminiProvider
from bubbles.ai.providers.groq import make_groq_provider
from bubbles.ai.router import DEFAULT_CHAINS, LLMRouter
from bubbles.core.cache import Cache
from bubbles.core.logging import get_logger
from bubbles.settings import Settings

log = get_logger(__name__)


@dataclass(slots=True)
class AIStack:
    http_client: httpx.AsyncClient
    router: LLMRouter
    embeddings: EmbeddingService
    gemini: GeminiProvider | None


def build_ai_stack(settings: Settings, cache: Cache) -> AIStack:
    client = make_http_client(timeout_s=settings.llm_call_timeout_s + 5)
    providers: list[Provider] = []
    gemini: GeminiProvider | None = None

    if settings.gemini_api_key is not None:
        gemini = GeminiProvider(
            api_key=settings.gemini_api_key.get_secret_value(),
            client=client,
            default_model=settings.gemini_consultant_model,
        )
        providers.append(gemini)
    if settings.cerebras_api_key is not None:
        providers.append(
            make_cerebras_provider(
                api_key=settings.cerebras_api_key.get_secret_value(),
                client=client,
                default_model=settings.cerebras_wingman_model,
            )
        )
    if settings.groq_api_key is not None:
        providers.append(
            make_groq_provider(
                api_key=settings.groq_api_key.get_secret_value(),
                client=client,
                default_model=settings.groq_wingman_model,
            )
        )

    if not providers:
        log.warning("no_llm_providers_configured")

    router = LLMRouter(
        providers,
        DEFAULT_CHAINS,
        breaker_error_rate=settings.llm_breaker_error_rate,
        breaker_window_s=settings.llm_breaker_window_s,
    )
    embeddings = EmbeddingService(
        gemini=gemini,
        cache=cache,
        model=settings.embedding_model,
    )
    return AIStack(http_client=client, router=router, embeddings=embeddings, gemini=gemini)
