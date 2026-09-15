"""Sessiya ↔ vazifa va sessiya ↔ loyiha bog'lanishi (sof funksiyalar).

Vazifa ID'si loyihaning `task_prefix` idan qurilgan regex bilan qidiriladi, raqamlar butun son
sifatida solishtiriladi: `task-1`, `TASK-001` va `Task-01` — bitta vazifa. Prefiksdan
tashqaridagi `UTF-8`, `ISO-8601` kabi so'zlar bog'lanmaydi.
"""

from __future__ import annotations

import os
import re
from collections.abc import Iterable, Sequence
from functools import lru_cache
from pathlib import Path

from agent_hub.kanbot_client import HOOKS_PLACEHOLDER, AgentSession, Pane
from agent_hub.registry import Project

# Oldida harf/raqam/`-`/`_` bo'lmasa (masalan `subtask-1` emas); oxirida ID davom etmasa.
_ID_TEMPLATE = r"(?<![\w-]){prefix}-(\d{{1,9}}(?:\.\d{{1,9}})*)(?![\w-]|\.\d)"
_RESUME_FLAGS = ("--resume", "-r")
_SESSION_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{7,63}$")
# Sessiya faylining birinchi yozuvi pane'dan keyin; soat yumaloqlanishi uchun zaxira.
PANE_SESSION_SLACK_S = 5.0


@lru_cache(maxsize=64)
def task_id_pattern(prefix: str) -> re.Pattern[str]:
    if not prefix:
        raise ValueError("task_prefix bo'sh")
    return re.compile(_ID_TEMPLATE.format(prefix=re.escape(prefix)), re.IGNORECASE)


def _key(prefix: str, digits: str) -> str:
    return f"{prefix.lower()}-{'.'.join(str(int(part)) for part in digits.split('.'))}"


def task_key(task_id: str, prefix: str) -> str | None:
    """ID'ning kanonik kaliti (`TASK-001` → `task-1`); ID to'liq mos kelmasa `None`."""
    match = task_id_pattern(prefix).fullmatch(task_id.strip())
    return _key(prefix, match.group(1)) if match else None


def find_task_keys(text: str, prefix: str) -> list[str]:
    """Matndagi vazifa ID'lari (kanonik, takrorsiz, uchragan tartibda)."""
    keys: list[str] = []
    for match in task_id_pattern(prefix).finditer(text):
        key = _key(prefix, match.group(1))
        if key not in keys:
            keys.append(key)
    return keys


def index_task_ids(task_ids: Iterable[str], prefix: str) -> dict[str, str]:
    """Kanonik kalit → bekloqdagi asl ID."""
    index: dict[str, str] = {}
    for task_id in task_ids:
        key = task_key(task_id, prefix)
        if key is not None:
            index.setdefault(key, task_id)
    return index


def pane_prompt_args(argv: Sequence[str]) -> list[str]:
    """argv'dagi prompt bo'lishi mumkin bo'lgan argumentlar (dastur nomi va hook JSON'isiz)."""
    return [arg for arg in argv[1:] if arg != HOOKS_PLACEHOLDER]


def resume_session_id(argv: Sequence[str]) -> str | None:
    """Resume qilingan pane'ning o'tgan sessiya ID'si.

    claude: `--resume <id>`, `--resume=<id>`, `-r <id>`; codex: `codex resume <id>`.
    """
    for index, arg in enumerate(argv[1:], start=1):
        value: str | None = None
        if arg in _RESUME_FLAGS and index + 1 < len(argv):
            value = argv[index + 1]
        elif arg.startswith("--resume="):
            value = arg.partition("=")[2]
        elif arg == "resume" and index == 1:
            value = next((a for a in argv[2:] if not a.startswith("-")), None)
        if value is not None:
            return value if _SESSION_ID_RE.match(value) else None
    return None


