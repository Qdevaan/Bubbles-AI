# Purpose: Async Unit-of-Work context manager that wraps a DB session and commits/rolls back on exit.
"""Unit of Work — request-scoped async transaction wrapper.

Usage::

    async with UnitOfWork(pool) as uow:
        sess = await sessions_repo.start(uow.conn, ...)
        await entities_repo.upsert(uow.conn, ...)
        # commit on context exit; rollback on exception

The UoW exposes a single connection so multiple repo calls share one tx.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from types import TracebackType
from typing import Self

import asyncpg


class UnitOfWork:
    def __init__(self, pool: asyncpg.Pool) -> None:
        self._pool = pool
        self._conn: asyncpg.Connection | None = None
        self._tx: asyncpg.connection.transaction.Transaction | None = None

    @property
    def conn(self) -> asyncpg.Connection:
        if self._conn is None:
            raise RuntimeError("UnitOfWork is not entered")
        return self._conn

    async def __aenter__(self) -> Self:
        self._conn = await self._pool.acquire()
        self._tx = self._conn.transaction()
        await self._tx.start()
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        try:
            if self._tx is not None:
                if exc is None:
                    await self._tx.commit()
                else:
                    await self._tx.rollback()
        finally:
            if self._conn is not None:
                await self._pool.release(self._conn)
            self._conn = None
            self._tx = None


@asynccontextmanager
async def transaction(pool: asyncpg.Pool) -> AsyncIterator[asyncpg.Connection]:
    """Lighter-weight helper when only a connection is needed."""
    async with UnitOfWork(pool) as uow:
        yield uow.conn
