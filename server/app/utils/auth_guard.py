"""
JWT Auth Guard — FastAPI Depends() dependency for Supabase JWT verification.

Usage in routes:
    from app.utils.auth_guard import get_verified_user, VerifiedUser

    @router.post("/my_endpoint")
    async def my_endpoint(req: MyRequest, user: VerifiedUser = Depends(get_verified_user)):
        # user.user_id is cryptographically verified
        ...

Configuration:
    Set DEBUG_SKIP_AUTH=true in .env to bypass JWT verification during local
    development. This trusts the user_id from the request body directly.
    NEVER enable in production.
"""

import logging
from dataclasses import dataclass
from typing import Optional

from fastapi import Depends, Header, HTTPException, Request, status
from supabase import create_client

from app.config import settings

logger = logging.getLogger(__name__)


@dataclass
class VerifiedUser:
    """Container for the cryptographically verified Supabase user identity."""
    user_id: str
    email: Optional[str] = None


def _get_supabase_admin():
    """Create a Supabase admin client for token verification."""
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)


async def get_verified_user(
    request: Request,
    authorization: Optional[str] = Header(default=None),
) -> VerifiedUser:
    """
    FastAPI dependency that validates a Supabase JWT Bearer token.

    Flow:
      1. Reads `Authorization: Bearer <token>` header.
      2. If DEBUG_SKIP_AUTH is True: extracts user_id from request body (dev only).
      3. Otherwise: calls supabase.auth.get_user(token) to verify the JWT.
      4. Returns a VerifiedUser(user_id=...) on success.
      5. Raises HTTP 401 on any failure.
    """

    # ── Dev bypass mode ──────────────────────────────────────────────────────
    if settings.DEBUG_SKIP_AUTH:
        # In dev mode, trust the user_id from the request body
        try:
            body = await request.json()
            user_id = body.get("user_id") or body.get("userId", "")
            if not user_id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="DEBUG_SKIP_AUTH is active but no user_id found in request body.",
                )
            logger.debug("⚠️ AUTH BYPASSED (DEBUG_SKIP_AUTH=true) for user: %s", user_id)
            return VerifiedUser(user_id=user_id)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Could not parse request body in debug mode: {e}",
            )

    # ── Production JWT verification ──────────────────────────────────────────
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header. Expected: 'Authorization: Bearer <token>'",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Authorization format. Expected: 'Bearer <token>'",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = authorization[len("Bearer "):]
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Empty Bearer token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        supabase_admin = _get_supabase_admin()
        response = supabase_admin.auth.get_user(token)

        if not response or not response.user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token is invalid or expired.",
                headers={"WWW-Authenticate": "Bearer"},
            )

        user = response.user
        return VerifiedUser(
            user_id=str(user.id),
            email=getattr(user, "email", None),
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.warning("JWT verification failed: %s", e)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials.",
            headers={"WWW-Authenticate": "Bearer"},
        )
