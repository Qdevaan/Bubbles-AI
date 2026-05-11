# syntax=docker/dockerfile:1.7
# Multi-stage build for Bubbles Brain API v5.
#
# Targets:
#   runtime  — FastAPI app (default)
#   worker   — ARQ worker (adds embed-local + stt-local extras; speaker-id optional)

# ---------------------------------------------------------------------------
# Base: uv + Python 3.12
# ---------------------------------------------------------------------------
FROM python:3.12-slim-bookworm AS base
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never
COPY --from=ghcr.io/astral-sh/uv:0.5 /uv /uvx /usr/local/bin/
WORKDIR /app

# Runtime OS deps: curl for healthcheck, ffmpeg + libsndfile for audio paths.
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Builder: resolve + install deps into a venv
# ---------------------------------------------------------------------------
FROM base AS builder
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*
ENV UV_PROJECT_ENVIRONMENT=/opt/venv

# Layer 1: deps only (cached unless lockfile changes).
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --no-dev

# Layer 2: project source + install the package itself.
COPY src ./src
COPY alembic.ini ./
COPY alembic ./alembic
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# ---------------------------------------------------------------------------
# Runtime: API server
# ---------------------------------------------------------------------------
FROM base AS runtime
ENV PATH="/opt/venv/bin:$PATH" \
    UV_PROJECT_ENVIRONMENT=/opt/venv
RUN useradd --create-home --uid 1001 bubbles
COPY --from=builder /opt/venv /opt/venv
COPY --chown=bubbles:bubbles src ./src
COPY --chown=bubbles:bubbles alembic.ini ./
COPY --chown=bubbles:bubbles alembic ./alembic
USER bubbles
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD curl -fsS http://localhost:8000/health/ready || exit 1
# 1 master + N uvicorn workers; tune --workers via compose override.
CMD ["gunicorn", "bubbles.app:create_app", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000", "--workers", "4", \
     "--timeout", "60", "--graceful-timeout", "30", \
     "--access-logfile", "-", "--error-logfile", "-"]

# ---------------------------------------------------------------------------
# Worker: ARQ background jobs
# ---------------------------------------------------------------------------
FROM base AS worker
ENV PATH="/opt/venv/bin:$PATH" \
    UV_PROJECT_ENVIRONMENT=/opt/venv
RUN useradd --create-home --uid 1001 bubbles
COPY --from=builder /opt/venv /opt/venv
COPY --chown=bubbles:bubbles src ./src
COPY --chown=bubbles:bubbles alembic.ini ./
COPY --chown=bubbles:bubbles alembic ./alembic
USER bubbles
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD arq --check bubbles.workers.arq_settings.WorkerSettings || exit 1
CMD ["arq", "bubbles.workers.arq_settings.WorkerSettings"]
