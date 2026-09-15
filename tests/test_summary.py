from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from agent_hub.backlog_client import TaskSummary, parse_task_list
from agent_hub.kanbot_client import Pane
from agent_hub.services.state import EffectiveState, StateResolver
from agent_hub.services.summary import count_statuses, is_bug, summarize

FIXTURES = Path(__file__).parent / "fixtures"
STATUSES = ["To Do", "In Progress", "Done"]


def _tasks() -> list[TaskSummary]:
    return parse_task_list((FIXTURES / "backlog" / "task_list.json").read_text(encoding="utf-8"))


def _panes() -> list[Pane]:
    data = json.loads((FIXTURES / "kanbot" / "panes.json").read_text(encoding="utf-8"))
    return [Pane.model_validate(item) for item in data["panes"]]


def _task(**overrides: Any) -> TaskSummary:
    data: dict[str, Any] = {"id": "TASK-9", "title": "T", "status": "To Do"}
    data.update(overrides)
    return TaskSummary.model_validate(data)


def test_fixture_counts_match_task_list_json() -> None:
    tasks = _tasks()
    raw = json.loads((FIXTURES / "backlog" / "task_list.json").read_text(encoding="utf-8"))
    expected: dict[str, int] = dict.fromkeys(STATUSES, 0)
    for item in raw["tasks"]:
        expected[item["status"]] += 1

    summary = summarize(tasks, STATUSES, _panes())
    assert summary.status_counts == expected == {"To Do": 2, "In Progress": 1, "Done": 0}
    assert list(summary.status_counts) == STATUSES
    assert summary.total == len(raw["tasks"]) == 3
    assert (summary.bugs, summary.open_bugs) == (1, 1)  # TASK-1: label "Bug" + type bug
    # Fixture: bitta tirik blocked claude va bitta tugagan codex pane.
    assert (summary.active_sessions, summary.blocked_sessions) == (1, 1)
    assert summary.blocked
    assert summary.blocked_pane_ids == ("a1b2c3d4",)


def test_unknown_status_is_counted_after_config_statuses() -> None:
    tasks = [_task(status="Done"), _task(status="Review"), _task(status="To Do")]
    assert count_statuses(tasks, STATUSES) == {"To Do": 1, "In Progress": 0, "Done": 1, "Review": 1}
    assert list(count_statuses(tasks, STATUSES)) == [*STATUSES, "Review"]


def test_is_bug_case_insensitive_label_or_type() -> None:
    assert is_bug(_task(labels=["BUG"]))
    assert is_bug(_task(labels=["ui", " bug "]))
    assert is_bug(_task(type="Bug"))
    assert not is_bug(_task(labels=["bugfix", "debug"]))
    assert not is_bug(_task())


def test_bugs_counted_once_and_open_bugs_exclude_last_status() -> None:
    tasks = [
        _task(labels=["bug", "Bug"], type="bug"),
        _task(labels=["bug"], status="Done"),
        _task(labels=["feature"]),
    ]
    summary = summarize(tasks, STATUSES)
    assert (summary.bugs, summary.open_bugs) == (2, 1)
    assert (summary.active_sessions, summary.blocked_sessions, summary.blocked) == (0, 0, False)


def test_blocked_uses_effective_state() -> None:
    blocked, finished = _panes()
    working = blocked.model_copy(update={"id": "w1", "state": "working"})
    states = {
        blocked.id: EffectiveState("idle", "blocked", approximate=True),
        working.id: EffectiveState("working", "working", approximate=False),
    }
    summary = summarize(_tasks(), STATUSES, [blocked, finished, working], states)
    assert (summary.active_sessions, summary.blocked_sessions, summary.blocked) == (2, 0, False)


async def test_idle_notification_does_not_mark_project_blocked() -> None:
    async def idle_screen(pane_id: str) -> str:
        return "● Tayyor.\n\n│ >                │\n  ? for shortcuts\n"

    panes = _panes()
    resolver = StateResolver(idle_screen)
    summary = summarize(_tasks(), STATUSES, panes, await resolver.resolve_all(panes))
    assert (summary.active_sessions, summary.blocked) == (1, False)


def test_empty_statuses() -> None:
    summary = summarize([_task(status="X")], [])
    assert summary.status_counts == {"X": 1}
    assert summary.total == 1
