"""/v1/enroll and /v1/identify_speaker — queue interaction, no real model."""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from bubbles.auth.current_user import CurrentUser, current_user
from bubbles.deps import get_arq

_USER = "11111111-1111-1111-1111-111111111111"
_CLIP = b"\x00\x01" * 64


class FakeJob:
    def __init__(self, *, result: Any = None, raises: BaseException | None = None) -> None:
        self.job_id = "job-123"
        self._result = result
        self._raises = raises

    async def result(self, timeout: float | None = None) -> Any:  # noqa: ASYNC109 — mirrors arq.jobs.Job.result
        if self._raises is not None:
            raise self._raises
        return self._result


class FakeArq:
    def __init__(self, *, job: FakeJob | None) -> None:
        self.job = job
        self.calls: list[tuple[tuple[Any, ...], dict[str, Any]]] = []

    async def enqueue_job(self, *args: Any, **kwargs: Any) -> FakeJob | None:
        self.calls.append((args, kwargs))
        return self.job


def _override(app: FastAPI, *, arq: FakeArq | None) -> None:
    app.dependency_overrides[current_user] = lambda: CurrentUser(
        id=_USER, email=None, role="authenticated"
    )
    app.dependency_overrides[get_arq] = lambda: arq


async def _client(app: FastAPI) -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://t")


def _files() -> dict[str, tuple[str, bytes, str]]:
    return {"audio": ("clip.pcm", _CLIP, "application/octet-stream")}


async def test_enroll_queues_job(app: FastAPI) -> None:
    arq = FakeArq(job=FakeJob())
    _override(app, arq=arq)
    async with await _client(app) as ac:
        r = await ac.post("/v1/enroll", files=_files())
    assert r.status_code == 202
    assert r.json() == {"status": "queued", "job_id": "job-123"}
    assert arq.calls[0][1]["_job_name"] == "speaker_enroll"
    assert arq.calls[0][1]["user_id"] == _USER


async def test_enroll_503_when_queue_down(app: FastAPI) -> None:
    _override(app, arq=None)
    async with await _client(app) as ac:
        r = await ac.post("/v1/enroll", files=_files())
    assert r.status_code == 503


async def test_enroll_rejects_empty_audio(app: FastAPI) -> None:
    _override(app, arq=FakeArq(job=FakeJob()))
    async with await _client(app) as ac:
        r = await ac.post("/v1/enroll", files={"audio": ("c.pcm", b"", "application/octet-stream")})
    assert r.status_code == 400


async def test_identify_returns_verification_result(app: FastAPI) -> None:
    job = FakeJob(result={"enrolled": True, "is_user": True, "similarity": 0.82, "error": None})
    _override(app, arq=FakeArq(job=job))
    async with await _client(app) as ac:
        r = await ac.post("/v1/identify_speaker", files=_files())
    assert r.status_code == 200
    assert r.json() == {"enrolled": True, "is_user": True, "similarity": 0.82}


async def test_identify_not_enrolled(app: FastAPI) -> None:
    job = FakeJob(result={"enrolled": False, "is_user": False, "similarity": None, "error": None})
    _override(app, arq=FakeArq(job=job))
    async with await _client(app) as ac:
        r = await ac.post("/v1/identify_speaker", files=_files())
    assert r.status_code == 200
    assert r.json() == {"enrolled": False, "is_user": False, "similarity": None}


async def test_identify_503_on_worker_timeout(app: FastAPI) -> None:
    job = FakeJob(raises=TimeoutError("not done"))
    _override(app, arq=FakeArq(job=job))
    async with await _client(app) as ac:
        r = await ac.post("/v1/identify_speaker", files=_files())
    assert r.status_code == 503


async def test_identify_503_when_queue_down(app: FastAPI) -> None:
    _override(app, arq=None)
    async with await _client(app) as ac:
        r = await ac.post("/v1/identify_speaker", files=_files())
    assert r.status_code == 503
