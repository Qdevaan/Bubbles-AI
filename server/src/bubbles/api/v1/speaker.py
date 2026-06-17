# Purpose: Speaker enrollment and identification endpoints that proxy to the Deepgram diarisation service.
"""Speaker enrolment + verification routes.

The heavy ECAPA model runs in the ARQ worker, never on the request path:
``/v1/enroll`` enqueues an enrolment job and returns immediately;
``/v1/identify_speaker`` enqueues a verification job and awaits its result
with a timeout.
"""

from __future__ import annotations

import base64

from fastapi import APIRouter, File, UploadFile

from bubbles.api.v1._schemas import EnrollResponse, IdentifySpeakerResponse
from bubbles.auth.current_user import CurrentUserDep
from bubbles.core.errors import BadRequest, UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.deps import ArqDep
from bubbles.workers.enqueue import enqueue_speaker_enroll, enqueue_speaker_identify

log = get_logger(__name__)
router = APIRouter(tags=["speaker"])

_MAX_AUDIO_BYTES = 5 * 1024 * 1024  # ~5 MB of 16 kHz PCM ≈ 2.5 min — plenty for a clip
_IDENTIFY_TIMEOUT_S = 15.0


async def _read_clip(audio: UploadFile) -> bytes:
    data = await audio.read()
    if not data:
        raise BadRequest("empty audio upload")
    if len(data) > _MAX_AUDIO_BYTES:
        raise BadRequest("audio clip too large")
    return data


@router.post("/enroll", response_model=EnrollResponse, status_code=202)
async def enroll(
    user: CurrentUserDep,
    arq: ArqDep,
    audio: UploadFile = File(...),
) -> EnrollResponse:
    if arq is None:
        raise UpstreamUnavailable("job queue is not ready")
    clip = await _read_clip(audio)
    job = await enqueue_speaker_enroll(
        arq, user_id=user.id, audio_b64=base64.b64encode(clip).decode("ascii")
    )
    return EnrollResponse(status="queued", job_id=getattr(job, "job_id", None))


@router.post("/identify_speaker", response_model=IdentifySpeakerResponse)
async def identify_speaker(
    user: CurrentUserDep,
    arq: ArqDep,
    audio: UploadFile = File(...),
) -> IdentifySpeakerResponse:
    if arq is None:
        raise UpstreamUnavailable("job queue is not ready")
    clip = await _read_clip(audio)
    job = await enqueue_speaker_identify(
        arq, user_id=user.id, audio_b64=base64.b64encode(clip).decode("ascii")
    )
    if job is None:
        raise UpstreamUnavailable("could not enqueue identification job")
    try:
        result = await job.result(timeout=_IDENTIFY_TIMEOUT_S)
    except Exception as exc:
        log.warning("identify_speaker_unavailable", error=str(exc))
        raise UpstreamUnavailable("speaker identification is taking too long") from exc
    if not isinstance(result, dict):
        raise UpstreamUnavailable("unexpected identification result")
    return IdentifySpeakerResponse(
        enrolled=bool(result.get("enrolled")),
        is_user=bool(result.get("is_user")),
        similarity=result.get("similarity"),
    )
