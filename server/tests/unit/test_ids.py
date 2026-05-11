"""ULID helpers."""

from __future__ import annotations

from bubbles.core.ids import is_ulid, new_id, new_uuid


def test_new_id_is_ulid() -> None:
    a = new_id()
    assert is_ulid(a)
    assert len(a) == 26


def test_ids_are_lex_sortable() -> None:
    import time

    a = new_id()
    time.sleep(0.002)
    b = new_id()
    # Time-prefix (first 10 chars) is monotonically non-decreasing.
    assert a[:10] <= b[:10]


def test_new_uuid_is_uuid_string() -> None:
    u = new_uuid()
    assert len(u) == 36 and u.count("-") == 4


def test_is_ulid_rejects_garbage() -> None:
    assert not is_ulid("")
    assert not is_ulid("nope")
    assert not is_ulid("a" * 26)
