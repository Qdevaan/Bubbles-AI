"""LiveKit token issuance."""

from __future__ import annotations

import pytest

from bubbles.core.errors import UpstreamUnavailable
from bubbles.voice.livekit import issue_token, make_room_name


def test_room_name_from_user() -> None:
    assert make_room_name("abc") == "user-abc"


def test_token_requires_credentials() -> None:
    with pytest.raises(UpstreamUnavailable):
        issue_token(api_key="", api_secret="", user_id="u")


def test_token_returns_jwt() -> None:
    jwt = issue_token(api_key="key", api_secret="x" * 32, user_id="u")
    assert isinstance(jwt, str)
    # JWT = three base64 segments separated by `.`
    assert jwt.count(".") == 2
