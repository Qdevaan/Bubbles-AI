"""Pytest fixtures + stubs for offline test runs.

The full server requires supabase, sentence-transformers, torch, speechbrain
and other heavy native deps to import. To keep unit tests runnable in any
Python env, we stub those modules in sys.modules BEFORE the app is imported.

Tests that need real provider behaviour belong in manual smoke tests, not
here.
"""
from __future__ import annotations

import sys
import types
from unittest.mock import AsyncMock, MagicMock

import pytest


def _stub_module(name: str, attrs: dict | None = None) -> types.ModuleType:
    mod = types.ModuleType(name)
    for k, v in (attrs or {}).items():
        setattr(mod, k, v)
    sys.modules[name] = mod
    return mod


# ── Stubs installed once at import time ──────────────────────────────────────
if "supabase" not in sys.modules:
    _stub_module("supabase", {
        "create_client": lambda *a, **kw: MagicMock(),
        "Client": MagicMock,
    })

if "sentence_transformers" not in sys.modules:
    _stub_module("sentence_transformers", {"SentenceTransformer": MagicMock})

if "torch" not in sys.modules:
    torch = _stub_module("torch", {
        "tensor": lambda *a, **kw: MagicMock(),
        "nn": MagicMock(),
        "no_grad": lambda: MagicMock(),
        "load": lambda *a, **kw: MagicMock(),
    })
    _stub_module("torch.nn", {})
    _stub_module("torch.nn.functional", {})

if "speechbrain" not in sys.modules:
    _stub_module("speechbrain", {})
    _stub_module("speechbrain.pretrained", {"EncoderClassifier": MagicMock})
    _stub_module("speechbrain.inference", {})
    _stub_module("speechbrain.inference.speaker", {"EncoderClassifier": MagicMock})

if "torchaudio" not in sys.modules:
    _stub_module("torchaudio", {"load": lambda *a, **kw: (MagicMock(), 16000)})

if "livekit" not in sys.modules:
    _stub_module("livekit", {})
    _stub_module("livekit.api", {})

if "redis" not in sys.modules:
    _stub_module("redis", {})
    _stub_module("redis.asyncio", {})

if "pyngrok" not in sys.modules:
    _stub_module("pyngrok", {})
    _stub_module("pyngrok.ngrok", {"connect": lambda *a, **kw: MagicMock()})

if "google" not in sys.modules:
    _stub_module("google", {})
if "google.generativeai" not in sys.modules:
    _stub_module("google.generativeai", {
        "configure": lambda *a, **kw: None,
        "GenerativeModel": MagicMock,
    })

if "cerebras" not in sys.modules:
    _stub_module("cerebras", {})
if "cerebras.cloud" not in sys.modules:
    _stub_module("cerebras.cloud", {})
if "cerebras.cloud.sdk" not in sys.modules:
    _stub_module("cerebras.cloud.sdk", {"AsyncCerebras": MagicMock})

if "groq" not in sys.modules:
    _stub_module("groq", {"AsyncGroq": MagicMock, "Groq": MagicMock})

if "slowapi" not in sys.modules:
    sl = MagicMock()

    class _Limiter:
        def __init__(self, *a, **kw):
            pass

        def limit(self, *a, **kw):
            def deco(f):
                return f
            return deco

    _stub_module("slowapi", {"Limiter": _Limiter, "_rate_limit_exceeded_handler": lambda *a, **kw: None})
    _stub_module("slowapi.errors", {"RateLimitExceeded": Exception})
    _stub_module("slowapi.util", {"get_remote_address": lambda *a, **kw: "0.0.0.0"})

if "networkx" not in sys.modules:
    _stub_module("networkx", {"DiGraph": MagicMock, "Graph": MagicMock})

if "language_tool_python" not in sys.modules:
    class _LT:
        def __init__(self, *a, **kw):
            pass

        def check(self, text):
            return []

        def close(self):
            pass

    _stub_module("language_tool_python", {"LanguageTool": _LT})

if "apscheduler" not in sys.modules:
    _stub_module("apscheduler", {})
    _stub_module("apscheduler.schedulers", {})

    class _Sched:
        def __init__(self, *a, **kw):
            pass

        def add_job(self, *a, **kw):
            pass

        def start(self):
            pass

        def shutdown(self, *a, **kw):
            pass

    _stub_module("apscheduler.schedulers.asyncio", {"AsyncIOScheduler": _Sched})
    _stub_module("apscheduler.triggers", {})
    _stub_module("apscheduler.triggers.cron", {"CronTrigger": MagicMock})
    _stub_module("apscheduler.triggers.interval", {"IntervalTrigger": MagicMock})

if "firebase_admin" not in sys.modules:
    _stub_module("firebase_admin", {
        "initialize_app": lambda *a, **kw: MagicMock(),
        "credentials": MagicMock(),
    })
    _stub_module("firebase_admin.credentials",
                 {"Certificate": lambda *a, **kw: MagicMock()})
    _stub_module("firebase_admin.messaging", {
        "Message": MagicMock,
        "Notification": MagicMock,
        "send": lambda *a, **kw: "fake-message-id",
    })


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture
def mock_brain_svc(mocker):
    mock = MagicMock()
    mock.get_wingman_suggestions = AsyncMock(
        return_value={
            "suggestions": ["Reply 1", "Reply 2", "Reply 3"],
            "latency_ms": 320,
        }
    )
    mocker.patch("app.services.brain_svc", mock)
    return mock


@pytest.fixture
def client():
    from app.main import app
    from fastapi.testclient import TestClient
    return TestClient(app)
