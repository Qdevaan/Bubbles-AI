"""Voice routes — process_audio, tts, getToken, voice_command."""

from __future__ import annotations

import json

from fastapi import APIRouter, File, Form, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, ConfigDict, Field

from bubbles.ai.providers.base import ChatMessage, Role
from bubbles.auth.current_user import CurrentUserDep
from bubbles.core.errors import BadRequest, UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.deps import RouterDep
from bubbles.settings import Settings, get_settings
from bubbles.voice import livekit as livekit_helper
from bubbles.voice.stt import GroqWhisper
from bubbles.voice.tts import resolve_preset, stream_mp3

router = APIRouter(tags=["voice"])

log = get_logger(__name__)


class _Base(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class TokenRequest(_Base):
    name: str | None = None
    ttl_minutes: int = Field(default=60, ge=1, le=24 * 60)


class TokenResponse(_Base):
    token: str
    room: str


class TTSRequest(_Base):
    text: str = Field(..., min_length=1, max_length=4_000)
    voice: str | None = None


class VoiceCommandRequest(_Base):
    text: str = Field(..., min_length=1, max_length=2_000)


class VoiceCommandResponse(_Base):
    intent: str
    args: dict[str, str | None]
    response_text: str


@router.post("/getToken", response_model=TokenResponse)
async def get_token(body: TokenRequest, user: CurrentUserDep) -> TokenResponse:
    settings: Settings = get_settings()
    if (
        settings.livekit_api_key is None
        or settings.livekit_api_secret is None
        or settings.livekit_url is None
    ):
        raise UpstreamUnavailable("LiveKit not configured")
    token = livekit_helper.issue_token(
        api_key=settings.livekit_api_key.get_secret_value(),
        api_secret=settings.livekit_api_secret.get_secret_value(),
        user_id=user.id,
        name=body.name,
        ttl_minutes=body.ttl_minutes,
    )
    return TokenResponse(token=token, room=livekit_helper.make_room_name(user.id))


@router.post("/process_audio")
async def process_audio(
    user: CurrentUserDep,
    file: UploadFile = File(...),
    language: str | None = Form(default=None),
) -> dict[str, object]:
    settings: Settings = get_settings()
    if settings.groq_api_key is None:
        raise UpstreamUnavailable("STT provider not configured")
    audio = await file.read()
    if not audio:
        raise BadRequest("audio file is empty")

    import httpx

    async with httpx.AsyncClient(timeout=60.0) as client:
        whisper = GroqWhisper(
            api_key=settings.groq_api_key.get_secret_value(),
            client=client,
            model=settings.groq_whisper_model,
        )
        transcript = await whisper.transcribe(
            audio,
            filename=file.filename or "audio.wav",
            content_type=file.content_type or "audio/wav",
            language=language,
        )
    log.info("process_audio_done", user=user.id, len=len(transcript.text))
    return {
        "text": transcript.text,
        "language": transcript.language,
        "duration_s": transcript.duration_s,
    }


@router.post("/tts")
async def tts(body: TTSRequest, user: CurrentUserDep) -> StreamingResponse:
    preset = resolve_preset(body.voice)
    log.info("tts_request", user=user.id, voice=preset.voice, chars=len(body.text))
    return StreamingResponse(
        stream_mp3(body.text, preset=preset),
        media_type="audio/mpeg",
        headers={"Cache-Control": "no-cache"},
    )


_VOICE_INTENT_PROMPT = (
    "Classify the user's voice command. Return strict JSON of the form: "
    '{"intent": "...", "args": {...}, "response_text": "..."}. '
    "intent ∈ {start_session, end_session, ask_consultant, ask_entity, "
    "save_note, set_reminder, settings, unknown}. "
    "response_text is what the assistant should say back."
)


@router.post("/voice_command", response_model=VoiceCommandResponse)
async def voice_command(
    body: VoiceCommandRequest,
    user: CurrentUserDep,
    llm_router: RouterDep,
) -> VoiceCommandResponse:
    completion = await llm_router.complete(
        "wingman.json",
        [
            ChatMessage(role=Role.system, content=_VOICE_INTENT_PROMPT),
            ChatMessage(role=Role.user, content=body.text),
        ],
        response_format="json",
    )
    try:
        payload = json.loads(completion.text)
    except json.JSONDecodeError as exc:
        raise UpstreamUnavailable(f"voice intent parse: {exc!s}") from exc
    if not isinstance(payload, dict):
        raise UpstreamUnavailable("voice intent payload not an object")

    intent = str(payload.get("intent") or "unknown").strip() or "unknown"
    args_raw = payload.get("args") or {}
    args: dict[str, str | None] = (
        {str(k): (str(v) if v is not None else None) for k, v in args_raw.items()}
        if isinstance(args_raw, dict)
        else {}
    )
    response_text = str(payload.get("response_text") or "").strip()
    log.info("voice_command", user=user.id, intent=intent)
    return VoiceCommandResponse(intent=intent, args=args, response_text=response_text)
