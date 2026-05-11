"""Lazy speaker enrolment via SpeechBrain (worker-only).

The model weights (~80 MB) load once per worker process on first call.
Production deploys can disable this job by skipping the ``speaker-id``
extras during ``uv sync``.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from bubbles.core.logging import get_logger
from bubbles.db.uow import UnitOfWork

log = get_logger(__name__)

_model: Any | None = None


def _get_model() -> Any:
    global _model
    if _model is None:
        try:
            from speechbrain.inference import EncoderClassifier
        except ImportError as exc:
            raise RuntimeError("speechbrain not installed; install the 'speaker-id' extra") from exc
        _model = EncoderClassifier.from_hparams(source="speechbrain/spkrec-ecapa-voxceleb")
    return _model


async def run(
    ctx: dict[str, Any],
    *,
    user_id: str,
    audio_b64: str,
) -> bool:
    """Compute a 192-dim ECAPA embedding and upsert into ``voice_enrollments``."""
    import base64

    import numpy as np
    import torch

    bub = ctx["bubbles"]
    audio_bytes = base64.b64decode(audio_b64)

    # 16 kHz mono int16 PCM expected.
    arr = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
    waveform = torch.from_numpy(arr).unsqueeze(0)
    model = _get_model()
    with torch.no_grad():
        embedding = model.encode_batch(waveform).squeeze().tolist()
    if len(embedding) != 192:
        log.warning("speaker_enroll_bad_dim", n=len(embedding))
        return False

    formatted = "[" + ",".join(f"{v:.6f}" for v in embedding) + "]"
    async with UnitOfWork(bub.pool) as uow:
        await uow.conn.execute(
            """
            INSERT INTO voice_enrollments (user_id, embedding, samples_count, model_version)
            VALUES ($1, $2::vector, 1, 'ecapa-voxceleb')
            ON CONFLICT (id) DO NOTHING
            """,
            UUID(user_id),
            formatted,
        )
    log.info("speaker_enroll_done", user=user_id)
    return True
