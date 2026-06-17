# Purpose: Module: settings.
"""Application settings.

Frozen pydantic-settings model. One instance per process, cached.
Loaded from environment + .env. Required fields fail fast at startup.
"""

from __future__ import annotations

from enum import StrEnum
from functools import lru_cache
from typing import Annotated, Self

from pydantic import AnyHttpUrl, Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class AppEnv(StrEnum):
    development = "development"
    staging = "staging"
    production = "production"


class LogLevel(StrEnum):
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"


class Settings(BaseSettings):
    """Frozen, immutable application settings."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        frozen=True,
        case_sensitive=False,
    )

    # Runtime
    app_env: AppEnv = AppEnv.development
    log_level: LogLevel = LogLevel.INFO
    host: str = "0.0.0.0"  # noqa: S104 — bound at the proxy layer in prod
    port: int = 8000
    request_body_limit: int = 2 * 1024 * 1024  # 2 MB
    audio_body_limit: int = 10 * 1024 * 1024  # 10 MB
    request_timeout_s: float = 30.0

    # Auth + DB
    supabase_url: AnyHttpUrl
    supabase_service_key: SecretStr
    supabase_jwks_url: AnyHttpUrl
    database_url: SecretStr  # asyncpg DSN to PgBouncer (port 6543)
    db_pool_min: int = 2
    db_pool_max: int = 10
    db_command_timeout_s: float = 10.0

    # Redis
    redis_url: SecretStr = SecretStr("redis://localhost:6379/0")

    # AI providers
    gemini_api_key: SecretStr | None = None
    cerebras_api_key: SecretStr | None = None
    groq_api_key: SecretStr | None = None
    openrouter_api_key: SecretStr | None = None
    gemini_consultant_model: str = "gemini-2.5-flash"
    cerebras_wingman_model: str = "gpt-oss-120b"
    cerebras_glm_model: str = "zai-glm-4.7"
    groq_wingman_model: str = "llama-3.1-8b-instant"
    groq_quality_model: str = "llama-3.3-70b-versatile"
    groq_whisper_model: str = "whisper-large-v3-turbo"
    openrouter_model: str = "meta-llama/llama-3.3-70b-instruct:free"
    embedding_model: str = "text-embedding-004"

    # Provider budgets
    llm_call_timeout_s: float = 25.0
    llm_token_budget: int = 8000
    llm_breaker_error_rate: float = 0.5
    llm_breaker_window_s: int = 30

    # Voice
    livekit_url: str | None = None
    livekit_api_key: SecretStr | None = None
    livekit_api_secret: SecretStr | None = None
    # Optional premium TTS — when set, "premium" voice presets use ElevenLabs;
    # everything else (and any ElevenLabs failure) falls back to free Edge-TTS.
    elevenlabs_api_key: SecretStr | None = None
    elevenlabs_model: str = "eleven_multilingual_v2"

    # Push
    firebase_credentials_json: SecretStr | None = None

    # Observability
    sentry_dsn: SecretStr | None = None
    otel_exporter_otlp_endpoint: AnyHttpUrl | None = None
    logtail_source_token: SecretStr | None = None
    sentry_traces_sample_rate: float = 0.1

    # Dev escape hatch — never allow in non-dev envs
    debug_skip_auth: Annotated[bool, Field(default=False)]

    @model_validator(mode="after")
    def _enforce_invariants(self) -> Self:
        if self.debug_skip_auth and self.app_env is not AppEnv.development:
            raise ValueError("DEBUG_SKIP_AUTH is forbidden outside APP_ENV=development")
        if self.db_pool_min < 1 or self.db_pool_max < self.db_pool_min:
            raise ValueError("invalid DB pool sizes")
        if self.app_env is AppEnv.production and self.sentry_dsn is None:
            # Hard requirement in prod; surface early.
            raise ValueError("SENTRY_DSN required in production")
        return self

    @property
    def is_production(self) -> bool:
        return self.app_env is AppEnv.production


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the process-wide Settings instance.

    Cached so repeated `Depends(get_settings)` is free. The cache key is
    nothing, so a single instance lives for the process. Tests clear via
    `get_settings.cache_clear()`.
    """
    return Settings()
