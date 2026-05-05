"""
Voice routes — voice command parsing, LiveKit token generation, and speaker enrollment.
Records audit logs for voice commands and enrollments.
"""

import asyncio
import json
import os
import tempfile
from datetime import datetime

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile

from app.config import settings
from app.models.requests import VoiceCommandRequest, TokenRequest
from app.services import graph_svc, vector_svc, brain_svc, session_svc, audit_svc
from app.utils.rate_limit import limiter
from app.utils.text_sanitizer import sanitize_input
from livekit import api

router = APIRouter()


# ══════════════════════════════════════════════════════════════════════════════
# POST /process_audio  (audio chunk → transcript + wingman advice)
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/process_audio")
@limiter.limit("30/minute")
async def process_audio(
    request: Request,
    user_id: str = Form(...),
    session_id: str = Form(None),
    speaker_role: str = Form("others"),
    file: UploadFile = File(...),
):
    """
    Accept a short audio chunk, transcribe via Deepgram, run wingman advice,
    and return {"transcript": "...", "suggestion": "..."}.

    Used by the Flutter live wingman screen for real-time audio-based input.
    Falls back gracefully if Deepgram is not configured.
    """
    import httpx

    suffix = os.path.splitext(file.filename or "")[1] or ".m4a"
    tmp_path = None
    transcript = ""

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            contents = await file.read()
            tmp.write(contents)
            tmp_path = tmp.name

        # ── Transcribe via Deepgram ───────────────────────────────────────────
        if settings.DEEPGRAM_API_KEY:
            try:
                async with httpx.AsyncClient(timeout=20.0) as client:
                    with open(tmp_path, "rb") as audio_file:
                        audio_bytes = audio_file.read()
                    dg_resp = await client.post(
                        "https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true",
                        headers={
                            "Authorization": f"Token {settings.DEEPGRAM_API_KEY}",
                            "Content-Type": "audio/m4a",
                        },
                        content=audio_bytes,
                    )
                    if dg_resp.status_code == 200:
                        dg_data = dg_resp.json()
                        transcript = (
                            dg_data.get("results", {})
                            .get("channels", [{}])[0]
                            .get("alternatives", [{}])[0]
                            .get("transcript", "")
                            .strip()
                        )
            except Exception as e:
                print(f"⚠️ Deepgram transcription error: {e}")

        if not transcript:
            return {"transcript": "", "suggestion": ""}

        # ── Get wingman advice ────────────────────────────────────────────────
        suggestion = ""
        role = speaker_role if speaker_role in ("user", "others") else "others"
        if role == "others":
            try:
                def _ctx():
                    graph_svc.load_graph(user_id)
                    return graph_svc.find_context(user_id, transcript)

                g_ctx, v_ctx = await asyncio.gather(
                    asyncio.to_thread(_ctx),
                    asyncio.to_thread(vector_svc.search_memory, user_id, transcript),
                )
                result = await brain_svc.get_wingman_advice(
                    user_id, transcript, g_ctx, v_ctx, "live_wingman", "casual",
                )
                suggestion = result.get("answer", "")
            except Exception as e:
                print(f"⚠️ Wingman advice error in process_audio: {e}")

        return {"transcript": transcript, "suggestion": suggestion}

    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Audio processing failed: {exc}")
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)


# ══════════════════════════════════════════════════════════════════════════════
# POST /getToken  (LiveKit JWT)
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/getToken")
@limiter.limit("15/minute")
async def get_token(request: Request, req: TokenRequest):
    """Generate a LiveKit JWT token for a user to join a room."""
    token = api.AccessToken(settings.LIVEKIT_API_KEY, settings.LIVEKIT_API_SECRET)
    token.with_identity(req.userId)
    token.with_name(req.userId)
    token.with_grants(
        api.VideoGrants(
            room_join=True, room=req.roomName,
            can_publish=True, can_subscribe=True,
        )
    )
    jwt_token = token.to_jwt()
    return {"token": jwt_token, "url": settings.LIVEKIT_URL}


