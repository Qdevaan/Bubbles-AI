"""Sentry initialisation.

No-op when DSN is unset. Production deploys must set DSN — Settings
validates this for ``APP_ENV=production``.
"""

from __future__ import annotations

import sentry_sdk
from sentry_sdk.integrations.asyncio import AsyncioIntegration
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.starlette import StarletteIntegration

from bubbles import __version__
from bubbles.core.logging import get_logger
from bubbles.settings import Settings

log = get_logger(__name__)

_configured = False


def configure_sentry(settings: Settings) -> None:
    """Idempotent. Safe to call multiple times — second call is a no-op."""
    global _configured
    if _configured or settings.sentry_dsn is None:
        return
    sentry_sdk.init(
        dsn=settings.sentry_dsn.get_secret_value(),
        environment=settings.app_env.value,
        release=__version__,
        traces_sample_rate=settings.sentry_traces_sample_rate,
        send_default_pii=False,
        attach_stacktrace=True,
        integrations=[
            StarletteIntegration(transaction_style="endpoint"),
            FastApiIntegration(transaction_style="endpoint"),
            AsyncioIntegration(),
        ],
    )
    _configured = True
    log.info("sentry_configured", env=settings.app_env.value)
