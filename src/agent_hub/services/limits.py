"""Claude va Codex CLI'larining joriy rate-limit foizi: faqat lokal fayllardan, tarmoqqa chiqmasdan.

Hech qaysi CLI bu ma'lumotni ochiq buyruq sifatida bermaydi:

- Codex har bir "turn"dan keyin joriy sessiya rollout fayliga
  (`~/.codex/sessions/**/rollout-*.jsonl`, `Settings.transcript_roots["codex"]` bilan bir xil papka)
  `payload.rate_limits.{primary,secondary}` yozadi (`used_percent`, `window_minutes`, `resets_at`).
  Qaysi maydonda (`primary`/`secondary`) qaysi oyna (5 soatlik yoki 7 kunlik) kelishi barqaror
  emas — `window_minutes` qiymati orqali aniqlanadi. Shu sababli eng so'nggi (mtime bo'yicha) Codex
  sessiyasi transkriptidan o'qiladi.
- Claude Code buni faqat interaktiv sessiya paytida `statusLine` buyrug'iga stdin JSON orqali
  beradi (`.rate_limits.five_hour/seven_day.{used_percentage,resets_at}`) va boshqa hech qanday
  faylga yozmaydi. Shuning uchun foydalanuvchining statusline skripti oxirgi qiymatni kichik
  keshga (`CLAUDE_CACHE_FILENAME`) yozib turishi kerak — shu servis o'sha keshni o'qiydi.

Ikkalasi ham faqat lokal fayl o'qiydi; ma'lumot yo'q yoki eskirgan bo'lsa xato emas,
`available=False` yoki `stale=True` bilan qaytadi.
"""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from agent_hub.kanbot_client import AgentSession
from agent_hub.services import transcripts
from agent_hub.settings import Settings

CLAUDE_CACHE_FILENAME = "agent-hub-rate-limits.json"
# Shundan ko'p eskirgan bo'lsa `stale=True` (tegishli CLI endi jonli emas, foiz baribir ko'rinadi).
STALE_AFTER = 20 * 60.0
# Codex rollout faylini oxiridan o'qishda shuncha bayt yetarli (rate_limits qatorlari kichik).
CODEX_TAIL_BYTES = 200_000
# Shu ko'p qatorni orqaga qarab skanerlab topilmasa — ma'lumot yo'q deb hisoblanadi.
CODEX_MAX_SCAN_LINES = 500

_FIVE_HOUR_MINUTES = 300
_WEEKLY_MINUTES = 10080
_WINDOW_TOLERANCE_MINUTES = 60


@dataclass(frozen=True)
class Window:
    used_percent: float
    resets_at: float | None  # epoch soniya


@dataclass(frozen=True)
class AgentLimits:
    agent: str
    available: bool
    five_hour: Window | None = None
    weekly: Window | None = None
    updated_at: float | None = None  # epoch soniya — ma'lumot qachon olingan
    stale: bool = False


def _unavailable(agent: str) -> AgentLimits:
    return AgentLimits(agent=agent, available=False)


def _window_kind(window_minutes: object) -> str | None:
    if not isinstance(window_minutes, (int, float)):
        return None
    if abs(window_minutes - _FIVE_HOUR_MINUTES) <= _WINDOW_TOLERANCE_MINUTES:
        return "five_hour"
    if abs(window_minutes - _WEEKLY_MINUTES) <= _WINDOW_TOLERANCE_MINUTES:
        return "weekly"
    return None


def _finish(
    agent: str,
    five_hour: Window | None,
    weekly: Window | None,
    updated_at: float | None,
    now: float,
) -> AgentLimits:
    if five_hour is None and weekly is None:
        return _unavailable(agent)
    stale = updated_at is None or (now - updated_at) > STALE_AFTER
    return AgentLimits(
        agent=agent,
        available=True,
        five_hour=five_hour,
        weekly=weekly,
        updated_at=updated_at,
        stale=stale,
    )


# --- Claude: statusline keshi -----------------------------------------------------------------


def _claude_window(raw: object) -> Window | None:
    if not isinstance(raw, dict):
        return None
    pct = raw.get("used_percentage")
    if not isinstance(pct, (int, float)):
        return None
    resets_at = raw.get("resets_at")
    return Window(
        used_percent=float(pct),
        resets_at=float(resets_at) if isinstance(resets_at, (int, float)) else None,
    )


