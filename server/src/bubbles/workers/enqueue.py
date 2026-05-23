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
    arq: ArqRedis, *, user_id: str, session_id: str, transcript: str, job_suffix: str = ""
) -> Any:
    # ``job_suffix`` lets a follow-up (e.g. after the sentiment scan) force a
    # re-run instead of being deduped against the first run's result.
    job_id = (
        f"analytics:{_hash_id((user_id, session_id))}{(':' + job_suffix) if job_suffix else ''}"
    )
    return await arq.enqueue_job(
        "run",
        _job_name="compute_session_analytics",
        user_id=user_id,
        session_id=session_id,
        transcript=transcript,
        _job_id=job_id,
    )


async def enqueue_sentiment_scan(arq: ArqRedis, *, user_id: str, session_id: str) -> Any:
    return await arq.enqueue_job(
        "run",
        _job_name="sentiment_scan",
        user_id=user_id,
        session_id=session_id,
        _job_id=f"sentiment:{_hash_id((user_id, session_id))}",
    )


async def enqueue_rolling_summarize(
    arq: ArqRedis, *, user_id: str, session_id: str, turn_index: int
) -> Any:
    """Re-summarise the recent tail of a session. One job per (session, turn_index).

    The ``turn_index`` is part of the job id so each 20-turn checkpoint enqueues a
    distinct job; same checkpoint within a few seconds is deduped by ARQ.
    """
    return await arq.enqueue_job(
        "run",
        _job_name="rolling_summarize",
        user_id=user_id,
        session_id=session_id,
        turn_index=turn_index,
        _job_id=f"rollsum:{_hash_id((session_id, turn_index))}",
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


async def enqueue_backfill_session_entities(arq: ArqRedis, *, limit: int = 200) -> Any:
    return await arq.enqueue_job(
        "run",
        _job_name="backfill_session_entities",
        limit=limit,
        _job_id="backfill_session_entities",
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


async def enqueue_generate_scenarios(arq: ArqRedis, *, user_id: str) -> Any:
    return await arq.enqueue_job(
        "run",
        _job_name="generate_scenarios",
        user_id=user_id,
        _job_id=f"genscenarios:{user_id}",
    )


async def enqueue_score_scenario(arq: ArqRedis, *, scenario_id: str) -> Any:
    return await arq.enqueue_job(
        "run",
        _job_name="score_scenario",
        scenario_id=scenario_id,
        _job_id=f"scorescenario:{scenario_id}",
    )
