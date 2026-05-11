"""Supabase JWT verification with cached JWKS.

JWKS is fetched once and cached in-process. On a ``kid`` miss we refresh
once. The fetch is rate-limited to prevent runaway when JWKS keeps churning.
"""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass
from typing import Any

import httpx
import jwt
from jwt import PyJWKClient
from jwt.exceptions import InvalidTokenError

from bubbles.core.errors import Unauthorized
from bubbles.core.logging import get_logger

log = get_logger(__name__)

_JWKS_TTL_S = 3600.0
_JWKS_REFRESH_COOLDOWN_S = 5.0


@dataclass(frozen=True)
class TokenClaims:
    user_id: str
    email: str | None
    role: str | None
    raw: dict[str, Any]


class JWKSCache:
    """Process-wide JWKS cache with cooldown-bounded refresh."""

    def __init__(self, jwks_url: str) -> None:
        self._url = jwks_url
        self._client: PyJWKClient | None = None
        self._loaded_at: float = 0.0
        self._last_refresh_attempt: float = 0.0
        self._lock = asyncio.Lock()

    async def get_signing_key(self, token: str) -> jwt.PyJWK:
        client = await self._ensure_client()
        try:
            return client.get_signing_key_from_jwt(token)
        except (InvalidTokenError, ValueError):
            await self._refresh()
            client = await self._ensure_client()
            return client.get_signing_key_from_jwt(token)

    async def _ensure_client(self) -> PyJWKClient:
        if self._client is not None and (time.monotonic() - self._loaded_at) < _JWKS_TTL_S:
            return self._client
        await self._refresh()
        assert self._client is not None
        return self._client

    async def _refresh(self) -> None:
        async with self._lock:
            now = time.monotonic()
            if now - self._last_refresh_attempt < _JWKS_REFRESH_COOLDOWN_S:
                return
            self._last_refresh_attempt = now
            # PyJWKClient is sync; offload the network call.
            self._client = await asyncio.to_thread(PyJWKClient, self._url)
            self._loaded_at = now
            log.info("jwks_refreshed")


async def warm_jwks(cache: JWKSCache, *, timeout_s: float = 5.0) -> None:
    """Best-effort prefetch at startup."""
    try:
        async with httpx.AsyncClient(timeout=timeout_s) as client:
            resp = await client.get(cache._url)
            resp.raise_for_status()
        await cache._refresh()
    except Exception as exc:
        log.warning("jwks_warm_failed", error=str(exc))


def _decode(token: str, signing_key: jwt.PyJWK) -> dict[str, Any]:
    try:
        decoded: dict[str, Any] = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256", "ES256", "HS256"],
            options={"require": ["exp", "sub"]},
            audience="authenticated",
        )
    except InvalidTokenError as exc:
        raise Unauthorized("Invalid token.") from exc
    return decoded


async def verify_token(jwks: JWKSCache, token: str) -> TokenClaims:
    if not token:
        raise Unauthorized("Missing token.")
    try:
        signing_key = await jwks.get_signing_key(token)
    except InvalidTokenError as exc:
        raise Unauthorized("Invalid token.") from exc
    claims = _decode(token, signing_key)
    sub = claims.get("sub")
    if not isinstance(sub, str):
        raise Unauthorized("Token missing subject.")
    return TokenClaims(
        user_id=sub,
        email=claims.get("email"),
        role=claims.get("role"),
        raw=claims,
    )
