"""Stable hashing for cache keys."""

from __future__ import annotations

from bubbles.core.hashing import cache_key, hash_obj, hash_str


def test_hash_str_stable() -> None:
    assert hash_str("hi") == hash_str("hi")
    assert hash_str("hi") != hash_str("ho")


def test_hash_obj_order_independent() -> None:
    a = {"k": 1, "v": [1, 2]}
    b = {"v": [1, 2], "k": 1}
    assert hash_obj(a) == hash_obj(b)


def test_cache_key_format() -> None:
    k = cache_key("prompt", "x", 1)
    assert k.startswith("b3:prompt:")
    # blake3.hexdigest(length=16) → 16 bytes → 32 hex chars
    assert len(k.split(":")[-1]) == 32