# ══════════════════════════════════════════════════════════════════════════════
# POST /voice_command
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/voice_command")
@limiter.limit("15/minute")
async def voice_command(request: Request, req: VoiceCommandRequest):
    """Parse a natural language voice command and route to the appropriate action."""
    user_id = req.user_id
    command = sanitize_input(req.command.strip().lower())

    print(f"🎙️ Voice Command from {user_id}: '{command}'")

    client_ip = request.client.host if request.client else None
    audit_svc.log(
        user_id, "voice_command_received",
        entity_type="voice_command",
        details={"command": command[:200]},
        ip_address=client_ip,
    )

    # 1. Use LLM to classify intent
    try:
        intent_prompt = (
            "You are a voice command parser for an app called Bubbles. "
            "Classify the user's command into ONE of these intents:\n"
            "1. 'start_session' - User wants to start a new live wingman session\n"
            "2. 'ask_consultant' - User wants to ask a question about past sessions or general advice\n"
            "3. 'view_sessions' - User wants to see session history\n"
            "4. 'go_home' - User wants to go to the home screen\n"
            "5. 'general_chat' - User is just chatting or the intent is unclear\n\n"
            'Return JSON ONLY: {"intent": "<intent>", "query": "<extracted question if ask_consultant, else empty>"}'
        )
        completion = brain_svc.client.chat.completions.create(
            messages=[
                {"role": "system", "content": intent_prompt},
                {"role": "user", "content": command},
            ],
            model=settings.WINGMAN_MODEL,
            temperature=0.2,
            max_tokens=100,
            response_format={"type": "json_object"},
        )
        intent_data = json.loads(completion.choices[0].message.content)
        intent = intent_data.get("intent", "general_chat")
        query = intent_data.get("query", "")
    except Exception as e:
        print(f"❌ Voice Command: Intent parsing failed: {e}")
        intent = "general_chat"
        query = command

    audit_svc.log(
        user_id, "voice_command_parsed",
        entity_type="voice_command",
        details={"intent": intent, "query": query[:200]},
    )

    # 2. Route based on intent
    if intent == "start_session":
        return {"action": "navigate", "target": "/new-session", "response": "Starting a new live session for you. Let's go!"}

    elif intent == "view_sessions":
        return {"action": "navigate", "target": "/sessions", "response": "Here are your past sessions."}

    elif intent == "go_home":
        return {"action": "navigate", "target": "/home", "response": "Taking you home."}

    elif intent == "ask_consultant":
        question = query if query else command
        try:
            vc_session_id = session_svc.create_session_record(
                user_id,
                title=f"Voice Consultant {datetime.now().strftime('%Y-%m-%d %H:%M')}",
                mode="consultant",
            )

            def _vc_graph_ctx():
                graph_svc.load_graph(user_id)
                return graph_svc.find_context(user_id, question, top_k=10)

            g_ctx, v_ctx, h_ctx, s_ctx = await asyncio.gather(
                asyncio.to_thread(_vc_graph_ctx),
                asyncio.to_thread(vector_svc.search_memory, user_id, question),
                asyncio.to_thread(session_svc.fetch_consultant_history, user_id, 5),
                asyncio.to_thread(session_svc.fetch_session_summaries, user_id, 3),
            )

            result = await brain_svc.ask_consultant(
                user_id, question, h_ctx, g_ctx, v_ctx, session_summaries=s_ctx,
            )
            answer = result.get("answer", "")
            await asyncio.to_thread(
                session_svc.log_consultant_qa,
                user_id, question, answer, session_id=vc_session_id,
                model_used=result.get("model_used"),
                latency_ms=result.get("latency_ms"),
                tokens_used=result.get("tokens_used"),
            )
            await asyncio.to_thread(session_svc.end_session, vc_session_id, summary=f"Q: {question[:100]}")
            await asyncio.to_thread(graph_svc.save_graph, user_id)

            await asyncio.to_thread(
                session_svc.update_session_token_usage,
                vc_session_id,
                tokens_prompt=result.get("tokens_prompt", 0),
                tokens_completion=result.get("tokens_completion", 0),
            )

            return {"action": "speak", "target": None, "response": answer}
        except Exception as e:
            print(f"❌ Voice Command: Consultant query failed: {e}")
            return {"action": "speak", "target": None, "response": "I had trouble looking that up. Can you try again?"}
    else:
        try:
            chat_completion = brain_svc.client.chat.completions.create(
                messages=[
                    {"role": "system", "content": "You are Bubbles, a friendly AI assistant. Keep responses short, warm, and conversational (1-2 sentences max)."},
                    {"role": "user", "content": command},
                ],
                model=settings.WINGMAN_MODEL,
                temperature=0.7,
                max_tokens=80,
            )
            response = chat_completion.choices[0].message.content.strip()
            return {"action": "speak", "target": None, "response": response}
        except Exception:
            return {"action": "speak", "target": None, "response": "Hey! I'm here to help. What can I do for you?"}


