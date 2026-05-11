"""Shared OpenAI-compatible chat-completions client.

Cerebras and Groq both expose an OpenAI-compatible /v1/chat/completions API.
We implement the wire protocol once here and let the concrete adapters set
their own ``base_url``, ``default_model``, and provider name.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator, Sequence
from typing import Any

import httpx

from bubbles.ai.providers.base import (
    ChatMessage,
    Chunk,
    Completion,
    ResponseFormat,
    Usage,
)
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger

log = get_logger(__name__)


def _to_oai_messages(messages: Sequence[ChatMessage]) -> list[dict[str, str]]:
    return [{"role": m.role.value, "content": m.content} for m in messages]


def _usage(meta: dict[str, Any] | None) -> Usage:
    if not meta:
        return Usage()
    return Usage(
        prompt_tokens=int(meta.get("prompt_tokens", 0) or 0),
        completion_tokens=int(meta.get("completion_tokens", 0) or 0),
        total_tokens=int(meta.get("total_tokens", 0) or 0),
    )


class OAICompatProvider:
    """OpenAI-compatible /v1/chat/completions client."""

    def __init__(
        self,
        *,
        name: str,
        base_url: str,
        api_key: str,
        client: httpx.AsyncClient,
        default_model: str,
    ) -> None:
        self.name = name
        self.default_model = default_model
        self._base_url = base_url.rstrip("/")
        self._client = client
        self._headers = {"Authorization": f"Bearer {api_key}"}

    async def complete(
        self,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
        response_format: ResponseFormat = "text",
        timeout_s: float = 25.0,
    ) -> Completion:
        body: dict[str, Any] = {
            "model": model or self.default_model,
            "messages": _to_oai_messages(messages),
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": False,
        }
        if response_format == "json":
            body["response_format"] = {"type": "json_object"}
        try:
            resp = await self._client.post(
                f"{self._base_url}/chat/completions",
                headers=self._headers,
                json=body,
                timeout=timeout_s,
            )
        except httpx.HTTPError as exc:
            raise UpstreamUnavailable(f"{self.name} transport: {exc!s}") from exc
        if resp.status_code >= 500:
            raise UpstreamUnavailable(f"{self.name} http {resp.status_code}")
        if resp.status_code >= 400:
            raise UpstreamUnavailable(f"{self.name} http {resp.status_code}: client error")
        data = resp.json()
        choice = (data.get("choices") or [{}])[0]
        msg = choice.get("message") or {}
        return Completion(
            text=msg.get("content") or "",
            finish_reason=choice.get("finish_reason"),
            usage=_usage(data.get("usage")),
            raw=data,
        )

    async def stream(
        self,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
        timeout_s: float = 25.0,
    ) -> AsyncIterator[Chunk]:
        body: dict[str, Any] = {
            "model": model or self.default_model,
            "messages": _to_oai_messages(messages),
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": True,
            "stream_options": {"include_usage": True},
        }
        url = f"{self._base_url}/chat/completions"
        try:
            async with self._client.stream(
                "POST",
                url,
                headers=self._headers,
                json=body,
                timeout=timeout_s,
            ) as resp:
                if resp.status_code >= 500:
                    raise UpstreamUnavailable(f"{self.name} http {resp.status_code}")
                if resp.status_code >= 400:
                    raise UpstreamUnavailable(f"{self.name} http {resp.status_code}: client error")
                async for line in resp.aiter_lines():
                    if not line or not line.startswith("data:"):
                        continue
                    payload = line[5:].strip()
                    if not payload or payload == "[DONE]":
                        continue
                    try:
                        data = json.loads(payload)
                    except json.JSONDecodeError:
                        log.warning("oai_bad_chunk", provider=self.name, payload=payload[:200])
                        continue
                    choice = (data.get("choices") or [{}])[0]
                    delta = choice.get("delta") or {}
                    text = delta.get("content") or ""
                    finish = choice.get("finish_reason")
                    usage = _usage(data.get("usage")) if finish else None
                    if text or finish:
                        yield Chunk(text=text, finish_reason=finish, usage=usage)
        except httpx.HTTPError as exc:
            raise UpstreamUnavailable(f"{self.name} stream transport: {exc!s}") from exc
