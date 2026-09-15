"""Vazifalar doskasi, vazifa detali va Backlog CLI orqali mutatsiyalar."""

from __future__ import annotations

import asyncio
from collections import defaultdict
from dataclasses import asdict
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, Field

from agent_hub.backlog_client import BacklogClient
from agent_hub.kanbot_client import Pane
from agent_hub.registry import Project
from agent_hub.services.linking import panes_for_project

from .deps import Hub, HubDep, LiveData
from .errors import ApiError
from .views import TaskIndex, pane_view, project_view, sort_panes, task_view

router = APIRouter(prefix="/api/projects/{project_id}")

MAX_LINE = 200
MAX_TEXT = 20_000


class TaskCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(max_length=MAX_LINE)
    description: str | None = Field(default=None, max_length=MAX_TEXT)
    status: str | None = Field(default=None, max_length=MAX_LINE)
    labels: list[str] = Field(default_factory=list, max_length=20)
    assignees: list[str] = Field(default_factory=list, max_length=20)
    milestone: str | None = Field(default=None, max_length=MAX_LINE)
    acceptance_criteria: list[str] = Field(default_factory=list, max_length=50)


class StatusUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: str = Field(max_length=MAX_LINE)


class LabelsAdd(BaseModel):
    model_config = ConfigDict(extra="forbid")

    labels: list[str] = Field(min_length=1, max_length=20)


def _line(field: str, value: str, *, allow_comma: bool = True) -> str:
    """Bir qatorli qiymat: bo'sh emas, boshqaruv belgisiz; ro'yxat qiymatlarida vergul yo'q."""
    value = value.strip()
    invalid = not value or any(not ch.isprintable() for ch in value)
    if invalid or (not allow_comma and "," in value):
        raise ApiError(422, "field_invalid", field=field, value=value)
    return value


async def _check_status(backlog: BacklogClient, status: str) -> str:
    status = _line("status", status)
    allowed = await backlog.statuses()
    if status not in allowed:
        raise ApiError(422, "status_invalid", status=status, allowed=allowed)
    return status


def _sessions_by_task(
    project: Project, hub: Hub, index: TaskIndex, live: LiveData | None
) -> dict[str, list[dict[str, Any]]]:
    """Vazifa ID → shu loyihadagi unga bog'langan tirik pane'lar."""
    linked: dict[str, list[dict[str, Any]]] = defaultdict(list)
    if live is None:
        return linked
    panes: list[Pane] = panes_for_project(live.panes, project, hub.registry.load())
    titles = live.session_titles
    for pane in panes:
        task = index.for_pane(pane, titles) if pane.alive else None
        if task is not None:
            linked[task.id].append(pane_view(pane, live.states.get(pane.id), project.id, task))
    return {task_id: sort_panes(views) for task_id, views in linked.items()}


@router.get("/board")
async def board(hub: HubDep, project_id: str) -> dict[str, Any]:
    project = hub.project(project_id)
    backlog = hub.backlog(project)
    # KanBot ixtiyoriy: ishlamasa ham doska ochiladi (sessiyalar bo'sh).
    tasks, statuses, labels, milestones, live = await asyncio.gather(
        backlog.list_tasks(),
        backlog.statuses(),
        backlog.labels(),
        backlog.milestones(),
        hub.live_or_none(),
    )
    dod = await backlog.dod_progress(task.id for task in tasks)
    index = TaskIndex.build(backlog.task_prefix(), tasks)
    sessions = _sessions_by_task(project, hub, index, live)
    return {
        "project": project_view(project),
        "task_prefix": index.prefix,
        "statuses": statuses,
        "labels": labels,
        "milestones": [asdict(milestone) for milestone in milestones],
        "tasks": [task_view(task, dod[task.id], sessions.get(task.id, [])) for task in tasks],
        "kanbot_available": live is not None,
    }


@router.get("/tasks/{task_id}")
async def task_detail(hub: HubDep, project_id: str, task_id: str) -> dict[str, Any]:
    project = hub.project(project_id)
    backlog = hub.backlog(project)
    index, live = await asyncio.gather(TaskIndex.load(backlog), hub.live_or_none())
    summary = index.get(task_id)
    detail = await backlog.view_task(summary.id)
    sessions = _sessions_by_task(project, hub, index, live).get(summary.id, [])
    return {**task_view(detail, None, sessions), "kanbot_available": live is not None}


@router.post("/tasks", status_code=201)
async def create_task(hub: HubDep, project_id: str, body: TaskCreate) -> dict[str, Any]:
    backlog = hub.backlog(hub.project(project_id))
    task_id = await backlog.create_task(
        _line("title", body.title),
        description=body.description.strip() if body.description else None,
        status=await _check_status(backlog, body.status) if body.status else None,
        labels=[_line("labels", label, allow_comma=False) for label in body.labels],
        assignees=[_line("assignees", name, allow_comma=False) for name in body.assignees],
        milestone=_line("milestone", body.milestone) if body.milestone else None,
        acceptance_criteria=[_line("acceptance_criteria", ac) for ac in body.acceptance_criteria],
    )
    return {"id": task_id}


@router.post("/tasks/{task_id}/status")
async def set_status(
    hub: HubDep, project_id: str, task_id: str, body: StatusUpdate
) -> dict[str, Any]:
    backlog = hub.backlog(hub.project(project_id))
    task = (await TaskIndex.load(backlog)).get(task_id)
    status = await _check_status(backlog, body.status)
    await backlog.set_status(task.id, status)
    return {"id": task.id, "status": status}


@router.post("/tasks/{task_id}/labels")
async def add_labels(hub: HubDep, project_id: str, task_id: str, body: LabelsAdd) -> dict[str, Any]:
    backlog = hub.backlog(hub.project(project_id))
    task = (await TaskIndex.load(backlog)).get(task_id)
    labels = [_line("labels", label, allow_comma=False) for label in body.labels]
    await backlog.add_label(task.id, labels)
    return {"id": task.id, "labels": list(dict.fromkeys([*task.labels, *labels]))}
