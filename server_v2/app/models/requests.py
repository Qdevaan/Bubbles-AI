"""
Pydantic request schemas — one place for all POST body models.
"""

from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field


# ── Session Endpoints ─────────────────────────────────────────────────────────

class StartSessionRequest(BaseModel):
    user_id: str = Field(..., min_length=1)
    mode: str = "live_wingman"
    target_entity_id: Optional[str] = None
    is_ephemeral: bool = False
    is_multiplayer: bool = False
    persona: str = "casual"
    device_id: Optional[str] = None
    session_type: Optional[str] = None
    idempotency_key: Optional[str] = None


class SaveSessionRequest(BaseModel):
    user_id: str
    transcript: str
    logs: List[Dict[str, Any]]
    is_ephemeral: bool = False
    idempotency_key: Optional[str] = None


class EndSessionRequest(BaseModel):
    session_id: str
    user_id: str
    idempotency_key: Optional[str] = None


# ── Consultant Endpoints ──────────────────────────────────────────────────────

class ConsultantRequest(BaseModel):
    user_id: str = Field(..., min_length=1, description="Supabase user UUID")
    question: str = Field(..., min_length=1, max_length=5000)
    session_id: Optional[str] = None
    mode: str = "consultant"
    persona: str = "casual"


class BatchConsultantRequest(BaseModel):
    user_id: str
    questions: List[str] = Field(..., min_length=1)
    mode: str = "casual"


# ── Wingman Endpoint ──────────────────────────────────────────────────────────

class WingmanRequest(BaseModel):
    user_id: str
    transcript: str
    session_id: Optional[str] = None
    speaker_role: str = "others"
    speaker_label: Optional[str] = None
    confidence: Optional[float] = None
    mode: str = Field("live_wingman", description="Session mode")
    persona: str = Field("casual", description="Persona tone")


# ── Entity Endpoints ──────────────────────────────────────────────────────────

class EntityQueryRequest(BaseModel):
    user_id: str = Field(..., min_length=1)
    entity_name: str = Field(..., min_length=1, max_length=200)


# ── Voice Endpoints ───────────────────────────────────────────────────────────

class VoiceCommandRequest(BaseModel):
    user_id: str = Field(..., min_length=1)
    command: str = Field(..., min_length=1, max_length=2000)


class TokenRequest(BaseModel):
    userId: str
    roomName: str = "default-room"


# ── Feedback ──────────────────────────────────────────────────────────────────

class FeedbackRequest(BaseModel):
    user_id: str = Field(..., min_length=1)
    session_id: Optional[str] = None
    session_log_id: Optional[str] = None
    consultant_log_id: Optional[str] = None
    feedback_type: str = Field(..., description="thumbs | star | text")
    value: Optional[int] = Field(None, ge=-1, le=5)
    comment: Optional[str] = Field(None, max_length=1000)
    idempotency_key: Optional[str] = None


# ── Error Response ────────────────────────────────────────────────────────────

class ErrorResponse(BaseModel):
    error: str                       # Machine-readable: "rate_limited", "auth_failed"
    message: str                     # Human-readable description
    details: Optional[Dict] = None   # Optional context (field name, retry_after, etc.)
    request_id: Optional[str] = None # Correlation ID from X-Request-ID header