def open_session_ids(panes: Iterable[Pane]) -> set[str]:
    """Tirik pane'larda ochiq sessiyalar: hook bergan `session_id` va `--resume` qilingan ID.

    KanBot sessiyani faqat fayl yaqinda yozilganda `active` deydi; jim turgan pane'dagi sessiya
    ham ochiq — uni ikkinchi marta davom ettirib bo'lmaydi.
    """
    ids: set[str] = set()
    for pane in panes:
        if not pane.alive:
            continue
        if pane.session_id:
            ids.add(pane.session_id)
        resumed = resume_session_id(pane.argv)
        if resumed:
            ids.add(resumed)
    return ids


def live_session_ids(panes: Iterable[Pane], sessions: Iterable[AgentSession]) -> set[str]:
    """Tirik pane'larga tegishli sessiyalar: `open_session_ids` + ID'si noma'lum pane'lar.

    Qo'lda ochilgan pane'da KanBot `session_id` bermaydi va argv'da `--resume` yo'q. Bunday pane
    uchun sessiya taxmin qilinadi: agent, papka va runner bir xil, sessiya pane'dan keyin
    boshlangan. Pane'lar eng yangisidan ko'riladi va har biri hali band bo'lmagan eng yangi
    nomzodni oladi — `/clear` dan keyingi joriy sessiya va bir papkadagi bir nechta pane uchun.
    """
    alive = [pane for pane in panes if pane.alive]
    ids = open_session_ids(alive)
    unknown = [
        pane
        for pane in alive
        if not pane.session_id and not resume_session_id(pane.argv) and pane.started_at is not None
    ]
    if not unknown:
        return ids
    candidates = [s for s in sessions if s.session_id not in ids and s.started_at is not None]
    for pane in sorted(unknown, key=lambda p: p.started_at or 0.0, reverse=True):
        match = max(
            (s for s in candidates if s.session_id not in ids and _pane_owns(pane, s)),
            key=lambda s: s.started_at or 0.0,
            default=None,
        )
        if match is not None:
            ids.add(match.session_id)
    return ids


def _pane_owns(pane: Pane, session: AgentSession) -> bool:
    if session.agent != pane.agent or not pane.cwd or not session.cwd:
        return False
    if pane.runner_id and session.runner_id and pane.runner_id != session.runner_id:
        return False
    if (session.started_at or 0.0) < (pane.started_at or 0.0) - PANE_SESSION_SLACK_S:
        return False
    return real_path(pane.cwd) == real_path(session.cwd)


def is_valid_session_id(session_id: str) -> bool:
    return bool(_SESSION_ID_RE.match(session_id))


def pane_task_key(
    pane: Pane, prefix: str, session_titles: dict[str, str] | None = None
) -> str | None:
    """Pane qaysi vazifa ustida ishlayotgani: title → argv'dagi prompt → resume sessiya title'i."""
    sources = [pane.title, *pane_prompt_args(pane.argv)]
    resumed = resume_session_id(pane.argv)
    if resumed and session_titles:
        sources.append(session_titles.get(resumed, ""))
    for text in sources:
        keys = find_task_keys(text, prefix)
        if keys:
            return keys[0]
    return None


# --- loyihaga tegishlilik --------------------------------------------------------------------


def real_path(path: str | Path) -> Path:
    return Path(os.path.realpath(Path(path).expanduser()))


def is_within(path: str | Path, root: str | Path) -> bool:
    """`path` (symlink'lar ochilgan holda) `root` ning o'zi yoki ichida."""
    if not str(path) or not str(root):
        return False
    return real_path(path).is_relative_to(real_path(root))


def project_for_path(path: str | Path, projects: Sequence[Project]) -> Project | None:
    """Yo'l tegishli loyiha; bir nechtasiga mos kelsa — eng ichki papkalisi."""
    if not str(path):
        return None
    resolved = real_path(path)
    best: tuple[int, Project] | None = None
    for project in projects:
        for directory in project.dirs:
            root = real_path(directory)
            if resolved.is_relative_to(root) and (best is None or len(root.parts) > best[0]):
                best = (len(root.parts), project)
    return best[1] if best else None


def panes_for_project(
    panes: Iterable[Pane], project: Project, projects: Sequence[Project]
) -> list[Pane]:
    return [
        pane
        for pane in panes
        if (owner := project_for_path(pane.cwd, projects)) and owner.id == project.id
    ]
