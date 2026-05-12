"""TTS preset resolver, text guard, and engine selection (ElevenLabs vs Edge)."""

from __future__ import annotations

from collections.abc import AsyncIterator

import pytest
from pydantic import SecretStr

from bubbles.settings import Settings, get_settings
from bubbles.voice import tts
from bubbles.voice.tts import PRESETS, resolve_preset, stream_mp3


def test_resolve_preset_known() -> None:
    assert resolve_preset("warm").voice == PRESETS["warm"].voice


def test_resolve_preset_unknown_falls_back() -> None:
    assert resolve_preset("alien").voice == PRESETS["default"].voice
    assert resolve_preset(None).voice == PRESETS["default"].voice


async def test_stream_mp3_rejects_empty() -> None:
    gen = stream_mp3("")
    with pytest.raises(ValueError):
        async for _ in gen:
            break


# --- ElevenLabs ↔ Edge-TTS selection --------------------------------------


def _settings(*, eleven_key: str | None) -> Settings:
    return get_settings().model_copy(
        update={"elevenlabs_api_key": SecretStr(eleven_key) if eleven_key else None}
    )


async def _edge_fake(text: str, preset: tts.VoicePreset) -> AsyncIterator[bytes]:
    yield b"EDGE"


async def _collect(it: AsyncIterator[bytes]) -> bytes:
    return b"".join([chunk async for chunk in it])


async def test_premium_voice_uses_elevenlabs(monkeypatch: pytest.MonkeyPatch) -> None:
    async def _eleven_fake(text: str, *, voice_id: str, api_key: str, model: str) -> bytes:
        assert api_key == "k" and voice_id
        return b"ELEVEN"

    monkeypatch.setattr(tts, "_elevenlabs_bytes", _eleven_fake)
    monkeypatch.setattr(tts, "_edge_stream", _edge_fake)
    out = await _collect(
        tts.synthesize_mp3("hi there", voice="premium", settings=_settings(eleven_key="k"))
    )
    assert out == b"ELEVEN"


async def test_elevenlabs_failure_falls_back_to_edge(monkeypatch: pytest.MonkeyPatch) -> None:
    async def _eleven_boom(text: str, *, voice_id: str, api_key: str, model: str) -> bytes:
        raise RuntimeError("429 quota")

    monkeypatch.setattr(tts, "_elevenlabs_bytes", _eleven_boom)
    monkeypatch.setattr(tts, "_edge_stream", _edge_fake)
    out = await _collect(
        tts.synthesize_mp3("hi", voice="premium", settings=_settings(eleven_key="k"))
    )
    assert out == b"EDGE"


async def test_no_key_uses_edge(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tts, "_edge_stream", _edge_fake)
    out = await _collect(
        tts.synthesize_mp3("hi", voice="premium", settings=_settings(eleven_key=None))
    )
    assert out == b"EDGE"


async def test_non_premium_voice_uses_edge_even_with_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tts, "_edge_stream", _edge_fake)
    out = await _collect(tts.synthesize_mp3("hi", voice="warm", settings=_settings(eleven_key="k")))
    assert out == b"EDGE"


async def test_synthesize_rejects_empty() -> None:
    with pytest.raises(ValueError, match="empty"):
        await _collect(
            tts.synthesize_mp3("   ", voice="default", settings=_settings(eleven_key=None))
        )
