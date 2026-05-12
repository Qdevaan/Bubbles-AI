"""Job-enqueue helpers callable from API routes.

Each helper is a thin wrapper over ``ArqRedis.enqueue_job`` so callers don't
need to know function names or queue layout. ``job_id`` is optional but
strongly preferred — pass a stable hash to make duplicate enqueues no-ops.
"""

from __future__ import annotations

from typing import Any

from arq.connections import ArqRedis

from bubbles.core.hashing import hash_obj


def _hash_id(payload: object) -> str:
    return hash_obj(payload)


async def enqueue_extract_knowledge(
    arq: ArqRedis, *, user_id: str, session_id: str, transcript: str
) -> Any:
    job_id = f"extract:{_hash_id((user_id, session_id, len(transcript)))}"
    return await arq.enqueue_job(
        "run",
        _job_name="extract_knowledge",
        user_id=user_id,
        session_id=session_id,
        transcript=transcript,
        _job_id=job_id,
    )


async def enqueue_session_analytics(
    arq: ArqRedis, *, user_id: str, session_id: str, transcript: str
) -> Any:
    job_id = f"analytics:{_hash_id((user_id, session_id))}"
    return await arq.enqueue_job(
        "run",
        _job_name="compute_session_analytics",
        user_id=user_id,
        session_id=session_id,
        transcript=transcript,
        _job_id=job_id,
    )


async def enqueue_grammar_scan(
    arq: ArqRedis, *, user_id: str, session_id: str | None, text: str
) -> Any:
    job_id = f"grammar:{_hash_id((user_id, session_id, text))}"
    return await arq.enqueue_job(
        "run",
        _job_name="grammar_scan",
        user_id=user_id,
        session_id=session_id,
        text=text,
        _job_id=job_id,
    )


async def enqueue_compute_embeddings(arq: ArqRedis, *, user_id: str) -> Any:
    return await arq.enqueue_job(
        "run",
        _job_name="compute_embeddings",
        user_id=user_id,
        _job_id=f"embed:{user_id}",
    )


async def enqueue_detect_achievements(arq: ArqRedis, *, user_id: str) -> Any:
    return await arq.enqueue_job(
        "run",
        _job_name="detect_achievements",
        user_id=user_id,
        _job_id=f"achievements:{user_id}",
    )


async def enqueue_speaker_enroll(arq: ArqRedis, *, user_id: str, audio_b64: str) -> Any:
    # One enrolment in flight per user; a re-enrol while one is queued is a no-op.
    return await arq.enqueue_job(
        "run",
        _job_name="speaker_enroll",
        user_id=user_id,
        audio_b64=audio_b64,
        _job_id=f"enroll:{user_id}",
    )


async def enqueue_speaker_identify(arq: ArqRedis, *, user_id: str, audio_b64: str) -> Any:
    # No stable job id — each identification is distinct and its result is awaited.
    return await arq.enqueue_job(
        "run",
        _job_name="speaker_identify",
        user_id=user_id,
        audio_b64=audio_b64,
    )
