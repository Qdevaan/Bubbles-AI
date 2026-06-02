"""Cerebras adapter — OpenAI-compatible at api.cerebras.ai/v1."""

from __future__ import annotations

import httpx

from bubbles.ai.providers._oai_compat import OAICompatProvider


def make_cerebras_provider(
    *,
    api_key: str,
    client: httpx.AsyncClient,
    name: str = "cerebras",
    default_model: str = "gpt-oss-120b",
) -> OAICompatProvider:
    return OAICompatProvider(
        name=name,
        base_url="https://api.cerebras.ai/v1",
        api_key=api_key,
        client=client,
        default_model=default_model,
    )
