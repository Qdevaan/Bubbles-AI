"""drill_cards — Leitner-box spaced-repetition cards for past user mistakes.

New table; not present in the live Supabase schema yet. ``CREATE TABLE IF
NOT EXISTS`` keeps the migration idempotent and safe to re-run, matching
0002-0006.

Revision ID: 0007
Revises: 0006
Create Date: 2026-05-23 00:00:00 UTC
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS drill_cards (
            id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id           uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
            rule_id           text        NOT NULL,
            category          text        NOT NULL,
            examples          jsonb       NOT NULL DEFAULT '[]'::jsonb,
            box               smallint    NOT NULL DEFAULT 1
                                  CHECK (box BETWEEN 1 AND 5),
            due_at            timestamptz NOT NULL DEFAULT now(),
            last_reviewed_at  timestamptz,
            correct_streak    integer     NOT NULL DEFAULT 0,
            total_reviews     integer     NOT NULL DEFAULT 0,
            total_correct     integer     NOT NULL DEFAULT 0,
            retired_at        timestamptz,
            created_at        timestamptz NOT NULL DEFAULT now(),
            updated_at        timestamptz NOT NULL DEFAULT now(),
            CONSTRAINT uq_drill_cards_user_rule_category UNIQUE (user_id, rule_id, category)
        );
        CREATE INDEX IF NOT EXISTS idx_drill_cards_user_due
            ON drill_cards (user_id, due_at)
            WHERE retired_at IS NULL;
        CREATE INDEX IF NOT EXISTS idx_drill_cards_user_retired
            ON drill_cards (user_id, retired_at);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX IF EXISTS idx_drill_cards_user_retired;
        DROP INDEX IF EXISTS idx_drill_cards_user_due;
        DROP TABLE IF EXISTS drill_cards;
        """
    )
