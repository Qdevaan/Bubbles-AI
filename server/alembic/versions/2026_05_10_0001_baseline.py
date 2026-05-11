"""baseline — production DB already at this revision

Production DB lives on Supabase and is already at the schema captured in
``Documentation/db_schema.sql``. This revision is empty by design:
``alembic stamp 0001`` marks the existing DB as up-to-date so future
revisions build forward without re-creating tables.

Revision ID: 0001
Revises:
Create Date: 2026-05-10 16:50:00 UTC
"""

from __future__ import annotations

from collections.abc import Sequence

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
