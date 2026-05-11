"""Alembic environment.

Async-aware. Reads ``DATABASE_URL`` from env when present so we don't keep
secrets in alembic.ini.
"""

from __future__ import annotations

import asyncio
import os
from logging.config import fileConfig

from alembic import context
from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

env_url = os.environ.get("DATABASE_URL")
if env_url:
    # Alembic stores plain text; if a Supabase URL came in as ``postgresql://``
    # we coerce it to the asyncpg dialect.
    if env_url.startswith("postgres://"):
        env_url = env_url.replace("postgres://", "postgresql+asyncpg://", 1)
    elif env_url.startswith("postgresql://") and "+asyncpg" not in env_url:
        env_url = env_url.replace("postgresql://", "postgresql+asyncpg://", 1)
    config.set_main_option("sqlalchemy.url", env_url)

target_metadata = None  # raw-SQL migrations only — no ORM model autogen


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    section = config.get_section(config.config_ini_section, {})
    connectable = async_engine_from_config(section, prefix="sqlalchemy.", poolclass=pool.NullPool)
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
