"""Grammar check routes.

For each user turn we ask the LLM (JSON-mode) to flag mistakes; if any are
returned and the route is wired to a session, we persist them. We don't run
``language_tool_python`` synchronously inside the request — instead it runs
in an ARQ worker (Phase 6) so the route stays fast.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from fastapi import APIRouter

from bubbles.ai.extraction import correct_grammar
from bubbles.api.v1._schemas import (
    CheckUserTurnRequest,
    CheckUserTurnResponse,
    MistakeOut,
    UserMistakesResponse,
)
from bubbles.auth.current_user import CurrentUserDep
from bubbles.db.repo import grammar as grammar_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep, RouterDep

router = APIRouter(tags=["grammar"])


def _normalise_mistakes(raw: list[dict[str, Any]]) -> list[MistakeOut]:
    out: list[MistakeOut] = []
    for m in raw:
        category = (m.get("category") or "other").strip()
        snippet = (m.get("snippet") or "").strip()
        if not snippet:
            continue
        out.append(
            MistakeOut(
                category=category,
                snippet=snippet,
                suggestion=(m.get("suggestion") or "").strip() or None,
                source="llm",
                rule_id=f"LLM_{category.upper()}",
            )
        )
    return out


@router.post("/check_user_turn", response_model=CheckUserTurnResponse)
async def check_user_turn(
    body: CheckUserTurnRequest,
    user: CurrentUserDep,
    llm_router: RouterDep,
    pool: PoolDep,
) -> CheckUserTurnResponse:
    payload = await correct_grammar(llm_router, body.text)
    mistakes = _normalise_mistakes(payload.get("mistakes") or [])

    if mistakes:
        async with UnitOfWork(pool) as uow:
            await grammar_repo.bulk_insert(
                uow.conn,
                user_id=UUID(user.id),
                session_id=body.session_id,
                mistakes=[
                    {
                        "rule_id": m.rule_id,
                        "category": m.category,
                        "snippet": m.snippet,
                        "suggestion": m.suggestion or "",
                        "source": m.source,
                    }
                    for m in mistakes
                ],
            )

    return CheckUserTurnResponse(
        is_correct=bool(payload.get("is_correct")) and not mistakes,
        corrected=payload.get("corrected"),
        mistakes=mistakes,
    )


@router.get("/user_mistakes", response_model=UserMistakesResponse)
async def list_user_mistakes(
    user: CurrentUserDep,
    pool: PoolDep,
    limit: int = 100,
) -> UserMistakesResponse:
    async with transaction(pool) as conn:
        rows = await grammar_repo.list_for_user(conn, user_id=UUID(user.id), limit=min(limit, 500))
        counts = await grammar_repo.category_counts(conn, user_id=UUID(user.id))
    return UserMistakesResponse(
        items=[
            MistakeOut(
                category=r.category,
                snippet=r.snippet,
                suggestion=r.suggestion,
                source=r.source,
                rule_id=r.rule_id,
            )
            for r in rows
        ],
        counts=counts,
    )
