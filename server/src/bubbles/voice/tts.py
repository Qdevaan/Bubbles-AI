"""Text-to-speech.

Free Microsoft Edge TTS by default (no key). When ``ELEVENLABS_API_KEY`` is
configured, voice presets that carry an ElevenLabs voice id are synthesised
there instead; any failure transparently falls back to Edge-TTS.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from dataclasses import dataclass

import edge_tts
import httpx

from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.settings import Settings

log = get_logger(__name__)

_ELEVENLABS_TTS_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
_ELEVENLABS_TIMEOUT_S = 30.0


@dataclass(frozen=True, slots=True)
class VoicePreset:
    name: str
    voice: str  # Edge-TTS voice short name
    rate: str = "+0%"
    pitch: str = "+0Hz"
    elevenlabs_voice_id: str | None = None  # set → eligible for premium synthesis


PRESETS: dict[str, VoicePreset] = {
    "default": VoicePreset("default", "en-US-AriaNeural"),
    "warm": VoicePreset("warm", "en-US-JennyNeural", rate="-5%"),
    "calm": VoicePreset("calm", "en-US-GuyNeural", rate="-7%", pitch="-2Hz"),
    "energetic": VoicePreset("energetic", "en-US-AriaNeural", rate="+8%"),
    "uk": VoicePreset("uk", "en-GB-SoniaNeural"),
    # Premium presets — the Edge-TTS voice is the fallback if ElevenLabs is
    # unavailable. ids are ElevenLabs' public stock voices ("Rachel", "Adam").
    "premium": VoicePreset(
        "premium", "en-US-AriaNeural", elevenlabs_voice_id="21m00Tcm4TlvDq8ikWAM"
    ),
    "premium-male": VoicePreset(
        "premium-male", "en-US-GuyNeural", elevenlabs_voice_id="pNInz6obpgDQGcFmaJgB"
    ),
}


def resolve_preset(name: str | None) -> VoicePreset:
    return PRESETS.get((name or "default").lower(), PRESETS["default"])


async def _edge_stream(text: str, preset: VoicePreset) -> AsyncIterator[bytes]:
    try:
        communicate = edge_tts.Communicate(
            text=text, voice=preset.voice, rate=preset.rate, pitch=preset.pitch
        )
        async for chunk in communicate.stream():
            if chunk.get("type") == "audio":
                data = chunk.get("data")
                if isinstance(data, bytes | bytearray) and data:
                    yield bytes(data)
    except Exception as exc:
        raise UpstreamUnavailable(f"edge-tts: {exc!s}") from exc


async def _elevenlabs_bytes(text: str, *, voice_id: str, api_key: str, model: str) -> bytes:
    """One-shot (buffered) ElevenLabs synthesis — lets us fall back cleanly on error."""
    async with httpx.AsyncClient(timeout=_ELEVENLABS_TIMEOUT_S) as client:
        resp = await client.post(
            _ELEVENLABS_TTS_URL.format(voice_id=voice_id),
            headers={"xi-api-key": api_key, "accept": "audio/mpeg"},
            json={"text": text, "model_id": model},
        )
        resp.raise_for_status()
        return resp.content


async def stream_mp3(
    text: str, *, preset: VoicePreset | None = None, voice: str | None = None
) -> AsyncIterator[bytes]:
    """Edge-TTS only. Routes should call ``synthesize_mp3`` (handles ElevenLabs)."""
    if not text or not text.strip():
        raise ValueError("text is empty")
    chosen = preset if preset is not None else resolve_preset(voice)
    async for chunk in _edge_stream(text, chosen):
        yield chunk


async def synthesize_mp3(
    text: str, *, voice: str | None, settings: Settings
) -> AsyncIterator[bytes]:
    """Synthesise ``text`` to MP3, using ElevenLabs for premium presets when keyed.

    On any ElevenLabs error (no key, bad voice, quota, network) this transparently
    falls back to Edge-TTS — the caller never has to know which engine ran.
    """
    if not text or not text.strip():
        raise ValueError("text is empty")
    preset = resolve_preset(voice)
    key = settings.elevenlabs_api_key
    if key is not None and preset.elevenlabs_voice_id:
        try:
            audio = await _elevenlabs_bytes(
                text,
                voice_id=preset.elevenlabs_voice_id,
                api_key=key.get_secret_value(),
                model=settings.elevenlabs_model,
            )
            log.info("tts_elevenlabs", voice_id=preset.elevenlabs_voice_id, bytes=len(audio))
            yield audio
            return
        except Exception as exc:
            log.warning("tts_elevenlabs_failed_fallback_edge", error=str(exc))
    async for chunk in _edge_stream(text, preset):
        yield chunk
