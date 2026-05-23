"""Personalized roleplay scenario generator.

Builds practice scenarios from the user's knowledge graph (people, open
tasks, recent events). Used by the ``generate_scenarios`` worker (feed
top-up) and ``POST /v1/scenarios/generate`` (on-demand). ``generate`` never
raises — a failure yields an empty list and the caller degrades.
"""

from __future__ import annotations

import json
from typing import Any, Final
from uuid import UUID

import asyncpg

from bubbles.ai.prompts.loader import render
from bubbles.ai.providers.base import ChatMessage, Role
from bubbles.ai.router import LLMRouter
from bubbles.core.errors import UpstreamUnavailable
from bubbles.core.logging import get_logger
from bubbles.db.repo import entities as entities_repo
from bubbles.db.repo import personas as personas_repo
from bubbles.db.repo import scenarios as scenarios_repo

log = get_logger(__name__)

_VALID_DIFFICULTY: Final[frozenset[str]] = frozenset({"easy", "medium", "hard"})
_MAX_CANDIDATES: Final[int] = 12
_MAX_PEOPLE: Final[int] = 40


def parse_scenarios(
    text: str,
    *,
    people_by_name: dict[str, UUID],
    task_refs: dict[str, UUID],
    event_refs: dict[str, UUID],
    limit: int,
) -> list[scenarios_repo.NewScenario]:
    """Parse the LLM JSON into validated ``NewScenario`` rows. Pure; never raises."""
    try:
        data: Any = json.loads(text)
    except (ValueError, TypeError):
        return []
    items = data.get("scenarios") if isinstance(data, dict) else None
    if not isinstance(items, list):
        return []

    out: list[scenarios_repo.NewScenario] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        person_id = people_by_name.get(str(item.get("target_person", "")).strip().lower())
        if person_id is None:
            continue  # grounded in an unknown person — drop
        title = str(item.get("title", "")).strip()
        situation = str(item.get("situation", "")).strip()
        goal = str(item.get("goal", "")).strip()
        criteria = str(item.get("success_criteria", "")).strip()
        opening = str(item.get("opening_line", "")).strip()
        if not (title and situation and goal and criteria and opening):
            continue
        difficulty = str(item.get("difficulty", "medium")).strip().lower()
        if difficulty not in _VALID_DIFFICULTY:
            difficulty = "medium"
        role_mode = str(item.get("role_mode", "default")).strip()[:60] or "default"
        raw_refs = item.get("source_refs")
        refs = [r for r in raw_refs if isinstance(r, str)] if isinstance(raw_refs, list) else []
        task_ids = [task_refs[r] for r in refs if r in task_refs]
        event_ids = [event_refs[r] for r in refs if r in event_refs]
        out.append(
            scenarios_repo.NewScenario(
                target_entity_id=person_id,
                title=title[:200],
                situation=situation,
                goal=goal,
                success_criteria=criteria,
                difficulty=difficulty,
                role_mode=role_mode,
                opening_line=opening,
                source={
                    "entity_id": str(person_id),
                    "tasks": [str(t) for t in task_ids],
                    "events": [str(e) for e in event_ids],
                },
            )
        )
        if len(out) >= limit:
            break
    return out


async def generate(
    conn: asyncpg.Connection,
    router: LLMRouter,
    *,
    user_id: UUID,
    count: int,
    target_entity_id: UUID | None = None,
) -> list[scenarios_repo.NewScenario]:
    """Generate up to ``count`` scenarios grounded in the user's graph.

    Returns ``[]`` on any failure — never raises.
    """
    if count <= 0:
        return []
    try:
        people = await entities_repo.list_for_user(conn, user_id=user_id, limit=_MAX_PEOPLE)
        people = [e for e in people if (e.entity_type or "").lower() == "person"]
        if target_entity_id is not None:
            people = [e for e in people if e.id == target_entity_id]
        if not people:
            return []

        used_tasks, used_events = await scenarios_repo.used_source_ids(conn, user_id=user_id)
        if target_entity_id is not None:
            name = people[0].display_name or people[0].canonical_name
            task_rows = await entities_repo.tasks_mentioning(
                conn, user_id=user_id, name=name, limit=_MAX_CANDIDATES
            )
            event_rows = await entities_repo.events_mentioning(
                conn, user_id=user_id, name=name, limit=_MAX_CANDIDATES
            )
            task_rows = [r for r in task_rows if r["id"] not in used_tasks]
            event_rows = [r for r in event_rows if r["id"] not in used_events]
        else:
            task_rows = await entities_repo.recent_tasks(
                conn, user_id=user_id, limit=_MAX_CANDIDATES, exclude_ids=used_tasks
            )
            event_rows = await entities_repo.recent_events(
                conn, user_id=user_id, limit=_MAX_CANDIDATES, exclude_ids=used_events
            )

        persona = await personas_repo.get(conn, user_id)
        persona_goals = list(persona.primary_goals) if persona is not None else []

        people_by_name = {
            (e.display_name or e.canonical_name).strip().lower(): e.id for e in people
        }
        task_refs = {f"T{i}": r["id"] for i, r in enumerate(task_rows)}
        event_refs = {f"E{i}": r["id"] for i, r in enumerate(event_rows)}

        prompt = render(
            "scenarios/generate.jinja",
            count=count,
            people=[
                {"name": e.display_name or e.canonical_name, "description": e.description or ""}
                for e in people
            ],
            tasks=[{"ref": f"T{i}", "title": r["title"]} for i, r in enumerate(task_rows)],
            events=[
                {"ref": f"E{i}", "title": r["title"], "due_text": r["due_text"] or ""}
                for i, r in enumerate(event_rows)
            ],
            persona_goals=persona_goals,
        )
        completion = await router.complete(
            "scenario.generate",
            [ChatMessage(role=Role.user, content=prompt)],
            response_format="json",
        )
    except UpstreamUnavailable as exc:
        log.warning("scenario_generate_upstream", error=str(exc), user_id=str(user_id))
        return []
    except Exception as exc:  # graph read failed — degrade, never raise
        log.warning("scenario_generate_failed", error=str(exc), user_id=str(user_id))
        return []

    return parse_scenarios(
        completion.text,
        people_by_name=people_by_name,
        task_refs=task_refs,
        event_refs=event_refs,
        limit=count,
    )
