"""``CurrentUser`` FastAPI dependency.

The dependency is the single auth path. Routes never parse Authorization
headers themselves.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, Header, Request

from bubbles.auth.jwt import JWKSCache, verify_token
from bubbles.core.errors import Forbidden, Unauthorized
from bubbles.core.logging import bind_request, current_request_id
from bubbles.settings import AppEnv, Settings, get_settings


@dataclass(frozen=True)
class CurrentUser:
    id: str
    email: str | None
    role: str | None


def _get_jwks(request: Request) -> JWKSCache:
    jwks: JWKSCache | None = getattr(request.app.state, "jwks", None)
    if jwks is None:
        # Outside lifespan (e.g. unit tests without an override) → fail closed.
        raise Unauthorized("Auth subsystem not ready.")
    return jwks


SettingsDep = Annotated[Settings, Depends(get_settings)]


async def current_user(
    request: Request,
    settings: SettingsDep,
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
) -> CurrentUser:
    if settings.debug_skip_auth and settings.app_env is AppEnv.development:
        # Local-only escape hatch (Settings validator guards production).
        return CurrentUser(id="dev-user", email=None, role="authenticated")

    if not authorization or not authorization.lower().startswith("bearer "):
        raise Unauthorized("Missing bearer token.")
    token = authorization[7:].strip()
    jwks = _get_jwks(request)
    claims = await verify_token(jwks, token)

    bind_request(request_id=current_request_id() or "-", user_id=claims.user_id)
    return CurrentUser(id=claims.user_id, email=claims.email, role=claims.role)


CurrentUserDep = Annotated[CurrentUser, Depends(current_user)]


def require_ownership(user: CurrentUser, owner_id: str) -> None:
    if user.id != owner_id:
        raise Forbidden("Resource is owned by another user.")
