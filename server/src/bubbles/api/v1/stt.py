"""Streaming STT WebSocket.

Client wire format:
    binary frame  → raw audio bytes (any container Whisper accepts)
    text frame    → JSON control: {"op": "flush"} or {"op": "close"}

Server emits text frames:
    {"type": "partial", "text": "..."}   — interim transcription
    {"type": "final",   "text": "..."}   — committed segment

The current implementation buffers up to N seconds of audio per flush and
hands the buffer to Groq Whisper as a one-shot transcription. Replace with
provider-side streaming once Groq exposes a WS endpoint.
"""

from __future__ import annotations

import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, status

from bubbles.auth.jwt import JWKSCache, verify_token
from bubbles.core.errors import Unauthorized, UpstreamUnavailable
from bubbles.core.logging import bind_request, get_logger, unbind_request
from bubbles.settings import Settings, get_settings
from bubbles.voice.stt import GroqWhisper

router = APIRouter(tags=["stt"])

log = get_logger(__name__)


_FLUSH_BYTES_HINT = 192_000  # ~12 s of 16 kHz mono 16-bit PCM


async def _verify_ws_token(websocket: WebSocket, token: str) -> str:
    jwks: JWKSCache | None = getattr(websocket.app.state, "jwks", None)
    if jwks is None:
        raise Unauthorized("Auth subsystem not ready.")
    claims = await verify_token(jwks, token)
    return claims.user_id


@router.websocket("/stt/stream")
async def stt_stream(websocket: WebSocket, token: str = "") -> None:
    settings: Settings = get_settings()
    if settings.groq_api_key is None:
        await websocket.close(code=status.WS_1011_INTERNAL_ERROR, reason="stt unavailable")
        return

    try:
        user_id = await _verify_ws_token(websocket, token)
    except Unauthorized:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="unauthorized")
        return

    await websocket.accept()
    bind_request(request_id="ws-stt", user_id=user_id)
    log.info("stt_ws_open", user=user_id)

    import httpx

    buffer = bytearray()
    try:
        async with httpx.AsyncClient(timeout=60.0) as http_client:
            whisper = GroqWhisper(
                api_key=settings.groq_api_key.get_secret_value(),
                client=http_client,
                model=settings.groq_whisper_model,
            )
            while True:
                msg = await websocket.receive()
                if msg["type"] == "websocket.disconnect":
                    break
                if "bytes" in msg and msg["bytes"] is not None:
                    buffer.extend(msg["bytes"])
                    if len(buffer) >= _FLUSH_BYTES_HINT:
                        await _flush(websocket, whisper, buffer)
                elif "text" in msg and msg["text"] is not None:
                    op = _parse_op(msg["text"])
                    if op == "flush":
                        await _flush(websocket, whisper, buffer)
                    elif op == "close":
                        break
    except WebSocketDisconnect:
        pass
    except UpstreamUnavailable as exc:
        log.warning("stt_ws_upstream", error=str(exc))
    finally:
        unbind_request()
        log.info("stt_ws_close", user=user_id)


def _parse_op(text: str) -> str:
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return ""
    if not isinstance(payload, dict):
        return ""
    return str(payload.get("op") or "")


async def _flush(websocket: WebSocket, whisper: GroqWhisper, buffer: bytearray) -> None:
    if not buffer:
        return
    audio = bytes(buffer)
    buffer.clear()
    try:
        transcript = await whisper.transcribe(audio, filename="chunk.wav", content_type="audio/wav")
    except UpstreamUnavailable as exc:
        await websocket.send_text(json.dumps({"type": "error", "message": str(exc)}))
        return
    if transcript.text:
        await websocket.send_text(json.dumps({"type": "final", "text": transcript.text}))
