"""Speaker verification: is the audio the enrolled user, or someone else?

Computes the ECAPA embedding of the query clip (heavy — worker only) and
compares it (pgvector cosine distance) against the user's stored enrolment.
Returned by ``await job.result(...)`` to the ``/v1/identify_speaker`` route.
"""

from __future__ import annotations

import base64
from typing import TYPE_CHECKING, Any
from uuid import UUID

from bubbles.core.logging import get_logger
from bubbles.db.repo import voice as voice_repo
from bubbles.db.uow import transaction
from bubbles.workers.jobs.speaker_enroll import encode_pcm16

if TYPE_CHECKING:
    from bubbles.workers.arq_settings import WorkerCtx

log = get_logger(__name__)

# ECAPA cosine *distance* (1 - cos sim); below this the clip is the enrolled user.
# 0.30 ≈ cosine similarity 0.70 — a conventional ECAPA-VoxCeleb verification point.
_MATCH_DISTANCE_THRESHOLD = 0.30


async def run(ctx: dict[str, Any], *, user_id: str, audio_b64: str) -> dict[str, Any]:
    bub: WorkerCtx = ctx["bubbles"]
    try:
        embedding = encode_pcm16(base64.b64decode(audio_b64))
    except Exception as exc:
        log.warning("speaker_identify_failed", user=user_id, error=str(exc))
        return {"enrolled": False, "is_user": False, "similarity": None, "error": str(exc)}

    async with transaction(bub.pool) as conn:
        distance = await voice_repo.cosine_distance_to_user(
            conn, user_id=UUID(user_id), embedding=embedding
        )
    if distance is None:
        return {"enrolled": False, "is_user": False, "similarity": None, "error": None}
    similarity = 1.0 - distance
    return {
        "enrolled": True,
        "is_user": distance <= _MATCH_DISTANCE_THRESHOLD,
        "similarity": round(similarity, 4),
        "error": None,
    }
