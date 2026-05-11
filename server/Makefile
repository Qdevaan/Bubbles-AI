.PHONY: help sync dev test lint fmt typecheck cov hooks migrate revision run docker docker-prod clean

PY := uv run
APP := bubbles.app:create_app

help:
	@echo "Targets:"
	@echo "  sync        install + lock deps"
	@echo "  dev         run uvicorn with reload"
	@echo "  run         run uvicorn (no reload)"
	@echo "  test        ruff + mypy + pytest"
	@echo "  lint        ruff check"
	@echo "  fmt         ruff format"
	@echo "  typecheck   mypy strict"
	@echo "  cov         pytest with HTML coverage"
	@echo "  hooks       install pre-commit hooks"
	@echo "  migrate     alembic upgrade head"
	@echo "  revision    alembic revision -m '<msg>'  (use MSG=)"
	@echo "  docker      build dev image"
	@echo "  docker-prod build prod image"
	@echo "  clean       remove caches"

sync:
	uv sync --all-extras

dev:
	$(PY) uvicorn --factory $(APP) --host 0.0.0.0 --port 8000 --reload

run:
	$(PY) uvicorn --factory $(APP) --host 0.0.0.0 --port 8000

test: lint typecheck
	$(PY) pytest

lint:
	$(PY) ruff check .
	$(PY) ruff format --check .

fmt:
	$(PY) ruff format .
	$(PY) ruff check --fix .

typecheck:
	$(PY) mypy

cov:
	$(PY) pytest --cov-report=html
	@echo "open htmlcov/index.html"

hooks:
	$(PY) pre-commit install --install-hooks

migrate:
	$(PY) alembic upgrade head

revision:
	@test -n "$(MSG)" || (echo "usage: make revision MSG='add foo'"; exit 1)
	$(PY) alembic revision --autogenerate -m "$(MSG)"

docker:
	docker build -t bubbles-server:dev .

docker-prod:
	docker build -t bubbles-server:prod -f Dockerfile --target runtime .

clean:
	rm -rf .pytest_cache .mypy_cache .ruff_cache .coverage coverage.xml htmlcov build dist
