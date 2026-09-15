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

from agent_hub.kanbot_client import HOOKS_PLACEHOLDER, Pane
from agent_hub.registry import Project

# Oldida harf/raqam/`-`/`_` bo'lmasa (masalan `subtask-1` emas); oxirida ID davom etmasa.
_ID_TEMPLATE = r"(?<![\w-]){prefix}-(\d{{1,9}}(?:\.\d{{1,9}})*)(?![\w-]|\.\d)"
_RESUME_FLAGS = ("--resume", "-r")
_SESSION_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{7,63}$")


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
