"""TTS preset resolver + text guard."""

from __future__ import annotations

import pytest

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
