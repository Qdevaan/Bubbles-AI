# Purpose: Deterministic BLAKE2b hashing utilities for generating idempotency keys from structured inputs.
"""Stable content hashing for cache keys.

blake3 is faster than sha256 and we never need cryptographic strength here —
only collision resistance for prompt+context cache keys.
"""

from __future__ import annotations

import json
from typing import Any

from blake3 import blake3


def hash_str(value: str) -> str:
    """Hex digest of a string (32 chars)."""
    return blake3(value.encode("utf-8")).hexdigest(length=16)


def hash_obj(value: Any) -> str:
    """Hex digest of a JSON-serialisable object.

    Sort keys + ensure_ascii=False so equivalent dicts hash equally regardless
    of insertion order.
    """
    payload = json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hash_str(payload)


def cache_key(namespace: str, *parts: Any) -> str:
    """Stable cache key: ``b3:{ns}:{hash(parts)}``."""
    return f"b3:{namespace}:{hash_obj(parts)}"
