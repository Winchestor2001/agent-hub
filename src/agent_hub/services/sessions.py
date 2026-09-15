"""Claude/Codex sessiyalarini ishga tushirish va davom ettirish (faqat SAFE runner orqali)."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, cast

from agent_hub.kanbot_client import SESSION_AGENTS, AgentName, AgentSession, KanbotClient, Pane
from agent_hub.registry import Project
from agent_hub.services.linking import is_valid_session_id, is_within, real_path

SESSION_PROMPT_TEMPLATE = (
    "Работай только над {task_id}. Прочитай `backlog instructions overview` и задачу, "
    "переведи её в In Progress, напиши план и дождись моего одобрения перед кодом."
)
TITLE_SEPARATOR = " · "
MAX_TITLE_LENGTH = 120


class SessionError(Exception):
    def __init__(self, code: str, **params: Any) -> None:
        super().__init__(f"{code}: {params}")
        self.code = code
        self.params = params


@dataclass(frozen=True)
class TaskInfo:
    """Sessiya bog'lanadigan vazifa (ID va sarlavha bekloqdan olinadi)."""

    id: str
    title: str


def build_prompt(task: TaskInfo | None, extra: str = "") -> str:
    """Vazifa tanlangan bo'lsa prompt aynan `SESSION_PROMPT_TEMPLATE` bilan boshlanadi."""
    extra = extra.strip()
    if task is None:
        return extra
    prefix = SESSION_PROMPT_TEMPLATE.format(task_id=task.id)
    return f"{prefix}\n\n{extra}" if extra else prefix


def session_title(task: TaskInfo | None, fallback: str = "") -> str:
    title = f"{task.id}{TITLE_SEPARATOR}{task.title.strip()}" if task else fallback.strip()
    title = " ".join(title.split())
    return title if len(title) <= MAX_TITLE_LENGTH else title[: MAX_TITLE_LENGTH - 1] + "…"


def _agent(agent: str) -> AgentName:
    if agent not in SESSION_AGENTS:
        raise SessionError("agent_invalid", agent=agent, allowed=list(SESSION_AGENTS))
    return cast(AgentName, agent)


def _project_dir(project: Project, cwd: str | None) -> Path:
    """cwd loyiha papkalaridan biri bo'lishi shart (default — birinchisi)."""
    if not cwd:
        return _existing_dir(project.dirs[0])
    target = real_path(cwd)
    for directory in project.dirs:
        if real_path(directory) == target:
            return _existing_dir(directory)
    raise SessionError("cwd_outside_project", cwd=cwd, project=project.id)


def _existing_dir(directory: str | Path) -> Path:
    path = Path(directory)
    if not path.is_dir():
        raise SessionError("path_invalid", path=str(path))
    return path


def _resume_dir(project: Project, session: AgentSession) -> Path:
    """Resume faqat sessiyaning asl cwd'ida ishlaydi; u loyiha papkalari ichida bo'lishi shart."""
    if not any(is_within(session.cwd, directory) for directory in project.dirs):
        raise SessionError("cwd_outside_project", cwd=session.cwd, project=project.id)
    return _existing_dir(session.cwd)


class SessionService:
    def __init__(self, kanbot: KanbotClient) -> None:
        self._kanbot = kanbot

    async def _safe_runner_id(self, agent: str, runner_id: str = "") -> str:
        """Agentga ega, onlayn va auto-approve'siz runner; hech biri yo'q bo'lsa xato."""
        runners = [r for r in await self._kanbot.runners() if r.online]
        if runner_id:
            runners = [r for r in runners if r.id == runner_id]
            if not runners:
                raise SessionError("runner_offline", runner=runner_id)
        capable = [r for r in runners if agent in r.capabilities]
        if not capable:
            raise SessionError("agent_unavailable", agent=agent)
        safe = [r for r in capable if not r.auto_approve]
        if not safe:
            raise SessionError("runner_unsafe", agent=agent)
        return safe[0].id

    async def start(
        self,
        project: Project,
        agent: str,
        *,
        cwd: str | None = None,
        task: TaskInfo | None = None,
        prompt: str = "",
    ) -> Pane:
        name = _agent(agent)
        directory = _project_dir(project, cwd)
        runner_id = await self._safe_runner_id(name)
        return await self._kanbot.start_pane(
            name,
            prompt=build_prompt(task, prompt),
            cwd=str(directory),
            title=session_title(task, fallback=project.name),
            runner_id=runner_id,
        )

    async def resume(self, project: Project, session: AgentSession, *, title: str = "") -> Pane:
        """Asl cwd va runner'da, prompt'siz (codex resume prompt qabul qilmaydi)."""
        name = _agent(session.agent)
        if not is_valid_session_id(session.session_id):
            raise SessionError("session_id_invalid", session_id=session.session_id)
        _resume_dir(project, session)
        runner_id = await self._safe_runner_id(name, session.runner_id)
        return await self._kanbot.start_pane(
            name,
            cwd=session.cwd,
            resume=session.session_id,
            title=session_title(None, fallback=title or session.name),
            runner_id=runner_id,
        )
