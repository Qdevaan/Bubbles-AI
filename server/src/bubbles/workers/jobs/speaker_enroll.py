# Purpose: Background job that submits audio samples to Deepgram for new speaker-profile enrollment.
"""Lazy speaker enrolment via SpeechBrain (worker-only).

The model weights (~80 MB) load once per worker process on first call.
Production deploys can disable this job by skipping the ``speaker-id``
extras during ``uv sync``. The ECAPA encoder here is reused by the
``speaker_identify`` job.
"""

from __future__ import annotations

import base64
from typing import TYPE_CHECKING, Any
from uuid import UUID

from bubbles.core.logging import get_logger
from bubbles.db.repo import voice as voice_repo
from bubbles.db.uow import UnitOfWork

if TYPE_CHECKING:
    from bubbles.workers.arq_settings import WorkerCtx

log = get_logger(__name__)

MODEL_VERSION = "ecapa-voxceleb"
_EMBED_DIM = 192

_model: Any | None = None


def _get_model() -> Any:
    global _model
    if _model is None:
        try:
            from speechbrain.inference import EncoderClassifier
        except ImportError as exc:  # pragma: no cover - optional extra
            raise RuntimeError("speechbrain not installed; install the 'speaker-id' extra") from exc
        _model = EncoderClassifier.from_hparams(source="speechbrain/spkrec-ecapa-voxceleb")
    return _model


def encode_pcm16(audio_bytes: bytes) -> list[float]:
    """ECAPA embedding of 16 kHz mono int16 PCM. Raises if the embedding dim is wrong."""
    import numpy as np
    import torch

    arr = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
    waveform = torch.from_numpy(arr).unsqueeze(0)
    model = _get_model()
    with torch.no_grad():
        embedding: list[float] = model.encode_batch(waveform).squeeze().tolist()
    if len(embedding) != _EMBED_DIM:
        raise RuntimeError(f"unexpected ECAPA embedding dim: {len(embedding)}")
    return embedding


async def run(ctx: dict[str, Any], *, user_id: str, audio_b64: str) -> bool:
    """Compute the user's ECAPA embedding and replace their ``voice_enrollments`` row."""
    bub: WorkerCtx = ctx["bubbles"]
    try:
        embedding = encode_pcm16(base64.b64decode(audio_b64))
    except Exception as exc:
        log.warning("speaker_enroll_failed", user=user_id, error=str(exc))
        return False
    async with UnitOfWork(bub.pool) as uow:
        await voice_repo.upsert_embedding(
            uow.conn, user_id=UUID(user_id), embedding=embedding, model_version=MODEL_VERSION
        )
    log.info("speaker_enroll_done", user=user_id)
    return True
