"""Claude/Codex rate-limit foizi: `GET /api/limits`.

Har ikkalasi ham faqat lokal fayllardan o'qiladi (bkg: `services/limits.py`); KanBot ishlamasa
Codex qismi shunchaki `available: false` bo'lib qaytadi, xato bermaydi.
"""

from __future__ import annotations

import time
from typing import Any

from fastapi import APIRouter

from agent_hub.services.limits import AgentLimits, Window

from .deps import HubDep

router = APIRouter(prefix="/api/limits")


def _window_view(window: Window | None) -> dict[str, Any] | None:
    if window is None:
        return None
    return {"used_percent": window.used_percent, "resets_at": window.resets_at}


def limits_view(item: AgentLimits) -> dict[str, Any]:
    return {
        "agent": item.agent,
        "available": item.available,
        "five_hour": _window_view(item.five_hour),
        "weekly": _window_view(item.weekly),
        "updated_at": item.updated_at,
        "stale": item.stale,
    }


@router.get("")
async def get_limits(hub: HubDep) -> dict[str, Any]:
    now = time.time()
    live = await hub.live_or_none()
    codex_sessions = live.sessions if live is not None else ()
    return {
        "claude": limits_view(hub.limits.claude(now=now)),
        "codex": limits_view(hub.limits.codex(codex_sessions, now=now)),
    }
