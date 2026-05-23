"""score_scenario worker — grades a finished roleplay against its scenario.

Enqueued from end_session when the ended session was started from a
scenario. Reuses ``evaluate_conversation_mission`` and awards XP on a pass.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from bubbles.ai.extraction import evaluate_conversation_mission
from bubbles.core.logging import get_logger
from bubbles.db.repo import scenarios as scenarios_repo
from bubbles.db.repo import session_logs as session_logs_repo
from bubbles.db.repo import xp as xp_repo
from bubbles.db.uow import UnitOfWork, transaction

log = get_logger(__name__)

_XP_SCENARIO_PASS = 40
_MIN_TURNS = 4


async def run(ctx: dict[str, Any], *, scenario_id: str) -> dict[str, Any]:
    """Grade the scenario's linked session; persist pass/fail + feedback."""
    bub = ctx["bubbles"]
    sid = UUID(scenario_id)
    async with transaction(bub.pool) as conn:
        scenario = await scenarios_repo.get(conn, sid)
        if scenario is None or scenario.session_id is None:
            return {"scored": False, "reason": "no linked session"}
        transcript = await session_logs_repo.assemble_transcript(
            conn, session_id=scenario.session_id
        )
        user_turns = await session_logs_repo.role_count(
            conn, session_id=scenario.session_id, role="user"
        )
    if not transcript:
        return {"scored": False, "reason": "empty transcript"}

    passed, reason = await evaluate_conversation_mission(
        bub.ai.router,
        criteria=f"{scenario.goal}\n{scenario.success_criteria}",
        transcript=transcript,
        min_turns=_MIN_TURNS,
        user_turns=user_turns,
    )
    async with UnitOfWork(bub.pool) as uow:
        await scenarios_repo.mark_completed(
            uow.conn, scenario_id=sid, passed=passed, feedback=reason
        )
        if passed:
            await xp_repo.record(
                uow.conn,
                user_id=scenario.user_id,
                amount=_XP_SCENARIO_PASS,
                source_type="scenario",
                source_id=str(sid),
                description="Completed a roleplay scenario",
            )
    log.info("score_scenario_done", scenario=scenario_id, passed=passed)
    return {"scored": True, "passed": passed}
