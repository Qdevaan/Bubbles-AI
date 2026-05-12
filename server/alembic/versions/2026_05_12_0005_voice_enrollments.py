"""voice_enrollments speaker-embedding store

``voice_enrollments`` already exists in the live Supabase database
(``Documentation/db_schema.sql``) along with the ``vector`` extension, so
``upgrade()`` is a no-op there (``CREATE TABLE IF NOT EXISTS``). The
``vector(192)`` column requires the ``vector`` extension; this migration does
*not* create it (matching the other migrations, which never touch extensions)
— a from-scratch database must have ``vector`` installed first (the CI
schema-drift job in H13 handles that). The test baseline installs it itself.

Revision ID: 0005
Revises: 0004
Create Date: 2026-05-12 00:00:00 UTC
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS voice_enrollments (
            id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id       uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
            embedding     vector(192) NOT NULL,
            samples_count integer     DEFAULT 0,
            model_version text,
            updated_at    timestamptz NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS idx_voice_enrollments_user ON voice_enrollments (user_id);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX IF EXISTS idx_voice_enrollments_user;
        DROP TABLE IF EXISTS voice_enrollments;
        """
    )
