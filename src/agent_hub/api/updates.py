"""Agent CLI'lari versiyalari va yangilash: `GET /api/updates`, `POST /api/updates/{agent}`.

`POST` yangilashni boshlaydi va 202 bilan darhol qaytadi; borishi `GET` dagi `running` va `last`
orqali kuzatiladi.
"""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Path

from agent_hub.services.updates import AgentUpdate

from .deps import HubDep

router = APIRouter(prefix="/api/updates")

AgentName = Annotated[str, Path(max_length=40)]


def update_view(item: AgentUpdate) -> dict[str, Any]:
    last = item.last
    return {
        "agent": item.agent,
        "cask": item.cask,
        "installed_version": item.installed,
        "latest_version": item.latest,
        "outdated": item.outdated,
        "running": item.running,
        "last": None
        if last is None
        else {
            "ok": last.ok,
            "exit_code": last.exit_code,
            "finished_at": last.finished_at,
            "output": last.output,
        },
    }


@router.get("")
async def list_updates(hub: HubDep) -> dict[str, Any]:
    updates = hub.updates
    return {
        "brew": updates.brew_available,
        "agents": [update_view(item) for item in await updates.status()],
    }


@router.post("/{agent}", status_code=202)
async def start_update(hub: HubDep, agent: AgentName) -> dict[str, Any]:
    await hub.updates.start(agent)
    return update_view(await hub.updates.agent_status(agent))
