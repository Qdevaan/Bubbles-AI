"""
Centralized configuration — all secrets and tunables in one place.
Reads from environment variables (loaded from .env by python-dotenv).
"""

import os
from dotenv import load_dotenv

# Try to load from root env folder first
root_env = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "env", ".env"))
if os.path.exists(root_env):
    load_dotenv(root_env)
else:
    # Fallback to local .env in server directory
    local_env = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".env"))
    load_dotenv(local_env)


class Settings:
    """Singleton holding every configurable value the server needs."""

    # ── Supabase ──────────────────────────────────────────────────────────────
    SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
    SUPABASE_KEY: str = os.getenv("SUPABASE_KEY", "")
    SUPABASE_SERVICE_KEY: str = os.getenv("SUPABASE_SERVICE_KEY", "")

    # ── Deepgram (Speech-to-Text) ─────────────────────────────────────────────
    DEEPGRAM_KEY: str = os.getenv("DEEPGRAM_KEY", "")

    # ── LiveKit (Real-time Audio/Video) ───────────────────────────────────────
    LIVEKIT_URL: str = os.getenv("LIVEKIT_URL", "")
    LIVEKIT_API_KEY: str = os.getenv("LIVEKIT_API_KEY", "")
    LIVEKIT_API_SECRET: str = os.getenv("LIVEKIT_API_SECRET", "")

    # ── Groq (LLM Inference) ─────────────────────────────────────────────────
    GROQ_KEY: str = os.getenv("GROQ_API_KEY", "")

    # ── AI Model Names ────────────────────────────────────────────────────────
    EMBEDDING_MODEL: str = "all-MiniLM-L6-v2"
    CONSULTANT_MODEL: str = "llama-3.3-70b-versatile"   # Detailed, accurate
    WINGMAN_MODEL: str = "llama-3.1-8b-instant"          # Fast, low-latency

    # ── Server ────────────────────────────────────────────────────────────────
    HOST: str = "0.0.0.0"
    PORT: int = 8000

    # ── CORS ──────────────────────────────────────────────────────────────────
    ALLOWED_ORIGINS: str = os.getenv("ALLOWED_ORIGINS", "*")


settings = Settings()

# Expose LiveKit env vars so the SDK picks them up automatically
os.environ["LIVEKIT_URL"] = settings.LIVEKIT_URL
os.environ["LIVEKIT_API_KEY"] = settings.LIVEKIT_API_KEY
os.environ["LIVEKIT_API_SECRET"] = settings.LIVEKIT_API_SECRET
