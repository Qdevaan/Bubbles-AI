"""Groq adapter — OpenAI-compatible at api.groq.com/openai/v1."""

from __future__ import annotations

import httpx

from bubbles.ai.providers._oai_compat import OAICompatProvider


def make_groq_provider(
    *,
    api_key: str,
    client: httpx.AsyncClient,
    default_model: str = "llama-3.1-8b-instant",
) -> OAICompatProvider:
    return OAICompatProvider(
        name="groq",
        base_url="https://api.groq.com/openai/v1",
        api_key=api_key,
        client=client,
        default_model=default_model,
    )
