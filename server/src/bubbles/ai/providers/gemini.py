"""Gemini adapter — Google Generative Language API v1beta.

Reference shapes:
    POST /v1beta/models/{model}:generateContent
    POST /v1beta/models/{model}:streamGenerateContent?alt=sse
    POST /v1beta/models/{model}:embedContent
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
    Role,
    Usage,
)
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger

log = get_logger(__name__)

_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"


def _to_gemini_messages(messages: Sequence[ChatMessage]) -> tuple[str | None, list[dict[str, Any]]]:
    """Split off system instructions and shape the rest as Gemini contents."""
    system: str | None = None
    contents: list[dict[str, Any]] = []
    for msg in messages:
        if msg.role is Role.system:
            system = (system + "\n" + msg.content) if system else msg.content
            continue
        role = "user" if msg.role is Role.user else "model"
        contents.append({"role": role, "parts": [{"text": msg.content}]})
    return system, contents


def _usage_from(meta: dict[str, Any] | None) -> Usage:
    if not meta:
        return Usage()
    return Usage(
        prompt_tokens=int(meta.get("promptTokenCount", 0) or 0),
        completion_tokens=int(meta.get("candidatesTokenCount", 0) or 0),
        total_tokens=int(meta.get("totalTokenCount", 0) or 0),
    )


def _extract_text(payload: dict[str, Any]) -> tuple[str, str | None]:
    candidates = payload.get("candidates") or []
    if not candidates:
        return "", None
    first = candidates[0]
    parts = (first.get("content") or {}).get("parts") or []
    text = "".join(p.get("text", "") for p in parts if isinstance(p, dict))
    return text, first.get("finishReason")


class GeminiProvider:
    name = "gemini"

    def __init__(
        self,
        api_key: str,
        *,
        client: httpx.AsyncClient,
        default_model: str = "gemini-2.5-flash",
    ) -> None:
        self._api_key = api_key
        self._client = client
        self.default_model = default_model

    def _url(self, model: str, op: str) -> str:
        return f"{_BASE_URL}/models/{model}:{op}"

    def _params(self) -> dict[str, str]:
        return {"key": self._api_key}

    def _generation_config(
        self,
        *,
        temperature: float,
        max_tokens: int,
        response_format: ResponseFormat,
    ) -> dict[str, Any]:
        cfg: dict[str, Any] = {
            "temperature": temperature,
            "maxOutputTokens": max_tokens,
        }
        if response_format == "json":
            cfg["responseMimeType"] = "application/json"
        return cfg

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
        model = model or self.default_model
        system, contents = _to_gemini_messages(messages)
        body: dict[str, Any] = {
            "contents": contents,
            "generationConfig": self._generation_config(
                temperature=temperature,
                max_tokens=max_tokens,
                response_format=response_format,
            ),
        }
        if system:
            body["systemInstruction"] = {"parts": [{"text": system}]}
        try:
            resp = await self._client.post(
                self._url(model, "generateContent"),
                params=self._params(),
                json=body,
                timeout=timeout_s,
            )
        except httpx.HTTPError as exc:
            raise UpstreamUnavailable(f"gemini transport error: {exc!s}") from exc
        if resp.status_code >= 500:
            raise UpstreamUnavailable(f"gemini http {resp.status_code}")
        if resp.status_code >= 400:
            raise UpstreamUnavailable(f"gemini http {resp.status_code}: client error")
        data = resp.json()
        text, finish = _extract_text(data)
        return Completion(
            text=text,
            finish_reason=finish,
            usage=_usage_from(data.get("usageMetadata")),
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
        model = model or self.default_model
        system, contents = _to_gemini_messages(messages)
        body: dict[str, Any] = {
            "contents": contents,
            "generationConfig": self._generation_config(
                temperature=temperature,
                max_tokens=max_tokens,
                response_format="text",
            ),
        }
        if system:
            body["systemInstruction"] = {"parts": [{"text": system}]}
        url = self._url(model, "streamGenerateContent")
        try:
            async with self._client.stream(
                "POST",
                url,
                params={**self._params(), "alt": "sse"},
                json=body,
                timeout=timeout_s,
            ) as resp:
                if resp.status_code >= 500:
                    raise UpstreamUnavailable(f"gemini http {resp.status_code}")
                if resp.status_code >= 400:
                    raise UpstreamUnavailable(f"gemini http {resp.status_code}: client error")
                async for line in resp.aiter_lines():
                    if not line or not line.startswith("data:"):
                        continue
                    payload = line[5:].strip()
                    if not payload or payload == "[DONE]":
                        continue
                    try:
                        data = json.loads(payload)
                    except json.JSONDecodeError:
                        log.warning("gemini_bad_chunk", payload=payload[:200])
                        continue
                    text, finish = _extract_text(data)
                    usage = _usage_from(data.get("usageMetadata"))
                    if text or finish:
                        yield Chunk(
                            text=text, finish_reason=finish, usage=usage if finish else None
                        )
        except httpx.HTTPError as exc:
            raise UpstreamUnavailable(f"gemini stream transport: {exc!s}") from exc

    async def embed(
        self,
        text: str,
        *,
        model: str = "text-embedding-004",
        timeout_s: float = 10.0,
    ) -> list[float]:
        try:
            resp = await self._client.post(
                self._url(model, "embedContent"),
                params=self._params(),
                json={"content": {"parts": [{"text": text}]}},
                timeout=timeout_s,
            )
        except httpx.HTTPError as exc:
            raise UpstreamUnavailable(f"gemini embed transport: {exc!s}") from exc
        if resp.status_code >= 400:
            raise UpstreamUnavailable(f"gemini embed http {resp.status_code}")
        data = resp.json()
        values = (data.get("embedding") or {}).get("values") or []
        if not values:
            raise UpstreamUnavailable("gemini embed returned no values")
        return [float(v) for v in values]
