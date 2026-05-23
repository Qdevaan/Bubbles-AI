"""recent_tasks / recent_events repo integration tests."""

from __future__ import annotations

from uuid import UUID

import asyncpg
import pytest

from bubbles.db.repo import entities as repo
from bubbles.db.uow import UnitOfWork

pytestmark = pytest.mark.integration


async def test_recent_tasks_excludes(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        # Both rows share one transaction's now() timestamp, so ORDER BY created_at
        # is exercised but its tie-break order is undefined — assert membership only.
        t1 = await repo.insert_task(uow.conn, user_id=user_id, session_id=None, title="task one")
        t2 = await repo.insert_task(uow.conn, user_id=user_id, session_id=None, title="task two")
        assert t1 is not None and t2 is not None
        all_rows = await repo.recent_tasks(uow.conn, user_id=user_id, limit=10)
        excl = await repo.recent_tasks(uow.conn, user_id=user_id, limit=10, exclude_ids={t1})
    assert {r["id"] for r in all_rows} == {t1, t2}
    assert {r["id"] for r in excl} == {t2}


async def test_recent_events_excludes(pool: asyncpg.Pool, user_id: UUID) -> None:
    async with UnitOfWork(pool) as uow:
        # Both rows share one transaction's now() timestamp, so ORDER BY created_at
        # is exercised but its tie-break order is undefined — assert membership only.
        e1 = await repo.insert_event(uow.conn, user_id=user_id, session_id=None, title="event one")
        e2 = await repo.insert_event(uow.conn, user_id=user_id, session_id=None, title="event two")
        assert e1 is not None and e2 is not None
        all_rows = await repo.recent_events(uow.conn, user_id=user_id, limit=10)
        excl = await repo.recent_events(uow.conn, user_id=user_id, limit=10, exclude_ids={e2})
    assert {r["id"] for r in all_rows} == {e1, e2}
    assert {r["id"] for r in excl} == {e1}
