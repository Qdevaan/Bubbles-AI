"""Background grammar scan via LanguageTool.

Runs in the worker so the request path stays fast. The LT JVM is loaded
lazily on first call and cached on the function attribute.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from bubbles.core.logging import get_logger
from bubbles.db.repo import grammar as grammar_repo
from bubbles.db.uow import UnitOfWork

log = get_logger(__name__)

_lt_instance: Any | None = None


def _get_lt() -> Any:
    global _lt_instance
    if _lt_instance is None:
        import language_tool_python

        _lt_instance = language_tool_python.LanguageTool("en-US")
    return _lt_instance


async def run(
    ctx: dict[str, Any],
    *,
    user_id: str,
    session_id: str | None,
    text: str,
) -> int:
    bub = ctx["bubbles"]
    lt = _get_lt()
    matches = lt.check(text)
    if not matches:
        return 0

    payload: list[dict[str, str]] = []
    for m in matches:
        snippet = text[m.offset : m.offset + m.errorLength].strip()
        if not snippet:
            continue
        suggestion = (m.replacements[0] if m.replacements else "").strip()
        payload.append(
            {
                "rule_id": str(m.ruleId or "LT_UNKNOWN"),
                "category": str(m.category or "other").strip().lower(),
                "snippet": snippet,
                "suggestion": suggestion,
                "source": "lt",
            }
        )

    if not payload:
        return 0

    async with UnitOfWork(bub.pool) as uow:
        await grammar_repo.bulk_insert(
            uow.conn,
            user_id=UUID(user_id),
            session_id=UUID(session_id) if session_id else None,
            mistakes=payload,
        )
    log.info("grammar_scan_done", user=user_id, n=len(payload))
    return len(payload)
