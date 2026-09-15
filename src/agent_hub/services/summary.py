"""Loyiha kartochkasi uchun hisoblagichlar."""

from __future__ import annotations

from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field

from agent_hub.backlog_client import TaskSummary
from agent_hub.kanbot_client import Pane
from agent_hub.services.state import EffectiveState

BUG = "bug"


def is_bug(task: TaskSummary) -> bool:
    if (task.type or "").strip().lower() == BUG:
        return True
    return any(label.strip().lower() == BUG for label in task.labels)


@dataclass(frozen=True)
class ProjectSummary:
    # Config'dagi statuslar tartibida, keyin config'da yo'q statuslar.
    status_counts: dict[str, int]
    total: int
    bugs: int
    open_bugs: int
    active_sessions: int
    blocked_sessions: int
    blocked_pane_ids: tuple[str, ...] = field(default=())

    @property
    def blocked(self) -> bool:
        return self.blocked_sessions > 0


def count_statuses(tasks: Iterable[TaskSummary], statuses: Sequence[str]) -> dict[str, int]:
    counts = dict.fromkeys(statuses, 0)
    for task in tasks:
        counts[task.status] = counts.get(task.status, 0) + 1
    return counts


def summarize(
    tasks: Sequence[TaskSummary],
    statuses: Sequence[str],
    panes: Iterable[Pane] = (),
    states: Mapping[str, EffectiveState] | None = None,
) -> ProjectSummary:
    """`panes` — shu loyihaga tegishli pane'lar; `states` — `StateResolver.resolve_all` natijasi."""
    done_status = statuses[-1] if statuses else None
    bugs = [task for task in tasks if is_bug(task)]
    live = [pane for pane in panes if pane.alive and pane.state != "done"]
    states = states or {}
    blocked = tuple(
        pane.id
        for pane in live
        if (states[pane.id].state if pane.id in states else pane.state) == "blocked"
    )
    return ProjectSummary(
        status_counts=count_statuses(tasks, statuses),
        total=len(tasks),
        bugs=len(bugs),
        open_bugs=sum(1 for task in bugs if task.status != done_status),
        active_sessions=len(live),
        blocked_sessions=len(blocked),
        blocked_pane_ids=blocked,
    )
