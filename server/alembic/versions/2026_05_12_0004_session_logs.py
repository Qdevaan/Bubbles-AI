"""session_logs per-turn conversation store

``session_logs`` already exists in the live Supabase database
(``Documentation/db_schema.sql``); ``upgrade()`` is therefore a no-op there
(``CREATE TABLE IF NOT EXISTS``), matching how ``0002`` / ``0003`` behave. The
column set below mirrors the live table so a from-scratch CI database lines up
with production. The test baseline (``tests/integration/fixtures/baseline.sql``)
gets the same table.

Revision ID: 0004
Revises: 0003
Create Date: 2026-05-12 00:00:00 UTC
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS session_logs (
            id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
            session_id     uuid        REFERENCES sessions(id) ON DELETE CASCADE,
            turn_index     integer     NOT NULL DEFAULT 0,
            role           text        NOT NULL,
            content        text,
            content_html   text,
            model_used     text,
            latency_ms     integer,
            tokens_used    integer,
            finish_reason  text,
            has_error      boolean     DEFAULT false,
            error_message  text,
            speaker_label  text,
            confidence     numeric,
            sentiment_score numeric,
            sentiment_label text,
            created_at     timestamptz DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS idx_session_logs_session_turn
            ON session_logs (session_id, turn_index);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX IF EXISTS idx_session_logs_session_turn;
        DROP TABLE IF EXISTS session_logs;
        """
    )
