# Purpose: Memory endpoints: list and search the user's rolling-summary memory store built from past sessions.
"""Memory admin routes."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Response

from bubbles.auth.current_user import CurrentUserDep, require_ownership
from bubbles.core.errors import NotFound
from bubbles.db.repo import memories as memories_repo
from bubbles.db.uow import UnitOfWork, transaction
from bubbles.deps import PoolDep

router = APIRouter(tags=["memories"])


@router.delete("/memories/{memory_id}", status_code=204, response_class=Response)
async def delete_memory(
    memory_id: UUID,
    user: CurrentUserDep,
    pool: PoolDep,
) -> Response:
    async with transaction(pool) as conn:
        mem = await memories_repo.get(conn, memory_id)
    if mem is None:
        raise NotFound("memory not found")
    require_ownership(user, str(mem.user_id))
    async with UnitOfWork(pool) as uow:
        ok = await memories_repo.soft_delete(uow.conn, memory_id=memory_id, user_id=UUID(user.id))
    if not ok:
        raise NotFound("memory not found")
    return Response(status_code=204)
