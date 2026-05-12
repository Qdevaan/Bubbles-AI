"""gamification tables: xp_transactions, achievements, user_achievements

These three tables already exist in the live Supabase database
(``Documentation/db_schema.sql``); ``upgrade()`` is therefore a no-op there
(``CREATE TABLE IF NOT EXISTS``), matching how the ``0002`` migration behaves.
The test baseline schema (``tests/integration/fixtures/baseline.sql``) gets
the same tables so integration tests can exercise the new repos.

Revision ID: 0003
Revises: 0002
Create Date: 2026-05-12 00:00:00 UTC
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS xp_transactions (
            id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id     uuid        REFERENCES auth.users(id) ON DELETE CASCADE,
            amount      integer     NOT NULL,
            source_type text        NOT NULL,
            source_id   text,
            description text,
            created_at  timestamptz DEFAULT now()
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_xp_transactions_dedup
            ON xp_transactions (user_id, source_type, source_id) WHERE source_id IS NOT NULL;
        CREATE INDEX IF NOT EXISTS idx_xp_transactions_user_time
            ON xp_transactions (user_id, created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_xp_transactions_period
            ON xp_transactions (created_at, user_id) WHERE amount > 0;

        CREATE TABLE IF NOT EXISTS achievements (
            id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
            code           text        UNIQUE,
            title          text        NOT NULL,
            description    text,
            icon           text        DEFAULT '🏆',
            category       text        DEFAULT 'general',
            criteria_type  text        NOT NULL,
            criteria_value integer     NOT NULL,
            xp_reward      integer     DEFAULT 0,
            tier           text,
            created_at     timestamptz NOT NULL DEFAULT now()
        );

        CREATE TABLE IF NOT EXISTS user_achievements (
            id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id        uuid        REFERENCES auth.users(id) ON DELETE CASCADE,
            achievement_id uuid        REFERENCES achievements(id) ON DELETE CASCADE,
            awarded_at     timestamptz DEFAULT now(),
            UNIQUE (user_id, achievement_id)
        );
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP TABLE IF EXISTS user_achievements;
        DROP TABLE IF EXISTS achievements;
        DROP TABLE IF EXISTS xp_transactions;
        """
    )
