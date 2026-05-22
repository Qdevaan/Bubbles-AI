"""scenarios — graph-generated roleplay practice

New table; not present in the live Supabase schema yet. ``CREATE TABLE IF
NOT EXISTS`` keeps the migration idempotent and safe to re-run, matching
0002-0005.

Revision ID: 0006
Revises: 0005
Create Date: 2026-05-22 00:00:00 UTC
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS scenarios (
            id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id          uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
            target_entity_id uuid        REFERENCES entities(id) ON DELETE SET NULL,
            title            text        NOT NULL,
            situation        text        NOT NULL,
            goal             text        NOT NULL,
            success_criteria text        NOT NULL,
            difficulty       text        NOT NULL DEFAULT 'medium'
                                 CHECK (difficulty IN ('easy', 'medium', 'hard')),
            role_mode        text        NOT NULL DEFAULT 'default',
            opening_line     text        NOT NULL,
            source           jsonb       NOT NULL DEFAULT '{}'::jsonb,
            status           text        NOT NULL DEFAULT 'suggested'
                                 CHECK (status IN ('suggested','started','completed','dismissed')),
            session_id       uuid        REFERENCES sessions(id) ON DELETE SET NULL,
            passed           boolean,
            score_feedback   text,
            created_at       timestamptz NOT NULL DEFAULT now(),
            updated_at       timestamptz NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS idx_scenarios_user_status
            ON scenarios (user_id, status);
        CREATE INDEX IF NOT EXISTS idx_scenarios_user_entity
            ON scenarios (user_id, target_entity_id);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX IF EXISTS idx_scenarios_user_entity;
        DROP INDEX IF EXISTS idx_scenarios_user_status;
        DROP TABLE IF EXISTS scenarios;
        """
    )
