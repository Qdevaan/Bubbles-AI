"""Settings validation."""

from __future__ import annotations

import pytest

from bubbles.settings import AppEnv, Settings, get_settings


def test_dev_defaults() -> None:
    s = get_settings()
    assert s.app_env is AppEnv.development
    assert s.db_pool_min <= s.db_pool_max
    assert s.is_production is False


def test_debug_skip_auth_blocked_outside_dev(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("SENTRY_DSN", "https://example/1")
    monkeypatch.setenv("DEBUG_SKIP_AUTH", "true")
    with pytest.raises(ValueError, match="DEBUG_SKIP_AUTH"):
        Settings()


def test_production_requires_sentry(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.delenv("SENTRY_DSN", raising=False)
    with pytest.raises(ValueError, match="SENTRY_DSN"):
        Settings()
