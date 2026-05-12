"""Unit tests for scripts/check_schema_drift.py (pure parsing + diff logic)."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from check_schema_drift import (
    _split_top_level,
    find_drift,
    parse_sql_schema,
)

_SQL = """
-- comment
CREATE TABLE public.widgets (
  id uuid NOT NULL DEFAULT uuid_generate_v4() PRIMARY KEY,
  name text NOT NULL,
  meta jsonb DEFAULT '{}'::jsonb,
  owner_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
  CONSTRAINT widgets_name_key UNIQUE (name),
  UNIQUE (owner_id, name)
);

CREATE TABLE IF NOT EXISTS gadgets (
  id uuid PRIMARY KEY,
  widget_id uuid
);
"""


def test_split_top_level_ignores_nested_commas() -> None:
    parts = _split_top_level("a int, b numeric(10, 2), c text, UNIQUE (a, b)")
    assert [p.strip() for p in parts] == ["a int", "b numeric(10, 2)", "c text", "UNIQUE (a, b)"]


def test_parse_sql_schema_extracts_columns_not_constraints() -> None:
    parsed = parse_sql_schema(_SQL)
    assert parsed["widgets"] == {"id", "name", "meta", "owner_id"}
    assert parsed["gadgets"] == {"id", "widget_id"}


def test_find_drift_flags_built_only_table_and_column() -> None:
    declared = {"widgets": {"id", "name"}}
    built = {
        "widgets": {"id", "name", "secret_col"},  # extra column -> error
        "rogue": {"x"},  # extra table -> error
        "alembic_version": {"version_num"},  # ignored
    }
    errors, _info = find_drift(built, declared, ignore_tables=frozenset({"alembic_version"}))
    assert any("rogue" in e for e in errors)
    assert any("secret_col" in e for e in errors)
    assert not any("alembic_version" in e for e in errors)


def test_find_drift_clean_when_built_is_subset() -> None:
    declared = {"widgets": {"id", "name", "meta"}, "extras": {"a"}}
    built = {"widgets": {"id", "name"}}  # subset baseline — no errors
    errors, info = find_drift(built, declared)
    assert errors == []
    assert any("extras" in line for line in info)  # prod-only table is just info
    assert any("widgets" in line and "meta" in line for line in info)
