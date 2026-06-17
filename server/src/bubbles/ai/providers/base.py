# Purpose: Abstract base class defining the provider interface (complete, stream, embed) that all providers implement.
"""LLM provider protocol + shared types.

We talk to providers over HTTP directly (httpx), not via vendor SDKs:

- one transport surface to instrument and circuit-break;
- trivial to mock with respx in tests;
- no SDK upgrade churn coupling us to vendor releases.
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any, Literal, Protocol, runtime_checkable

import httpx


class Role(StrEnum):
    system = "system"
    user = "user"
    assistant = "assistant"


@dataclass(frozen=True, slots=True)
class ChatMessage:
    role: Role
    content: str


@dataclass(frozen=True, slots=True)
class Usage:
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0


@dataclass(frozen=True, slots=True)
class Chunk:
    """One streamed token chunk."""

    text: str
    finish_reason: str | None = None
    usage: Usage | None = None


@dataclass(frozen=True, slots=True)
class Completion:
    """Non-streamed completion."""

    text: str
    finish_reason: str | None
    usage: Usage
    raw: dict[str, Any] = field(default_factory=dict)


ResponseFormat = Literal["text", "json"]


@runtime_checkable
class Provider(Protocol):
    """Common interface for LLM providers."""

    name: str
    default_model: str

    async def complete(
        self,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
        response_format: ResponseFormat = "text",
        timeout_s: float = 25.0,
    ) -> Completion: ...

    def stream(
        self,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
        timeout_s: float = 25.0,
    ) -> AsyncIterator[Chunk]: ...


def make_http_client(*, timeout_s: float = 30.0) -> httpx.AsyncClient:
    """Shared client factory; HTTP/2, sane timeouts, connection pooling."""
    return httpx.AsyncClient(
        http2=True,
        timeout=httpx.Timeout(timeout_s, connect=5.0),
        limits=httpx.Limits(max_connections=64, max_keepalive_connections=16),
        headers={"User-Agent": "bubbles-api/5"},
    )
