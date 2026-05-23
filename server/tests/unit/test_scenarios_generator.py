"""Unit tests for the scenario generator's pure JSON parser."""

from __future__ import annotations

import json
from uuid import uuid4

from bubbles.ai.scenarios import parse_scenarios


def _item(**over: object) -> dict[str, object]:
    base: dict[str, object] = {
        "target_person": "Sarah",
        "title": "Ask for a raise",
        "situation": "You meet your manager.",
        "goal": "Negotiate confidently",
        "success_criteria": "Made the ask",
        "difficulty": "hard",
        "role_mode": "busy",
        "opening_line": "You wanted to see me?",
        "source_refs": [],
    }
    base.update(over)
    return base


def test_parse_valid_scenario_remaps_refs() -> None:
    pid, tid = uuid4(), uuid4()
    text = json.dumps({"scenarios": [_item(source_refs=["T0"])]})
    rows = parse_scenarios(
        text,
        people_by_name={"sarah": pid},
        task_refs={"T0": tid},
        event_refs={},
        limit=5,
    )
    assert len(rows) == 1
    assert rows[0].target_entity_id == pid
    assert rows[0].difficulty == "hard"
    assert rows[0].source["tasks"] == [str(tid)]
    assert rows[0].source["events"] == []


def test_parse_drops_unknown_person() -> None:
    text = json.dumps({"scenarios": [_item(target_person="ghost")]})
    rows = parse_scenarios(
        text, people_by_name={"sarah": uuid4()}, task_refs={}, event_refs={}, limit=5
    )
    assert rows == []


def test_parse_drops_missing_required_field() -> None:
    text = json.dumps({"scenarios": [_item(title="")]})
    rows = parse_scenarios(
        text, people_by_name={"sarah": uuid4()}, task_refs={}, event_refs={}, limit=5
    )
    assert rows == []


def test_parse_bad_difficulty_falls_back_to_medium() -> None:
    text = json.dumps({"scenarios": [_item(difficulty="impossible")]})
    rows = parse_scenarios(
        text, people_by_name={"sarah": uuid4()}, task_refs={}, event_refs={}, limit=5
    )
    assert len(rows) == 1
    assert rows[0].difficulty == "medium"


def test_parse_invalid_json_returns_empty() -> None:
    rows = parse_scenarios(
        "not json at all",
        people_by_name={"sarah": uuid4()},
        task_refs={},
        event_refs={},
        limit=5,
    )
    assert rows == []


def test_parse_respects_limit() -> None:
    text = json.dumps({"scenarios": [_item(title=f"t{i}") for i in range(5)]})
    rows = parse_scenarios(
        text, people_by_name={"sarah": uuid4()}, task_refs={}, event_refs={}, limit=2
    )
    assert len(rows) == 2
