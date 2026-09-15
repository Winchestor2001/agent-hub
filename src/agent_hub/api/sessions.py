"""Agent sessiyalari: jonli pane'lar, o'tgan sessiyalar, ishga tushirish, davom ettirish."""

from __future__ import annotations

import asyncio
from typing import Any

from fastapi import APIRouter, Query
from pydantic import BaseModel, ConfigDict, Field

from agent_hub.registry import Project
from agent_hub.services.linking import project_for_path
from agent_hub.services.sessions import TaskInfo, session_title

from .deps import Hub, HubDep
from .errors import ApiError
from .views import TaskIndex, pane_view, past_session_view, sort_panes

router = APIRouter()

MAX_PROMPT = 20_000


class SessionStart(BaseModel):
    model_config = ConfigDict(extra="forbid")

    agent: str = Field(max_length=20)
    cwd: str | None = Field(default=None, max_length=1024)
    task_id: str | None = Field(default=None, max_length=40)
    prompt: str = Field(default="", max_length=MAX_PROMPT)


class SessionResume(BaseModel):
    """Faqat sessiya kaliti: cwd va runner KanBot ro'yxatidan olinadi, klientdan emas."""

    model_config = ConfigDict(extra="forbid")

    agent: str = Field(max_length=20)
    session_id: str = Field(max_length=64)


async def _indexes(hub: Hub, projects: list[Project]) -> dict[str, TaskIndex | None]:
    """Bog'lash uchun vazifa indekslari; bekloqi o'qilmagan loyiha — `None` (bog'lanmaydi)."""
    loaded = await asyncio.gather(
        *(TaskIndex.load_or_none(hub.backlog(project)) for project in projects)
    )
    return {project.id: index for project, index in zip(projects, loaded, strict=True)}


@router.get("/api/sessions")
async def list_sessions(
    hub: HubDep,
    project: str | None = Query(default=None, max_length=40),
    past_limit: int = Query(default=50, ge=0, le=500),
) -> dict[str, Any]:
    projects = hub.registry.load()
    if project is not None:
        hub.project(project)  # 404 project_not_found
    # KanBot ishlamasa KanbotUnavailable → 503 kanbot_unavailable.
    live = await hub.live()
    indexes = await _indexes(hub, projects)
    titles = live.session_titles

    live_views = []
    for pane in live.panes:
        if not pane.alive:
            continue
        owner = project_for_path(pane.cwd, projects)
        if project is not None and (owner is None or owner.id != project):
            continue
        index = indexes.get(owner.id) if owner else None
        task = index.for_pane(pane, titles) if index else None
        live_views.append(
            pane_view(pane, live.states.get(pane.id), owner.id if owner else None, task)
        )

    past_views = []
    for session in live.sessions:
        # Loyihadan tashqaridagi sessiyani davom ettirib bo'lmaydi — ro'yxatga ham kirmaydi.
        owner = project_for_path(session.cwd, projects)
        if owner is None or (project is not None and owner.id != project):
            continue
        index = indexes.get(owner.id)
        past_views.append(
            past_session_view(session, owner.id, index.for_session(session) if index else None)
        )
    past_views.sort(key=lambda view: view["mtime"], reverse=True)

    return {"live": sort_panes(live_views), "past": past_views[:past_limit]}


@router.post("/api/projects/{project_id}/sessions", status_code=201)
async def start_session(hub: HubDep, project_id: str, body: SessionStart) -> dict[str, Any]:
    project = hub.project(project_id)
    task = None
    if body.task_id:
        task = (await TaskIndex.load(hub.backlog(project))).get(body.task_id)
    pane = await hub.sessions.start(
        project,
        body.agent,
        cwd=body.cwd,
        task=TaskInfo(task.id, task.title) if task else None,
        prompt=body.prompt,
    )
    return pane_view(pane, None, project.id, task)


@router.post("/api/projects/{project_id}/sessions/resume", status_code=201)
async def resume_session(hub: HubDep, project_id: str, body: SessionResume) -> dict[str, Any]:
    project = hub.project(project_id)
    sessions = await hub.kanbot.list_agent_sessions()
    session = next(
        (s for s in sessions if s.agent == body.agent and s.session_id == body.session_id), None
    )
    if session is None:
        raise ApiError(404, "session_not_found", agent=body.agent, session_id=body.session_id)
    if session.active:
        raise ApiError(409, "session_active", session_id=session.session_id)
    index = await TaskIndex.load_or_none(hub.backlog(project))
    task = index.for_session(session) if index else None
    # Vazifa ID'si pane sarlavhasida qolsa, davom ettirilgan sessiya ham vazifaga bog'lanadi.
    title = session_title(TaskInfo(task.id, task.title)) if task else (session.title or "")
    pane = await hub.sessions.resume(project, session, title=title)
    return pane_view(pane, None, project.id, task)


@router.post("/api/sessions/{pane_id}/kill")
async def kill_session(hub: HubDep, pane_id: str) -> dict[str, Any]:
    try:
        await hub.kanbot.kill_pane(pane_id)
    except ValueError as exc:
        raise ApiError(422, "pane_id_invalid", pane_id=pane_id) from exc
    return {"ok": True}
