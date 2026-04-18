"""
STT/TTS proxy routes.

GET  /stt/stream  — WebSocket proxy: Flutter ↔ this server ↔ Deepgram STT
POST /tts         — HTTP proxy: Flutter → this server → Deepgram TTS → audio bytes
"""

import asyncio

import httpx
from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import Response
from supabase import create_client
from websockets.asyncio.client import connect as ws_connect
from websockets.exceptions import ConnectionClosed

from app.config import settings

router = APIRouter()

_DEEPGRAM_STT_URL = (
    "wss://api.deepgram.com/v1/listen"
    "?smart_format=true&diarize=true&model=nova-2"
    "&encoding=linear16&sample_rate=16000&channels=1"
)
_DEEPGRAM_TTS_URL = "https://api.deepgram.com/v1/speak?model=aura-orpheus-en"


def _verify_jwt(token: str) -> str:
    """Validate Supabase JWT. Returns user_id on success, raises HTTPException on failure."""
    if not token:
        raise HTTPException(status_code=401, detail="Missing token")
    try:
        svc = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)
        user = svc.auth.get_user(token)
        return user.user.id
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")


# ── STT WebSocket Proxy ───────────────────────────────────────────────────────

@router.websocket("/stt/stream")
async def stt_stream(websocket: WebSocket, token: str = ""):
    """
    Bidirectional WebSocket proxy between Flutter client and Deepgram STT.
    Requires ?token=<supabase_jwt> query parameter.
    Closes with code 4001 if JWT is invalid.
    """
    # Validate JWT before accepting the connection
    try:
        _verify_jwt(token)
    except HTTPException:
        await websocket.close(code=4001, reason="Unauthorized")
        return

    await websocket.accept()

    if not settings.DEEPGRAM_API_KEY:
        await websocket.close(code=4002, reason="STT not configured on server")
        return

    try:
        async with ws_connect(
            _DEEPGRAM_STT_URL,
            extra_headers={"Authorization": f"Token {settings.DEEPGRAM_API_KEY}"},
        ) as deepgram_ws:

            async def client_to_deepgram():
                """Forward audio bytes from Flutter → Deepgram."""
                try:
                    async for message in websocket.iter_bytes():
                        await deepgram_ws.send(message)
                except (WebSocketDisconnect, Exception):
                    pass
                finally:
                    await deepgram_ws.close()

            async def deepgram_to_client():
                """Forward transcript JSON from Deepgram → Flutter."""
                try:
                    async for message in deepgram_ws:
                        await websocket.send_text(message)
                except (ConnectionClosed, WebSocketDisconnect, Exception):
                    pass

            await asyncio.gather(
                client_to_deepgram(),
                deepgram_to_client(),
                return_exceptions=True,
            )

    except Exception as exc:
        try:
            await websocket.send_json({"error": "upstream_disconnected", "detail": str(exc)})
        except Exception:
            pass
    finally:
        try:
            await websocket.close()
        except Exception:
            pass


# ── TTS HTTP Proxy ────────────────────────────────────────────────────────────

@router.post("/tts")
async def tts_proxy(request_body: dict, authorization: str = ""):
    """
    Proxy Deepgram TTS: receive {"text": "..."} from Flutter,
    forward to Deepgram /v1/speak, return audio bytes.
    Requires Authorization: Bearer <supabase_jwt> header.
    """
    token = authorization.removeprefix("Bearer ").strip()
    _verify_jwt(token)

    text = request_body.get("text", "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="text field is required")

    if not settings.DEEPGRAM_API_KEY:
        raise HTTPException(status_code=503, detail="TTS not configured on server")

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            _DEEPGRAM_TTS_URL,
            headers={
                "Authorization": f"Token {settings.DEEPGRAM_API_KEY}",
                "Content-Type": "application/json",
            },
            json={"text": text},
        )

    if resp.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"Deepgram TTS error: {resp.status_code}",
        )

    return Response(
        content=resp.content,
        media_type=resp.headers.get("content-type", "audio/mpeg"),
    )
