"""
Centralized configuration — pydantic-settings BaseSettings.
Missing required fields (SUPABASE_URL, SUPABASE_SERVICE_KEY, GROQ_API_KEY)
raise a clear ValidationError at startup, not silently at request time.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file="../../../env/.env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ── Supabase (required) ───────────────────────────────────────────────────
    SUPABASE_URL: str
    SUPABASE_SERVICE_KEY: str
    SUPABASE_KEY: str = ""          # Anon key — kept for reference, not used by server

    # ── LLM (required) ────────────────────────────────────────────────────────
    GROQ_API_KEY: str

    # ── Additional LLM providers (optional) ──────────────────────────────────
    CEREBRAS_API_KEY: str = ""
    GEMINI_API_KEY: str = ""

    # ── Voice / Video ─────────────────────────────────────────────────────────
    DEEPGRAM_API_KEY: str = ""
    LIVEKIT_URL: str = ""
    LIVEKIT_API_KEY: str = ""
    LIVEKIT_API_SECRET: str = ""

    # ── Session Store ─────────────────────────────────────────────────────────
    # Native Redis URL: rediss://default:<password>@<host>:6379
    # NOT the Upstash REST URL (https://...)
    REDIS_URL: str = ""

    # ── Auth ──────────────────────────────────────────────────────────────────
    # NEVER set true in production
    DEBUG_SKIP_AUTH: bool = False

    # ── CORS ──────────────────────────────────────────────────────────────────
    ALLOWED_ORIGINS: str = "*"

    # ── App Environment ───────────────────────────────────────────────────────
    APP_ENV: str = "development"    # development | staging | production
    SELF_URL: str = ""              # Server's own public URL (for health self-ping)

    # ── Server ────────────────────────────────────────────────────────────────
    HOST: str = "0.0.0.0"
    PORT: int = 8000

    # ── AI Model Names ────────────────────────────────────────────────────────
    EMBEDDING_MODEL: str = "all-MiniLM-L6-v2"
    CONSULTANT_MODEL: str = "llama-3.3-70b-versatile"
    WINGMAN_MODEL: str = "llama-3.1-8b-instant"


settings = Settings()
