# Purpose: Generates signed LiveKit access tokens for Wingman real-time voice room sessions.
"""LiveKit access tokens.

Wraps the official ``livekit-api`` ``AccessToken``. The room name is derived
from ``user_id`` so a user always lands in the same private room.
"""

from __future__ import annotations

from datetime import timedelta

from livekit import api as livekit_api

from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger

log = get_logger(__name__)


def make_room_name(user_id: str) -> str:
    return f"user-{user_id}"


def issue_token(
    *,
    api_key: str,
    api_secret: str,
    user_id: str,
    identity: str | None = None,
    name: str | None = None,
    ttl_minutes: int = 60,
    room: str | None = None,
) -> str:
    if not api_key or not api_secret:
        raise UpstreamUnavailable("livekit credentials missing")
    target_room = room or make_room_name(user_id)
    grants = livekit_api.VideoGrants(
        room_join=True,
        room=target_room,
        can_publish=True,
        can_subscribe=True,
        can_publish_data=True,
    )
    token = (
        livekit_api.AccessToken(api_key, api_secret)
        .with_identity(identity or user_id)
        .with_name(name or "user")
        .with_ttl(timedelta(minutes=ttl_minutes))
        .with_grants(grants)
    )
    jwt: str = token.to_jwt()
    return jwt
