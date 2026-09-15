"""Agent sessiyalari: jonli pane'lar, o'tgan sessiyalar, ishga tushirish, davom ettirish."""

from __future__ import annotations

import asyncio
from typing import Any

from fastapi import APIRouter, Query
from pydantic import BaseModel, ConfigDict, Field

from agent_hub.kanbot_client import SESSION_AGENTS
from agent_hub.registry import Project
from agent_hub.services.linking import live_session_ids, project_for_path
from agent_hub.services.sessions import SESSION_PROMPT_TEMPLATE, TaskInfo, session_title

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


@router.get("/api/sessions/options")
async def session_options() -> dict[str, Any]:
    """Yangi sessiya dialogi uchun: ruxsat etilgan agentlar va prompt prefiksi (`{task_id}`)."""
    return {"agents": list(SESSION_AGENTS), "prompt_template": SESSION_PROMPT_TEMPLATE}


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

    live_views: list[dict[str, Any]] = []
    # Chiqib ketgan pane'lar: KanBot ~2 soat saqlaydi, foydalanuvchi ro'yxatdan olib tashlaydi.
    finished_views: list[dict[str, Any]] = []
    for pane in live.panes:
        owner = project_for_path(pane.cwd, projects)
        if project is not None and (owner is None or owner.id != project):
            continue
        index = indexes.get(owner.id) if owner else None
        task = index.for_pane(pane, titles) if index else None
        view = pane_view(pane, live.states.get(pane.id), owner.id if owner else None, task)
        (live_views if pane.alive else finished_views).append(view)
    finished_views.sort(key=lambda view: view["ended_at"] or 0.0, reverse=True)

    # Tirik pane'dagi sessiya «Jonli agentlar»da turibdi — o'tganlarda takrorlanmaydi.
    open_ids = live_session_ids(live.panes, live.sessions)
    past_views = []
    for session in live.sessions:
        if session.session_id in open_ids:
            continue
        # Loyihadan tashqaridagi sessiyani davom ettirib bo'lmaydi — ro'yxatga ham kirmaydi.
        owner = project_for_path(session.cwd, projects)
        if owner is None or (project is not None and owner.id != project):
            continue
        index = indexes.get(owner.id)
        task = index.for_session(session) if index else None
        past_views.append(past_session_view(session, owner.id, task, active=session.active))
    past_views.sort(key=lambda view: view["mtime"], reverse=True)

    return {
        "live": sort_panes(live_views),
        "finished": finished_views,
        "past": past_views[:past_limit],
    }


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
    live = await hub.live()
    session = next(
        (s for s in live.sessions if s.agent == body.agent and s.session_id == body.session_id),
        None,
    )
    if session is None:
        raise ApiError(404, "session_not_found", agent=body.agent, session_id=body.session_id)
    if session.active or session.session_id in live_session_ids(live.panes, live.sessions):
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


@router.delete("/api/sessions/{pane_id}")
async def remove_session(hub: HubDep, pane_id: str) -> dict[str, Any]:
    """Tugagan pane'ni KanBot ro'yxatidan olib tashlaydi.

    KanBot tirik pane'ni olib tashlashda SIGKILL qiladi: agent bu yo'l bilan o'ldirilmasin.
    """
    try:
        pane = await hub.kanbot.get_pane(pane_id)
    except ValueError as exc:
        raise ApiError(422, "pane_id_invalid", pane_id=pane_id) from exc
    if pane.alive:
        raise ApiError(409, "pane_alive", pane_id=pane_id)
    await hub.kanbot.remove_pane(pane_id)
    return {"ok": True}
