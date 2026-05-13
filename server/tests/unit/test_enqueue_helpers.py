"""Unit tests for the API-side job-enqueue helpers."""

from __future__ import annotations

from typing import Any

from bubbles.workers.enqueue import (
    enqueue_compute_embeddings,
    enqueue_extract_knowledge,
    enqueue_grammar_scan,
    enqueue_rolling_summarize,
    enqueue_session_analytics,
)


class FakeArq:
    """Records ``enqueue_job`` calls; mimics the bits of ``ArqRedis`` we use."""

    def __init__(self) -> None:
        self.calls: list[tuple[tuple[Any, ...], dict[str, Any]]] = []

    async def enqueue_job(self, *args: Any, **kwargs: Any) -> str:
        self.calls.append((args, kwargs))
        job_id = kwargs.get("_job_id", "job")
        return str(job_id)


async def test_enqueue_session_analytics_shape() -> None:
    arq = FakeArq()
    await enqueue_session_analytics(arq, user_id="u1", session_id="s1", transcript="hi")  # type: ignore[arg-type]
    (args, kwargs) = arq.calls[0]
    assert args == ("run",)
    assert kwargs["_job_name"] == "compute_session_analytics"
    assert kwargs["user_id"] == "u1"
    assert kwargs["session_id"] == "s1"
    assert kwargs["transcript"] == "hi"
    assert kwargs["_job_id"].startswith("analytics:")


async def test_enqueue_session_analytics_job_id_ignores_transcript() -> None:
    arq = FakeArq()
    await enqueue_session_analytics(arq, user_id="u1", session_id="s1", transcript="a")  # type: ignore[arg-type]
    await enqueue_session_analytics(arq, user_id="u1", session_id="s1", transcript="b" * 99)  # type: ignore[arg-type]
    assert arq.calls[0][1]["_job_id"] == arq.calls[1][1]["_job_id"]


async def test_enqueue_extract_knowledge_shape() -> None:
    arq = FakeArq()
    await enqueue_extract_knowledge(arq, user_id="u1", session_id="s1", transcript="hello")  # type: ignore[arg-type]
    (_, kwargs) = arq.calls[0]
    assert kwargs["_job_name"] == "extract_knowledge"
    assert kwargs["_job_id"].startswith("extract:")


async def test_enqueue_grammar_scan_handles_none_session() -> None:
    arq = FakeArq()
    await enqueue_grammar_scan(arq, user_id="u1", session_id=None, text="some text")  # type: ignore[arg-type]
    (_, kwargs) = arq.calls[0]
    assert kwargs["_job_name"] == "grammar_scan"
    assert kwargs["session_id"] is None
    assert kwargs["text"] == "some text"
    assert kwargs["_job_id"].startswith("grammar:")


async def test_enqueue_compute_embeddings_job_id_is_per_user() -> None:
    arq = FakeArq()
    await enqueue_compute_embeddings(arq, user_id="u1")  # type: ignore[arg-type]
    (_, kwargs) = arq.calls[0]
    assert kwargs["_job_name"] == "compute_embeddings"
    assert kwargs["_job_id"] == "embed:u1"


async def test_enqueue_rolling_summarize_per_turn_unique_id() -> None:
    arq = FakeArq()
    await enqueue_rolling_summarize(arq, user_id="u1", session_id="s1", turn_index=20)  # type: ignore[arg-type]
    await enqueue_rolling_summarize(arq, user_id="u1", session_id="s1", turn_index=40)  # type: ignore[arg-type]
    a = arq.calls[0][1]
    b = arq.calls[1][1]
    assert a["_job_name"] == "rolling_summarize"
    assert a["turn_index"] == 20 and b["turn_index"] == 40
    assert a["_job_id"].startswith("rollsum:")
    assert a["_job_id"] != b["_job_id"]  # different checkpoint -> different job
