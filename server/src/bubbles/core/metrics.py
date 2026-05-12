"""Prometheus collectors.

One module-level registry. Every collector here is read by ``/metrics``.
Avoid creating new Counter/Histogram instances at request time — that
mutates the registry and is a memory leak.
"""

from __future__ import annotations

from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

REGISTRY = CollectorRegistry()


# --- HTTP -------------------------------------------------------------------

http_requests_total = Counter(
    "bubbles_http_requests_total",
    "Total HTTP requests processed.",
    labelnames=("method", "route", "status"),
    registry=REGISTRY,
)

http_request_duration_seconds = Histogram(
    "bubbles_http_request_duration_seconds",
    "HTTP request latency in seconds.",
    labelnames=("method", "route"),
    buckets=(0.01, 0.025, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0),
    registry=REGISTRY,
)

# --- LLM --------------------------------------------------------------------

llm_calls_total = Counter(
    "bubbles_llm_calls_total",
    "LLM provider calls.",
    labelnames=("task", "provider", "outcome"),  # outcome ∈ ok|error|breaker
    registry=REGISTRY,
)

llm_fallback_depth = Histogram(
    "bubbles_llm_fallback_depth",
    "Provider chain depth that ultimately served the request (0 = primary).",
    labelnames=("task",),
    buckets=(0, 1, 2, 3, 4),
    registry=REGISTRY,
)

llm_tokens_total = Counter(
    "bubbles_llm_tokens_total",
    "Token usage by provider and direction.",
    labelnames=("provider", "direction"),  # direction ∈ in|out
    registry=REGISTRY,
)

# --- Cache ------------------------------------------------------------------

cache_hits_total = Counter(
    "bubbles_cache_hits_total",
    "Cache lookups split by tier and outcome.",
    labelnames=("namespace", "tier", "outcome"),  # tier ∈ l1|l2; outcome ∈ hit|miss
    registry=REGISTRY,
)

# --- DB / Redis -------------------------------------------------------------

db_pool_in_use = Gauge(
    "bubbles_db_pool_in_use",
    "Connections currently checked out from the asyncpg pool.",
    registry=REGISTRY,
)

db_pool_size = Gauge(
    "bubbles_db_pool_size",
    "Configured upper bound of the asyncpg pool.",
    registry=REGISTRY,
)

# --- ARQ --------------------------------------------------------------------

arq_queue_depth = Gauge(
    "bubbles_arq_queue_depth",
    "Pending jobs in the ARQ queue.",
    labelnames=("queue",),
    registry=REGISTRY,
)

arq_dead_letter_queue_size = Gauge(
    "bubbles_arq_dead_letter_queue_size",
    "Jobs that exhausted all retries (length of the Redis dead-letter list).",
    registry=REGISTRY,
)


def render() -> tuple[bytes, str]:
    """Return the (body, content_type) tuple for ``/metrics``."""
    return generate_latest(REGISTRY), CONTENT_TYPE_LATEST
