"""Loyihalar registri va loyiha hisoblagichlari."""

from __future__ import annotations

import asyncio
from collections.abc import Sequence
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, Field

from agent_hub.backlog_client import BacklogError
from agent_hub.registry import Project, validate_project
from agent_hub.services.linking import panes_for_project
from agent_hub.services.summary import summarize

from .deps import Hub, HubDep, LiveData
from .errors import error_body
from .views import project_view, summary_view

router = APIRouter(prefix="/api/projects")


class ProjectCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(max_length=40)
    name: str = Field(max_length=100)
    backlog_dir: str = Field(max_length=1024)
    repos: list[str] = Field(default_factory=list, max_length=20)


async def project_summary(
    hub: Hub, project: Project, projects: Sequence[Project], live: LiveData | None
) -> dict[str, Any]:
    """Bekloq o'qilmasa `BacklogError`."""
    backlog = hub.backlog(project)
    tasks, statuses = await asyncio.gather(backlog.list_tasks(), backlog.statuses())
    panes = panes_for_project(live.panes, project, projects) if live else []
    summary = summarize(tasks, statuses, panes, live.states if live else None)
    return summary_view(summary, kanbot_available=live is not None)


@router.get("")
async def list_projects(hub: HubDep) -> dict[str, Any]:
    projects = hub.registry.load()
    live = await hub.live_or_none()

    async def item(project: Project) -> dict[str, Any]:
        view = project_view(project)
        try:
            view["summary"] = await project_summary(hub, project, projects, live)
            view["error"] = None
        except BacklogError as exc:
            # Bitta buzilgan bekloq butun ro'yxatni to'xtatmasin.
            view["summary"] = None
            view["error"] = error_body(exc.code, exc.params, str(exc))
        return view

    items = await asyncio.gather(*(item(project) for project in projects))
    return {"projects": list(items), "kanbot_available": live is not None}


@router.post("", status_code=201)
async def add_project(hub: HubDep, body: ProjectCreate) -> dict[str, Any]:
    project = validate_project(body.id, body.name, body.backlog_dir, body.repos)
    return project_view(hub.registry.add(project))


@router.delete("/{project_id}")
async def remove_project(hub: HubDep, project_id: str) -> dict[str, Any]:
    project = hub.project(project_id)
    hub.registry.remove(project_id)
    if all(p.backlog_dir != project.backlog_dir for p in hub.registry.load()):
        hub.forget_backlog(project)
    return {"ok": True}


@router.get("/{project_id}/summary")
async def get_summary(hub: HubDep, project_id: str) -> dict[str, Any]:
    project = hub.project(project_id)
    live = await hub.live_or_none()
    summary = await project_summary(hub, project, hub.registry.load(), live)
    return {**project_view(project), "summary": summary, "kanbot_available": live is not None}
