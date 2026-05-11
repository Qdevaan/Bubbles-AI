"""Text-to-speech via Microsoft Edge TTS (free, no key)."""

from __future__ import annotations

from collections.abc import AsyncIterator
from dataclasses import dataclass

import edge_tts

from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger

log = get_logger(__name__)


@dataclass(frozen=True, slots=True)
class VoicePreset:
    name: str
    voice: str
    rate: str = "+0%"
    pitch: str = "+0Hz"


PRESETS: dict[str, VoicePreset] = {
    "default": VoicePreset("default", "en-US-AriaNeural"),
    "warm": VoicePreset("warm", "en-US-JennyNeural", rate="-5%"),
    "calm": VoicePreset("calm", "en-US-GuyNeural", rate="-7%", pitch="-2Hz"),
    "energetic": VoicePreset("energetic", "en-US-AriaNeural", rate="+8%"),
    "uk": VoicePreset("uk", "en-GB-SoniaNeural"),
}


def resolve_preset(name: str | None) -> VoicePreset:
    return PRESETS.get((name or "default").lower(), PRESETS["default"])


async def stream_mp3(
    text: str,
    *,
    preset: VoicePreset | None = None,
    voice: str | None = None,
) -> AsyncIterator[bytes]:
    if not text or not text.strip():
        raise ValueError("text is empty")
    chosen = preset if preset is not None else resolve_preset(voice)
    try:
        communicate = edge_tts.Communicate(
            text=text,
            voice=chosen.voice,
            rate=chosen.rate,
            pitch=chosen.pitch,
        )
        async for chunk in communicate.stream():
            if chunk.get("type") == "audio":
                data = chunk.get("data")
                if isinstance(data, bytes | bytearray) and data:
                    yield bytes(data)
    except Exception as exc:
        raise UpstreamUnavailable(f"edge-tts: {exc!s}") from exc
