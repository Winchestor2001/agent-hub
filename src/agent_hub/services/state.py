"""Sessiyaning UI'da ko'rsatiladigan holati (`effective_state`).

KanBot `blocked` holatini ikki joyda noto'g'ri beradi:

* Claude'ning `Notification` hook'i ruxsat so'rovidan tashqari, idle kutishda ham ishlaydi.
  Ruxsat berilgach ham keyingi hook kelguncha holat `blocked` bo'lib qoladi.
* Codex holati ekran regex'lari bilan aniqlanadi. Ular keng (yakka `permission`,
  `Would you like to`), shuning uchun agent matnidagi so'z ham `blocked` beradi.

Shu sabab `blocked` pane ekrani (`read_pane`) qat'iy tasdiqlash matnlari bilan qayta tekshiriladi.
Ekran boshqa holatni aniq ko'rsatsa, o'sha holat olinadi. Aniq bo'lmasa, oldingi holat `idle`
bo'lgandagina `idle` ko'rsatiladi. Qolgan hollarda `blocked` qoladi, chunki haqiqiy so'rovni
yashirishdan ko'ra ortiqcha ogohlantirish yaxshiroq.
"""

from __future__ import annotations

import asyncio
import re
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass
from typing import Literal

from agent_hub.kanbot_client import KanbotClient, KanbotError, Pane

SCREEN_LINES = 30

ScreenState = Literal["blocked", "working", "idle"]

# Claude Code 2.1 va Codex 0.154 binar fayllaridan olingan dialog matnlari.
_CLAUDE_APPROVAL = re.compile(
    r"Do you want to .{1,160}\?"
    r"|Would you like to proceed\?"
    r"|Yes, and don't ask again"
    r"|No, and tell Claude what to do differently"
    r"|Is this a project you created or one you trust\?"
    r"|Yes, I trust this folder"
    r"|Enter to (?:select|confirm)"
)
_CODEX_APPROVAL = re.compile(
    r"Would you like to (?:run the following command|make the following edits"
    r"|grant these permissions|send input to (?:the existing )?terminal)"
    r"|Yes, and don't ask again"
    r"|No, and tell Codex what to do differently"
    r"|Do you trust the contents of this directory"
)
_APPROVAL: dict[str, re.Pattern[str]] = {"claude": _CLAUDE_APPROVAL, "codex": _CODEX_APPROVAL}
_WORKING = re.compile(r"esc to interrupt", re.IGNORECASE)
# Bo'sh kiritish qatori (`>`, `│ > │`, `›`) yoki idle footer.
_IDLE = re.compile(r"^[\s│┃|]*[>❯›][\s│┃|]*$|\? for shortcuts")


def _last_index(lines: Sequence[str], pattern: re.Pattern[str]) -> int:
    for index in range(len(lines) - 1, -1, -1):
        if pattern.search(lines[index]):
            return index
    return -1


def classify_screen(text: str, agent: str) -> ScreenState | None:
    """Ekran oxiridan holatni qat'iy belgilar bo'yicha aniqlaydi; aniq bo'lmasa `None`."""
    lines = [line.rstrip() for line in text.splitlines() if line.strip()][-SCREEN_LINES:]
    approval = _last_index(lines, _APPROVAL.get(agent, _CLAUDE_APPROVAL))
    idle = _last_index(lines, _IDLE)
    if approval >= 0 and idle < approval:
        return "blocked"
    working = _last_index(lines, _WORKING)
    if working > approval:
        return "working"
    if idle >= 0:
        return "idle"
    return None


@dataclass(frozen=True)
class EffectiveState:
    state: str
    raw_state: str
    # Holat hook'dan emas, ekrandan taxminiy aniqlangan (UI'da "≈").
    approximate: bool

    @property
    def corrected(self) -> bool:
        return self.state != self.raw_state


ReadScreen = Callable[[str], Awaitable[str]]


class StateResolver:
    """Pane'lar holatini hisoblaydi; oldingi holatlar va ekran natijalari shu obyektda saqlanadi."""

    def __init__(self, read_screen: ReadScreen) -> None:
        self._read_screen = read_screen
        self._previous: dict[str, str] = {}
        self._screens: dict[str, tuple[float | None, ScreenState | None]] = {}

    @classmethod
    def for_kanbot(cls, client: KanbotClient) -> StateResolver:
        async def read(pane_id: str) -> str:
            return (await client.read_pane(pane_id, SCREEN_LINES)).text

        return cls(read)

    async def _screen_state(self, pane: Pane) -> ScreenState | None:
        cached = self._screens.get(pane.id)
        if cached is not None and cached[0] == pane.last_output_at:
            return cached[1]
        text = await self._read_screen(pane.id)
        state = classify_screen(text, pane.agent)
        self._screens[pane.id] = (pane.last_output_at, state)
        return state

    async def resolve(self, pane: Pane) -> EffectiveState:
        raw = pane.state
        approximate = pane.state_source == "screen"
        if raw != "blocked" or not pane.alive:
            self._previous[pane.id] = raw
            self._screens.pop(pane.id, None)
            return EffectiveState(raw, raw, approximate)

        try:
            screen = await self._screen_state(pane)
        except (KanbotError, ValueError):
            screen = None
        if screen is not None:
            state: str = screen
        elif self._previous.get(pane.id) == "idle":
            state = "idle"
        else:
            state = raw
        return EffectiveState(state, raw, approximate or state != raw)

    async def resolve_all(self, panes: Sequence[Pane]) -> dict[str, EffectiveState]:
        """Hamma pane'lar; ro'yxatda yo'q pane'larning xotirasi tozalanadi."""
        results = await asyncio.gather(*(self.resolve(pane) for pane in panes))
        alive_ids = {pane.id for pane in panes}
        for store in (self._previous, self._screens):
            for pane_id in set(store) - alive_ids:
                del store[pane_id]
        return {pane.id: result for pane, result in zip(panes, results, strict=True)}
