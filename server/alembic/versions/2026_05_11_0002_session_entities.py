"""session_entities link table

Tracks which entities were mentioned in which sessions, so the entity
timeline can show real linked sessions instead of v2's single
``sessions.target_entity_id`` + name-match heuristic.

The table starts empty; old sessions are not backfilled here (a one-off
backfill worker job is a separate follow-up). Going forward the
``extract_knowledge`` ARQ job writes a row per (session, entity) it extracts.

Revision ID: 0002
Revises: 0001
Create Date: 2026-05-11 21:30:00 UTC
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS session_entities (
            session_id    uuid        NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            entity_id     uuid        NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
            user_id       uuid        NOT NULL,
            mention_count integer     NOT NULL DEFAULT 1,
            first_seen_at timestamptz NOT NULL DEFAULT now(),
            last_seen_at  timestamptz NOT NULL DEFAULT now(),
            PRIMARY KEY (session_id, entity_id)
        );
        CREATE INDEX IF NOT EXISTS session_entities_entity_idx
            ON session_entities (entity_id, last_seen_at DESC);
        CREATE INDEX IF NOT EXISTS session_entities_user_idx
            ON session_entities (user_id, last_seen_at DESC);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX IF EXISTS session_entities_user_idx;
        DROP INDEX IF EXISTS session_entities_entity_idx;
        DROP TABLE IF EXISTS session_entities;
        """
    )
