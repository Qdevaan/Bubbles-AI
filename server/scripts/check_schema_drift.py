"""Fail if the migrated schema has tables/columns the live Supabase schema lacks.

Run in CI after ``alembic upgrade head`` (on top of the test baseline). The
"declared" schema is ``Documentation/db_schema.sql``; the "built" schema is
whatever's actually in the ``public`` schema of the target database. Direction
matters: a table/column that exists in the *built* DB but **not** in
``db_schema.sql`` is drift (a migration or the test baseline expects something
prod doesn't have → 500s in prod). The reverse — prod has things the built DB
doesn't — is expected (``baseline.sql`` mirrors only a subset) and only logged.

    uv run python scripts/check_schema_drift.py \
        --dsn postgresql://user:pass@localhost:5432/db \
        --schema-file ../Documentation/db_schema.sql
"""

from __future__ import annotations

import argparse
import asyncio
import re
import sys
from pathlib import Path

import asyncpg

# Tables that legitimately exist in the built DB but not in db_schema.sql:
#   alembic_version    — alembic's own bookkeeping table
#   session_entities   — added by Alembic 0002 (v5-new link table)
#   user_personas      — v5's persona table (db_schema.sql still has the old `profiles`)
# Add to this set when a migration introduces a new table; never to silence
# drift on a table that prod already has.
_IGNORE_BUILT_TABLES: frozenset[str] = frozenset(
    {"alembic_version", "session_entities", "user_personas"}
)

# Line-leading tokens inside a CREATE TABLE body that are constraints, not columns.
_CONSTRAINT_KEYWORDS: frozenset[str] = frozenset(
    {"primary", "foreign", "unique", "check", "constraint", "exclude", "like"}
)

_CREATE_TABLE_RE = re.compile(
    r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?(?P<name>\w+)\s*\((?P<body>.*?)\)\s*;",
    re.IGNORECASE | re.DOTALL,
)


def _split_top_level(body: str) -> list[str]:
    """Split a CREATE TABLE body on top-level commas (ignoring those inside parens)."""
    parts: list[str] = []
    depth = 0
    cur: list[str] = []
    for ch in body:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if cur:
        parts.append("".join(cur))
    return parts


def parse_sql_schema(text: str) -> dict[str, set[str]]:
    """Parse ``CREATE TABLE [public.]name (...)`` blocks → {table: {column names}}."""
    out: dict[str, set[str]] = {}
    for m in _CREATE_TABLE_RE.finditer(text):
        name = m.group("name").lower()
        cols: set[str] = set()
        for raw in _split_top_level(m.group("body")):
            line = raw.strip()
            if not line:
                continue
            first = line.split()[0].strip('"').lower()
            if first in _CONSTRAINT_KEYWORDS or not re.fullmatch(r"\w+", first):
                continue
            cols.add(first)
        if cols:
            out[name] = cols
    return out


async def introspect_public_schema(conn: asyncpg.Connection) -> dict[str, set[str]]:
    rows = await conn.fetch(
        """
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
        ORDER BY table_name, ordinal_position
        """
    )
    out: dict[str, set[str]] = {}
    for r in rows:
        out.setdefault(r["table_name"].lower(), set()).add(r["column_name"].lower())
    return out


def find_drift(
    built: dict[str, set[str]],
    declared: dict[str, set[str]],
    *,
    ignore_tables: frozenset[str] = _IGNORE_BUILT_TABLES,
) -> tuple[list[str], list[str]]:
    """Return (errors, info). Errors = built has something not in declared."""
    errors: list[str] = []
    info: list[str] = []
    for table, cols in sorted(built.items()):
        if table in ignore_tables:
            continue
        if table not in declared:
            errors.append(f"table `{table}` exists in the migrated DB but not in db_schema.sql")
            continue
        extra = cols - declared[table]
        if extra:
            errors.append(
                f"table `{table}` has column(s) not in db_schema.sql: {', '.join(sorted(extra))}"
            )
        missing = declared[table] - cols
        if missing:
            info.append(
                f"table `{table}` (subset baseline) omits prod column(s): {', '.join(sorted(missing))}"
            )
    for table in sorted(set(declared) - set(built)):
        info.append(
            f"table `{table}` exists in db_schema.sql but not in the migrated DB (subset baseline)"
        )
    return errors, info


async def _amain() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dsn", required=True, help="postgresql://… DSN of the migrated DB")
    ap.add_argument("--schema-file", required=True, type=Path, help="path to db_schema.sql")
    args = ap.parse_args()

    declared = parse_sql_schema(args.schema_file.read_text(encoding="utf-8"))
    if not declared:
        print(f"!! parsed 0 tables from {args.schema_file} — check the file path", file=sys.stderr)
        return 2
    dsn = args.dsn.replace("postgresql+asyncpg://", "postgresql://")
    conn = await asyncpg.connect(dsn=dsn)
    try:
        built = await introspect_public_schema(conn)
    finally:
        await conn.close()

    errors, info = find_drift(built, declared)
    for line in info:
        print(f"   (info) {line}")
    if errors:
        print("\nSCHEMA DRIFT — the migrated schema diverges from Documentation/db_schema.sql:")
        for line in errors:
            print(f"  ✗ {line}")
        return 1
    print(f"OK — {len(built)} public tables; no columns/tables beyond db_schema.sql.")
    return 0


def main() -> None:
    raise SystemExit(asyncio.run(_amain()))


if __name__ == "__main__":
    main()