# ══════════════════════════════════════════════════════════════════════════════
# POST /enroll  (voice enrollment)
# ══════════════════════════════════════════════════════════════════════════════

_speaker_model = None

def _get_speaker_model():
    global _speaker_model
    if _speaker_model is None:
        from speechbrain.inference.speaker import EncoderClassifier
        _speaker_model = EncoderClassifier.from_hparams(
            source="speechbrain/spkrec-ecapa-voxceleb",
            savedir="pretrained_models/spkrec-ecapa-voxceleb",
        )
    return _speaker_model


@router.post("/enroll")
@limiter.limit("5/minute")
async def enroll_voice(
    request: Request,
    user_id: str = Form(...),
    user_name: str = Form(...),
    file: UploadFile = File(...),
):
    """Enroll a speaker embedding via ECAPA-TDNN model."""
    import torch
    import torchaudio

    suffix = os.path.splitext(file.filename or "")[1] or ".m4a"
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            contents = await file.read()
            tmp.write(contents)
            tmp_path = tmp.name

        model = await asyncio.to_thread(_get_speaker_model)

        def _embed():
            waveform, sr = torchaudio.load(tmp_path)
            if sr != 16000:
                waveform = torchaudio.transforms.Resample(orig_freq=sr, new_freq=16000)(waveform)
            if waveform.shape[0] > 1:
                waveform = waveform.mean(dim=0, keepdim=True)
            with torch.no_grad():
                emb = model.encode_batch(waveform)
            return emb.squeeze().tolist()

        embedding = await asyncio.to_thread(_embed)

        from supabase import create_client
        svc_client = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)

        existing = svc_client.table("voice_enrollments").select(
            "samples_count"
        ).eq("user_id", user_id).maybe_single().execute()
        current_count = 0
        if existing.data:
            current_count = existing.data.get("samples_count", 0) or 0

        svc_client.table("voice_enrollments").upsert(
            {
                "user_id": user_id,
                "embedding": embedding,
                "model_version": "v1",
                "samples_count": current_count + 1,
            },
            on_conflict="user_id",
        ).execute()

        audit_svc.log(
            user_id, "voice_enrolled",
            entity_type="voice_enrollment",
            details={"user_name": user_name, "samples_count": current_count + 1},
        )

        return {"status": "enrolled", "user_id": user_id, "user_name": user_name}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Voice enrollment failed: {exc}")
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)


# ══════════════════════════════════════════════════════════════════════════════
# POST /identify_speaker  (compare audio against enrolled voiceprint)
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/identify_speaker")
@limiter.limit("120/minute")
async def identify_speaker(
    request: Request,
    user_id: str = Form(...),
    file: UploadFile = File(...),
):
    """
    Compare uploaded audio against the user's enrolled ECAPA-TDNN embedding.
    Returns {"identity": "user"|"other"|"unknown", "confidence": float}.
    'unknown' means no enrollment exists for this user_id.
    """
    import torch
    import torchaudio
    import torch.nn.functional as F

    from supabase import create_client
    svc_client = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)

    enrolled = svc_client.table("voice_enrollments").select(
        "embedding"
    ).eq("user_id", user_id).maybe_single().execute()

    if not enrolled.data:
        return {"identity": "unknown", "confidence": 0.0}

    enrolled_vec = torch.tensor(enrolled.data["embedding"], dtype=torch.float32)

    suffix = os.path.splitext(file.filename or "")[1] or ".m4a"
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            contents = await file.read()
            tmp.write(contents)
            tmp_path = tmp.name

        model = await asyncio.to_thread(_get_speaker_model)

        def _embed():
            waveform, sr = torchaudio.load(tmp_path)
            if sr != 16000:
                waveform = torchaudio.transforms.Resample(orig_freq=sr, new_freq=16000)(waveform)
            if waveform.shape[0] > 1:
                waveform = waveform.mean(dim=0, keepdim=True)
            with torch.no_grad():
                emb = model.encode_batch(waveform)
            return emb.squeeze()

        query_vec = await asyncio.to_thread(_embed)

        similarity = F.cosine_similarity(
            enrolled_vec.unsqueeze(0), query_vec.unsqueeze(0)
        ).item()

        # Threshold tuned for ECAPA-TDNN on VoxCeleb — adjust if needed
        _THRESHOLD = 0.75
        identity = "user" if similarity >= _THRESHOLD else "other"

        return {"identity": identity, "confidence": round(similarity, 4)}

    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Speaker identification failed: {exc}")
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)