def read_claude_limits(cache_file: Path, *, now: float) -> AgentLimits:
    """`statusline.sh` yozgan keshni o'qiydi. Fayl yo'q/buzuq/bo'sh bo'lsa — `available=False`."""
    try:
        raw = cache_file.read_text(encoding="utf-8")
    except OSError:
        return _unavailable("claude")
    try:
        data = json.loads(raw)
    except ValueError:
        return _unavailable("claude")
    if not isinstance(data, dict):
        return _unavailable("claude")
    rate_limits = data.get("rate_limits")
    if not isinstance(rate_limits, dict):
        return _unavailable("claude")
    captured_at = data.get("captured_at")
    updated_at = float(captured_at) if isinstance(captured_at, (int, float)) else None
    return _finish(
        "claude",
        _claude_window(rate_limits.get("five_hour")),
        _claude_window(rate_limits.get("seven_day")),
        updated_at,
        now,
    )


# --- Codex: sessiya rollout fayli -------------------------------------------------------------


def _tail_text(path: Path, max_bytes: int) -> tuple[str, bool]:
    """Faylning oxirgi `max_bytes`i; ikkinchisi — boshi qirqilgani (birinchi qator to'liq emas)."""
    try:
        size = path.stat().st_size
        truncated = size > max_bytes
        with path.open("rb") as fh:
            if truncated:
                fh.seek(size - max_bytes)
            data = fh.read()
    except OSError:
        return "", False
    return data.decode("utf-8", errors="replace"), truncated


def _parse_iso(ts: object) -> float | None:
    if not isinstance(ts, str):
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def read_codex_limits(path: Path, *, now: float) -> AgentLimits:
    """Sessiya rollout faylining oxiridan `rate_limits` bor so'nggi qatorni topadi."""
    text, truncated = _tail_text(path, CODEX_TAIL_BYTES)
    lines = text.split("\n")
    if truncated:
        lines = lines[1:]  # boshi qirqilgan — birinchi qator to'liq emas
    for line in reversed(lines[-CODEX_MAX_SCAN_LINES:]):
        line = line.strip()
        if not line or "rate_limits" not in line:
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if not isinstance(obj, dict):
            continue
        payload = obj.get("payload")
        rate_limits = payload.get("rate_limits") if isinstance(payload, dict) else None
        if not isinstance(rate_limits, dict):
            continue
        five_hour: Window | None = None
        weekly: Window | None = None
        for bucket in (rate_limits.get("primary"), rate_limits.get("secondary")):
            if not isinstance(bucket, dict):
                continue
            pct = bucket.get("used_percent")
            if not isinstance(pct, (int, float)):
                continue
            window = Window(
                used_percent=float(pct),
                resets_at=float(bucket["resets_at"])
                if isinstance(bucket.get("resets_at"), (int, float))
                else None,
            )
            kind = _window_kind(bucket.get("window_minutes"))
            if kind == "five_hour":
                five_hour = window
            elif kind == "weekly":
                weekly = window
        if five_hour is None and weekly is None:
            continue  # masalan limit_id="premium" bo'lib, ikkalasi ham null
        updated_at = _parse_iso(obj.get("timestamp"))
        return _finish("codex", five_hour, weekly, updated_at, now)
    return _unavailable("codex")


def _latest_codex_session(sessions: Sequence[AgentSession]) -> AgentSession | None:
    codex = [s for s in sessions if s.agent == "codex"]
    if not codex:
        return None
    return max(codex, key=lambda s: s.mtime)


class LimitsService:
    """Ikkala agentning joriy rate-limit holati."""

    def __init__(self, *, claude_cache: Path, codex_roots: Mapping[str, Path]) -> None:
        self._claude_cache = claude_cache
        self._codex_roots = codex_roots

    @classmethod
    def for_settings(cls, settings: Settings) -> LimitsService:
        claude_home = settings.claude_home or settings.home / ".claude"
        return cls(
            claude_cache=claude_home / CLAUDE_CACHE_FILENAME, codex_roots=settings.transcript_roots
        )

    def claude(self, *, now: float) -> AgentLimits:
        return read_claude_limits(self._claude_cache, now=now)

    def codex(self, sessions: Sequence[AgentSession], *, now: float) -> AgentLimits:
        session = _latest_codex_session(sessions)
        if session is None:
            return _unavailable("codex")
        try:
            transcript = transcripts.locate(session, self._codex_roots)
        except transcripts.TranscriptError:
            return _unavailable("codex")
        return read_codex_limits(transcript.file, now=now)
