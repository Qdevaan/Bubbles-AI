"""process_transcript_wingman: turn persistence + advice loop."""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence
from typing import Any
from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.ai.providers.base import ChatMessage, Chunk, Completion, ResponseFormat, Usage
from bubbles.ai.router import LLMRouter, TaskChain
from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.deps import get_arq, get_embeddings, get_pool, get_router

pytestmark = pytest.mark.integration

_ADVICE = "lean in and ask one open follow-up question"


class _Stub:
    name = "stub"
    default_model = "m"

    async def complete(
        self,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
        response_format: ResponseFormat = "text",
        timeout_s: float = 25.0,
    ) -> Completion:
        return Completion(
            text=_ADVICE, finish_reason="stop", usage=Usage(3, 5, 8), raw={"model": "stub-m"}
        )

    async def stream(
        self,
        messages: Sequence[ChatMessage],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
        timeout_s: float = 25.0,
    ) -> AsyncIterator[Chunk]:
        yield Chunk(text=_ADVICE, finish_reason="stop", usage=Usage(3, 5, 8))


class _StubEmb:
    async def embed(self, text: str) -> Sequence[float]:
        raise RuntimeError("no embeddings in tests")  # forces the list_for_user fallback


class FakeArq:
    def __init__(self) -> None:
        self.calls: list[tuple[tuple[Any, ...], dict[str, Any]]] = []

    async def enqueue_job(self, *args: Any, **kwargs: Any) -> str:
        self.calls.append((args, kwargs))
        return str(kwargs.get("_job_id", "job"))


def _router() -> LLMRouter:
    return LLMRouter([_Stub()], [TaskChain("wingman.advice", ("stub",))])


def _override(app: FastAPI, pool: asyncpg.Pool, uid: UUID, *, arq: FakeArq | None = None) -> None:
    app.dependency_overrides[get_pool] = lambda: pool
    app.dependency_overrides[get_arq] = lambda: arq
    app.dependency_overrides[get_router] = _router
    app.dependency_overrides[get_embeddings] = lambda: _StubEmb()
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=str(uid), email=None, role="authenticated"
    )


async def _make_session(pool: asyncpg.Pool, owner: UUID) -> UUID:
    async with pool.acquire() as con:
        row = await con.fetchrow(
            "INSERT INTO sessions (user_id, title, status) VALUES ($1, 's', 'active') RETURNING id",
            owner,
        )
    assert row is not None
    sid: UUID = row["id"]
    return sid


async def test_user_turn_returns_waiting_and_persists(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    arq = FakeArq()
    _override(app, pool, user_id, arq=arq)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/process_transcript_wingman",
            json={
                "session_id": str(sid),
                "transcript": "I think we should ship it",
                "speaker_role": "user",
            },
        )
        rep = await ac.get(f"/v1/session_replay/{sid}")
    assert r.status_code == 200
    assert r.json()["advice"] == "WAITING"
    assert r.json()["turn_index"] == 0
    turns = rep.json()["turns"]
    assert [t["role"] for t in turns] == ["user"]
    # user-turn fast path enqueues an embeddings refresh
    assert [kw["_job_name"] for (_, kw) in arq.calls] == ["compute_embeddings"]


async def test_others_turn_returns_advice_and_logs_llm_turn(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    arq = FakeArq()
    _override(app, pool, user_id, arq=arq)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/process_transcript_wingman",
            json={
                "session_id": str(sid),
                "transcript": "honestly I'm not sure about the timeline",
                "speaker_role": "others",
                "speaker_label": "Dana",
            },
        )
        rep = await ac.get(f"/v1/session_replay/{sid}")
    assert r.status_code == 200
    assert r.json()["advice"] == _ADVICE
    assert r.json()["turn_index"] == 0
    turns = rep.json()["turns"]
    assert [t["role"] for t in turns] == ["others", "llm"]
    assert turns[0]["speaker_label"] == "Dana"
    assert turns[1]["content"] == _ADVICE
    assert turns[1]["model_used"] == "stub-m"
    # turn_count after the llm turn is 2 -> not a multiple of 5 -> no extract; embeddings yes
    assert [kw["_job_name"] for (_, kw) in arq.calls] == ["compute_embeddings"]


async def test_wingman_other_user_403(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    other = uuid4()
    async with pool.acquire() as con:
        await con.execute("INSERT INTO auth.users (id) VALUES ($1)", other)
    sid = await _make_session(pool, other)
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/process_transcript_wingman",
            json={"session_id": str(sid), "transcript": "hi", "speaker_role": "others"},
        )
    assert r.status_code == 403


async def test_wingman_no_session_returns_advice(
    app: FastAPI, pool: asyncpg.Pool, user_id: UUID
) -> None:
    _override(app, pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/process_transcript_wingman",
            json={"transcript": "what do you think we should do next", "speaker_role": "others"},
        )
    assert r.status_code == 200
    assert r.json()["advice"] == _ADVICE
    assert r.json()["turn_index"] is None


async def test_wingman_ok_when_queue_down(app: FastAPI, pool: asyncpg.Pool, user_id: UUID) -> None:
    _override(app, pool, user_id, arq=None)
    sid = await _make_session(pool, user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        r = await ac.post(
            "/v1/process_transcript_wingman",
            json={"session_id": str(sid), "transcript": "go on", "speaker_role": "others"},
        )
    assert r.status_code == 200
    assert r.json()["advice"] == _ADVICE
