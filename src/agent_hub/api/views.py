"""API javoblari (JSON) va vazifa ↔ sessiya bog'lanishi."""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from typing import Any

from agent_hub.backlog_client import BacklogClient, BacklogError, TaskDetail, TaskSummary
from agent_hub.kanbot_client import AgentSession, Pane
from agent_hub.registry import Project
from agent_hub.services.linking import find_task_keys, index_task_ids, pane_task_key, task_key
from agent_hub.services.state import EffectiveState
from agent_hub.services.summary import ProjectSummary

from .errors import ApiError


@dataclass(frozen=True)
class TaskIndex:
    """Loyiha vazifalari kanonik kalit bo'yicha (`TASK-001` va `task-1` — bitta)."""

    prefix: str
    by_key: dict[str, TaskSummary]

    @classmethod
    def build(cls, prefix: str, tasks: Sequence[TaskSummary]) -> TaskIndex:
        ids = index_task_ids((task.id for task in tasks), prefix)
        by_id = {task.id: task for task in tasks}
        return cls(prefix, {key: by_id[task_id] for key, task_id in ids.items()})

    @classmethod
    async def load(cls, backlog: BacklogClient) -> TaskIndex:
        return cls.build(backlog.task_prefix(), await backlog.list_tasks())

    @classmethod
    async def load_or_none(cls, backlog: BacklogClient) -> TaskIndex | None:
        try:
            return await cls.load(backlog)
        except BacklogError:
            return None

    def key(self, task_id: str) -> str:
        """Yo'ldagi vazifa ID'si prefiksga mos bo'lmasa 422 (CLI'ga yuborilmaydi)."""
        key = task_key(task_id, self.prefix)
        if key is None:
            raise ApiError(422, "task_id_invalid", task_id=task_id, prefix=self.prefix)
        return key

    def get(self, task_id: str) -> TaskSummary:
        task = self.by_key.get(self.key(task_id))
        if task is None:
            raise ApiError(404, "task_not_found", task_id=task_id)
        return task

    def for_pane(self, pane: Pane, session_titles: dict[str, str]) -> TaskSummary | None:
        key = pane_task_key(pane, self.prefix, session_titles)
        return self.by_key.get(key) if key else None

    def for_session(self, session: AgentSession) -> TaskSummary | None:
        for text in (session.title or "", session.name):
            for key in find_task_keys(text, self.prefix):
                if key in self.by_key:
                    return self.by_key[key]
        return None


def task_ref(task: TaskSummary | None) -> dict[str, Any] | None:
    if task is None:
        return None
    return {"id": task.id, "title": task.title, "status": task.status}


def project_view(project: Project) -> dict[str, Any]:
    return {
        "id": project.id,
        "name": project.name,
        "backlog_dir": str(project.backlog_dir),
        "repos": [str(repo) for repo in project.repos],
        "dirs": [str(directory) for directory in project.dirs],
    }


def summary_view(summary: ProjectSummary, kanbot_available: bool) -> dict[str, Any]:
    return {
        "status_counts": [
            {"status": status, "count": count} for status, count in summary.status_counts.items()
        ],
        "total": summary.total,
        "bugs": summary.bugs,
        "open_bugs": summary.open_bugs,
        # KanBot ishlamasa sessiyalar sonini bilmaymiz — 0 emas, null.
        "active_sessions": summary.active_sessions if kanbot_available else None,
        "blocked_sessions": summary.blocked_sessions if kanbot_available else None,
        "blocked_pane_ids": list(summary.blocked_pane_ids),
    }


def pane_view(
    pane: Pane,
    state: EffectiveState | None,
    project_id: str | None,
    task: TaskSummary | None,
) -> dict[str, Any]:
    if state is None:
        state = EffectiveState(pane.state, pane.state, pane.state_source == "screen")
    return {
        "id": pane.id,
        "agent": pane.agent,
        "title": pane.title,
        "cwd": pane.cwd,
        "state": state.state,
        "raw_state": state.raw_state,
        "approximate": state.approximate,
        "alive": pane.alive,
        "session_id": pane.session_id,
        "runner_id": pane.runner_id,
        "runner_name": pane.runner_name,
        "started_at": pane.started_at,
        "last_output_at": pane.last_output_at,
        "ended_at": pane.ended_at,
        "exit_code": pane.exit_code,
        "project_id": project_id,
        "task": task_ref(task),
    }


def sort_panes(views: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Jonli pane'lar barqaror tartibda: eskisi tepada, boshlanish vaqti yo'qlari oxirda.

    Holat yoki oxirgi chiqish bo'yicha saralanmaydi — aks holda agent har safar chiqish
    berganda qator joyini almashtiradi va uni bosib bo'lmaydi.
    """

    def order(view: dict[str, Any]) -> tuple[bool, float, str]:
        started = view["started_at"]
        return started is None, started or 0.0, view["id"]

    return sorted(views, key=order)


def past_session_view(
    session: AgentSession, project_id: str | None, task: TaskSummary | None, *, active: bool
) -> dict[str, Any]:
    return {
        "agent": session.agent,
        "session_id": session.session_id,
        "cwd": session.cwd,
        "name": session.name,
        "title": session.title,
        "recap": session.recap,
        "turns": session.turns,
        "started_at": session.started_at,
        "mtime": session.mtime,
        "active": active,
        "runner_id": session.runner_id,
        "project_id": project_id,
        "task": task_ref(task),
    }


def task_view(
    task: TaskSummary, dod: tuple[int, int] | None, sessions: list[dict[str, Any]]
) -> dict[str, Any]:
    data: dict[str, Any] = task.model_dump(mode="json")
    if isinstance(task, TaskDetail):
        dod = task.dod_progress
    data["dod_completed"], data["dod_count"] = dod or (0, 0)
    data["sessions"] = sessions
    return data
