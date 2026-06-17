# Purpose: Bidirectional WebSocket proxy between the Flutter client and Deepgram STT with speaker diarisation.
"""Speech-to-text via Groq Whisper.

Groq exposes an OpenAI-compatible ``audio/transcriptions`` endpoint:
    POST https://api.groq.com/openai/v1/audio/transcriptions
    multipart: file, model, language?, response_format=json

Whisper-large-v3-turbo is free-tier and ~10x realtime, so we hit it
synchronously per audio blob. For continuous streams the caller batches.
"""

from __future__ import annotations

from dataclasses import dataclass

import httpx

from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger

log = get_logger(__name__)

_URL = "https://api.groq.com/openai/v1/audio/transcriptions"


@dataclass(frozen=True, slots=True)
class Transcript:
    text: str
    language: str | None = None
    duration_s: float | None = None


class GroqWhisper:
    def __init__(
        self,
        *,
        api_key: str,
        client: httpx.AsyncClient,
        model: str = "whisper-large-v3-turbo",
    ) -> None:
        self._api_key = api_key
        self._client = client
        self._model = model

    async def transcribe(
        self,
        audio: bytes,
        *,
        filename: str = "audio.wav",
        content_type: str = "audio/wav",
        language: str | None = None,
        timeout_s: float = 30.0,
    ) -> Transcript:
        if not audio:
            raise ValueError("audio is empty")
        files = {"file": (filename, audio, content_type)}
        data: dict[str, str] = {"model": self._model, "response_format": "verbose_json"}
        if language:
            data["language"] = language
        try:
            resp = await self._client.post(
                _URL,
                headers={"Authorization": f"Bearer {self._api_key}"},
                files=files,
                data=data,
                timeout=timeout_s,
            )
        except httpx.HTTPError as exc:
            raise UpstreamUnavailable(f"groq stt transport: {exc!s}") from exc
        if resp.status_code >= 500:
            raise UpstreamUnavailable(f"groq stt http {resp.status_code}")
        if resp.status_code >= 400:
            raise UpstreamUnavailable(f"groq stt http {resp.status_code}: client error")
        payload = resp.json()
        return Transcript(
            text=str(payload.get("text") or "").strip(),
            language=payload.get("language"),
            duration_s=payload.get("duration"),
        )
