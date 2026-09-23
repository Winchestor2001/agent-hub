"""Routerlar uchun umumiy obyektlar: registr, klientlar va servislar."""

from __future__ import annotations

import asyncio
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated

from fastapi import Depends, Request

from agent_hub.backlog_client import BacklogClient
from agent_hub.kanbot_client import AgentSession, KanbotClient, KanbotError, Pane
from agent_hub.registry import Project, Registry
from agent_hub.services.limits import LimitsService
from agent_hub.services.sessions import SessionService
from agent_hub.services.state import EffectiveState, StateResolver
from agent_hub.services.updates import UpdateService
from agent_hub.settings import Settings

BacklogFactory = Callable[[Path], BacklogClient]


@dataclass(frozen=True)
class LiveData:
    """KanBot'dagi joriy pane'lar (holatlari bilan) va o'tgan agent sessiyalari."""

    panes: list[Pane]
    states: dict[str, EffectiveState]
    sessions: list[AgentSession]

    @property
    def session_titles(self) -> dict[str, str]:
        return {s.session_id: s.title or "" for s in self.sessions}


class Hub:
    def __init__(
        self,
        settings: Settings,
        registry: Registry,
        kanbot: KanbotClient,
        backlog_factory: BacklogFactory = BacklogClient,
    ) -> None:
        self.settings = settings
        self.registry = registry
        self.kanbot = kanbot
        self.sessions = SessionService(kanbot)
        self.state = StateResolver.for_kanbot(kanbot)
        self.updates = UpdateService.detect()
        self.limits = LimitsService.for_settings(settings)
        self._backlog_factory = backlog_factory
        self._backlogs: dict[Path, BacklogClient] = {}
        # Fayli o'chirilgan (agent, session_id): runner qayta skanerlaguncha KanBot ko'rsataveradi.
        self._deleted_sessions: set[tuple[str, str]] = set()

    def project(self, project_id: str) -> Project:
        return self.registry.get(project_id)

    def backlog(self, project: Project) -> BacklogClient:
        """Har bekloq papkasi uchun bitta klient (kesh shu obyektda)."""
        client = self._backlogs.get(project.backlog_dir)
        if client is None:
            client = self._backlogs[project.backlog_dir] = self._backlog_factory(
                project.backlog_dir
            )
        return client

    def backlog_at(self, directory: Path) -> BacklogClient:
        """Registrga kirmagan papka uchun keshsiz klient (masalan, `init`)."""
        return self._backlog_factory(directory)

    def forget_backlog(self, project: Project) -> None:
        self._backlogs.pop(project.backlog_dir, None)

    def mark_sessions_deleted(self, keys: Iterable[tuple[str, str]]) -> None:
        self._deleted_sessions.update(keys)

    async def live(self) -> LiveData:
        """KanBot ishlamasa `KanbotError` (odatda `KanbotUnavailable`)."""
        panes, reported = await asyncio.gather(
            self.kanbot.list_panes(), self.kanbot.list_agent_sessions()
        )
        keys = {(s.agent, s.session_id) for s in reported}
        # KanBot endi ko'rsatmayotganlari unutiladi — to'plam o'smaydi.
        self._deleted_sessions &= keys
        sessions = [s for s in reported if (s.agent, s.session_id) not in self._deleted_sessions]
        # resolve_all doim hamma pane'lar bilan: ro'yxatda yo'qlarning xotirasi tozalanadi.
        states = await self.state.resolve_all(panes)
        return LiveData(panes, states, sessions)

    async def live_or_none(self) -> LiveData | None:
        try:
            return await self.live()
        except KanbotError:
            return None


def get_hub(request: Request) -> Hub:
    hub: Hub = request.app.state.hub
    return hub


HubDep = Annotated[Hub, Depends(get_hub)]
