"""
SlowAPI rate limiter.
Uses a compound key: user_id (from JWT state) + endpoint path for authenticated
routes; falls back to IP for unauthenticated endpoints.
"""

from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address


def _get_rate_limit_key(request: Request) -> str:
    """
    Compound key: user_id:path for authenticated requests, IP:path otherwise.
    Prevents bypassing per-user limits with multiple IPs (VPN, mobile data).
    """
    user = getattr(request.state, "verified_user", None)
    if user and getattr(user, "user_id", None):
        return f"user:{user.user_id}:{request.url.path}"
    ip = request.client.host if request.client else "unknown"
    return f"ip:{ip}:{request.url.path}"


limiter = Limiter(key_func=_get_rate_limit_key)
