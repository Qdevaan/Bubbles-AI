"""Cerebras adapter — OpenAI-compatible at api.cerebras.ai/v1."""

from __future__ import annotations

import httpx

from bubbles.ai.providers._oai_compat import OAICompatProvider


def make_cerebras_provider(
    *,
    api_key: str,
    client: httpx.AsyncClient,
    default_model: str = "llama3.1-8b",
) -> OAICompatProvider:
    return OAICompatProvider(
        name="cerebras",
        base_url="https://api.cerebras.ai/v1",
        api_key=api_key,
        client=client,
        default_model=default_model,
    )
