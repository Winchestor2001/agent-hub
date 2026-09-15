"""`/api/health` — KanBot ulanishi va xavfsizlik sozlamalari."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter

from agent_hub import __version__
from agent_hub.kanbot_client import KanbotError
from agent_hub.kanbot_safety import Problem, check_config, check_runners, check_version

from .deps import HubDep

router = APIRouter()


@router.get("/api/health")
async def health(hub: HubDep) -> dict[str, Any]:
    client = hub.kanbot
    problems: list[Problem] = list(check_config(hub.settings.kanbot_config))
    kanbot_info: dict[str, Any] = {"url": client.base_url, "reachable": False}
    try:
        kb_health = await client.health()
        runners = await client.runners()
    except KanbotError as exc:
        problems.append(Problem("kanbot_unavailable", "error", {"error": str(exc)}))
    else:
        kanbot_info.update(
            reachable=True,
            version=kb_health.version,
            runners_online=sum(1 for r in runners if r.online),
            agents=sorted({a for r in runners if r.online for a in r.capabilities}),
        )
        problems.extend(check_version(kb_health.version))
        problems.extend(check_runners(runners))
    return {
        "ok": not any(p.severity == "error" for p in problems),
        "version": __version__,
        "kanbot": kanbot_info,
        "problems": [p.as_dict() for p in problems],
    }
