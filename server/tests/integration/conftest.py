"""Integration-test fixtures.

Spins up Postgres via testcontainers, applies the baseline schema, hands an
asyncpg pool to tests. Skipped automatically when Docker isn't available
or when ``RUN_INTEGRATION`` is unset.

Tests must be marked ``@pytest.mark.integration``.
"""

from __future__ import annotations

import os
from collections.abc import AsyncIterator, Iterator
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

import pytest

pytestmark = pytest.mark.integration


def _skip_if_no_docker() -> None:
    if not os.environ.get("RUN_INTEGRATION"):
        pytest.skip("integration tests disabled (set RUN_INTEGRATION=1)", allow_module_level=True)
    try:
        import docker  # noqa: F401
    except ImportError:
        pytest.skip("docker SDK not installed", allow_module_level=True)


_skip_if_no_docker()

import asyncpg  # noqa: E402
from testcontainers.postgres import PostgresContainer  # noqa: E402

_BASELINE = Path(__file__).parent / "fixtures" / "baseline.sql"


@pytest.fixture(scope="session")
def pg_container() -> Iterator[Any]:
    container = PostgresContainer(
        image="pgvector/pgvector:pg16",
        username="bubbles",
        password="bubbles",
        dbname="bubbles_test",
    )
    container.start()
    try:
        yield container
    finally:
        container.stop()


@pytest.fixture(scope="session")
def pg_dsn(pg_container: Any) -> str:
    raw: str = pg_container.get_connection_url()
    # testcontainers returns SQLAlchemy-style URL; strip dialect for asyncpg.
    return raw.replace("postgresql+psycopg2://", "postgresql://")


@pytest.fixture
async def pool(pg_dsn: str) -> AsyncIterator[asyncpg.Pool]:
    pool = await asyncpg.create_pool(dsn=pg_dsn, min_size=1, max_size=4)
    assert pool is not None
    try:
        async with pool.acquire() as con:
            await con.execute(_BASELINE.read_text(encoding="utf-8"))
        yield pool
    finally:
        async with pool.acquire() as con:
            await con.execute(
                """
                DROP SCHEMA IF EXISTS auth CASCADE;
                DROP TABLE IF EXISTS scenarios, drill_cards, feedback, session_analytics, coaching_reports,
                    highlights,
                    voice_enrollments, session_entities, session_logs, events, tasks,
                    user_rewards, rewards, user_achievements, achievements, xp_transactions,
                    user_quests, quest_definitions,
                    user_gamification, user_mistakes, memory, user_personas,
                    entity_relations, entities, sessions CASCADE;
                """
            )
        await pool.close()


@pytest.fixture
async def user_id(pool: asyncpg.Pool) -> UUID:
    new_id = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", new_id)
    return new_id


@pytest.fixture
async def other_user_id(pool: asyncpg.Pool) -> UUID:
    new_id = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", new_id)
    return new_id
