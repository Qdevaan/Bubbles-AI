"""
Health & root endpoints — no auth, no rate-limiting.
"""

import time
from fastapi import APIRouter

from app.config import settings
from app.database import db
from app.services import vector_svc

router = APIRouter()

_SERVER_START_TIME = time.time()


@router.get("/")
def root():
    return {
        "status": "Bubbles Brain Online",
        "consultant_model": settings.CONSULTANT_MODEL,
        "wingman_model": settings.WINGMAN_MODEL,
    }


@router.get("/health")
def health_check():
    """Health check with DB, LLM, and embeddings validation."""
    is_healthy = True
    health_status = {
        "status": "healthy",
        "version": "2.0.0",
        "uptime": round(time.time() - _SERVER_START_TIME),
        "db": "unknown",
        "llm": "unknown",
        "embeddings": "unknown",
    }

    # 1. Database connectivity
    try:
        if db:
            db.table("profiles").select("id").limit(1).execute()
        health_status["db"] = "ok"
    except Exception as e:
        health_status["db"] = f"error: {str(e)[:80]}"
        is_healthy = False

    # 2. Embeddings model loaded
    try:
        if vector_svc.model is not None:
            health_status["embeddings"] = "ok"
        else:
            health_status["embeddings"] = "not loaded"
            is_healthy = False
    except Exception as e:
        health_status["embeddings"] = f"error: {str(e)[:80]}"
        is_healthy = False

    # 3. LLM (Groq) API key
    try:
        if settings.GROQ_KEY and len(settings.GROQ_KEY) > 10:
            health_status["llm"] = "ok"
        else:
            health_status["llm"] = "no key"
            is_healthy = False
    except Exception as e:
        health_status["llm"] = f"error: {str(e)[:80]}"
        is_healthy = False

    if not is_healthy:
        health_status["status"] = "degraded"
        from starlette.responses import JSONResponse
        return JSONResponse(content=health_status, status_code=503)
    return health_status
