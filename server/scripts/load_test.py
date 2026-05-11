"""Locust fallback for environments without k6.

    uv run locust -f scripts/load_test.py --host https://api.example

Set BUBBLES_TOKEN in the environment to exercise authed routes. Without it
only the health endpoints are hit.
"""

from __future__ import annotations

import os
import random

from locust import HttpUser, between, task

_TOKEN = os.environ.get("BUBBLES_TOKEN", "")
_HEADERS = {"Authorization": f"Bearer {_TOKEN}"} if _TOKEN else {}


def _graceful(response: object) -> bool:
    status = getattr(response, "status_code", 0)
    if status == 503 and getattr(response, "headers", {}).get("Retry-After"):
        return True
    return 200 <= status < 400


class BubblesUser(HttpUser):
    wait_time = between(0.1, 0.6)

    @task(5)
    def health(self) -> None:
        self.client.get("/health/live", name="health/live")

    @task(2)
    def ready(self) -> None:
        self.client.get("/health/ready", name="health/ready")

    @task(3)
    def consultant(self) -> None:
        if not _TOKEN:
            return
        with self.client.post(
            "/v1/ask_consultant?stream=false",
            json={"question": random.choice(["Tip?", "Idea?", "Advice?"])},
            headers=_HEADERS,
            name="consultant/json",
            catch_response=True,
        ) as resp:
            if _graceful(resp):
                resp.success()
            else:
                resp.failure(f"unexpected status {resp.status_code}")
