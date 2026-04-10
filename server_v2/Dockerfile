FROM python:3.11-slim

WORKDIR /app

# System deps: build tools, curl (healthcheck), ffmpeg (audio), libsndfile (speechbrain)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ffmpeg \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user early so pip cache is owned correctly
RUN useradd -m -u 1001 bubbles

# Copy and install dependencies as root (needs build tools)
COPY requirements.txt .
RUN pip install -r requirements.txt

# Copy application source
COPY app/ ./app/

# Hand off ownership and switch user
RUN chown -R bubbles:bubbles /app
USER bubbles

# Docker-layer health check (independent of docker-compose)
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

EXPOSE 8000

# Use 2 workers in production (adjust via CMD override in compose)
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
