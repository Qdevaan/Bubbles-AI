# Bubbles Brain API v5

Async FastAPI server for Bubbles-AI. See `../Documentation/server-blueprint.md` for full design.

## Quick start

```bash
uv sync                # install deps + lock
cp .env.example .env   # fill secrets
make dev               # uvicorn --reload
make test              # ruff + mypy + pytest
```

## Layout

```
src/bubbles/   application code
alembic/       migrations
tests/         unit / integration / e2e
scripts/       seed, backfill, load test
ops/           dashboards, alert rules
```

## Tooling

- `uv` — package + venv manager
- `ruff` — lint + format
- `mypy --strict` — types
- `pytest` — tests with coverage
- `pre-commit` — local hooks

## Phases

Tracked in `Documentation/server-blueprint.md`. This repo skeleton = Phase 0.
