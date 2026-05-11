"""Persona repo integration tests."""

from __future__ import annotations

from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import personas as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


def test_role_family_classifier() -> None:
    assert repo.classify_role_family("teacher") == "educator"
    assert repo.classify_role_family("student") == "learner"
    assert repo.classify_role_family("manager") == "professional"
    assert repo.classify_role_family("unknown") == "default"


async def test_upsert_idempotent(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        first = await repo.upsert(
            uow.conn,
            user_id=user_id,
            role_primary="teacher",
            native_language="en",
            display_name="Mx. T",
        )
    async with UnitOfWork(pool) as uow:
        second = await repo.upsert(
            uow.conn,
            user_id=user_id,
            role_primary="manager",
            native_language="en",
            display_name="Mx. M",
        )
    assert first.user_id == second.user_id
    assert second.role_family == "professional"
    assert second.display_name == "Mx. M"
