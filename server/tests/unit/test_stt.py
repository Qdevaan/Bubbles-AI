"""Groq Whisper STT — wire-protocol tests."""

from __future__ import annotations

import httpx
import pytest
import respx

from bubbles.core.errors import UpstreamUnavailable
from bubbles.voice.stt import GroqWhisper


def _make() -> GroqWhisper:
    return GroqWhisper(api_key="k", client=httpx.AsyncClient(timeout=5.0))


@respx.mock
async def test_transcribe_parses_text() -> None:
    respx.post("https://api.groq.com/openai/v1/audio/transcriptions").mock(
        return_value=httpx.Response(
            200,
            json={"text": "  hello world  ", "language": "en", "duration": 1.23},
        )
    )
    out = await _make().transcribe(b"\x00\x01")
    assert out.text == "hello world"
    assert out.language == "en"
    assert out.duration_s == 1.23


@respx.mock
async def test_transcribe_5xx_raises() -> None:
    respx.post("https://api.groq.com/openai/v1/audio/transcriptions").mock(
        return_value=httpx.Response(503)
    )
    with pytest.raises(UpstreamUnavailable):
        await _make().transcribe(b"\x00")


async def test_transcribe_empty_raises() -> None:
    with pytest.raises(ValueError):
        await _make().transcribe(b"")
