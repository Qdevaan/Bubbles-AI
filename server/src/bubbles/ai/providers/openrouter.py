# Purpose: OpenRouter provider — fallback gateway that proxies requests to multiple model vendors.
"""OpenRouter adapter — OpenAI-compatible at openrouter.ai/api/v1."""

from __future__ import annotations

import httpx

from bubbles.ai.providers._oai_compat import OAICompatProvider


def make_openrouter_provider(
    *,
    api_key: str,
    client: httpx.AsyncClient,
    default_model: str = "meta-llama/llama-3.3-70b-instruct:free",
) -> OAICompatProvider:
    return OAICompatProvider(
        name="openrouter",
        base_url="https://openrouter.ai/api/v1",
        api_key=api_key,
        client=client,
        default_model=default_model,
    )
