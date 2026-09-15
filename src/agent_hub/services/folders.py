"""«Loyiha qo'shish» oynasi uchun papkalar: takliflar va uy papkasi ichidagi brauzer.

Faqat papkalar ko'rsatiladi (fayllar va yashirin papkalar yo'q), yo'llar symlink'lar ochilgan holda
uy papkasi ichida qolishi shart — brauzer orqali tizimning boshqa joylarini ko'rib bo'lmaydi.
"""

from __future__ import annotations

import os
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

from agent_hub.registry import BACKLOG_CONFIG_CANDIDATES

MAX_ENTRIES = 500


class FolderError(Exception):
    def __init__(self, code: str, path: str) -> None:
        super().__init__(f"{code}: {path}")
        self.code = code
        self.path = path


@dataclass(frozen=True)
class Folder:
    name: str
    path: Path
    has_backlog: bool


@dataclass(frozen=True)
class Listing:
    folder: Folder
    parent: Path | None
    in_git: bool
    entries: list[Folder]
    truncated: bool


def has_backlog(directory: Path) -> bool:
    return any((directory / candidate).is_file() for candidate in BACKLOG_CONFIG_CANDIDATES)


def in_git(directory: Path) -> bool:
    return any((candidate / ".git").exists() for candidate in (directory, *directory.parents))


def resolve_in_home(raw: str | Path, home: Path) -> Path:
    """Mavjud papkaning haqiqiy yo'li; uydan tashqarida yoki papka bo'lmasa `FolderError`."""
    text = str(raw).strip()
    if not text:
        raise FolderError("path_invalid", text)
    path = Path(os.path.realpath(Path(text).expanduser()))
    if not path.is_relative_to(Path(os.path.realpath(home))):
        raise FolderError("path_outside_home", text)
    if not path.is_dir():
        raise FolderError("path_invalid", text)
    return path


def _folder(path: Path) -> Folder:
    return Folder(path.name, path, has_backlog(path))


def _child_dirs(directory: Path, home: Path) -> list[Path]:
    """Yashirin bo'lmagan bola papkalar (haqiqiy yo'llar, faqat uy papkasi ichidagilar)."""
    try:
        entries = [e for e in os.scandir(directory) if not e.name.startswith(".") and _is_dir(e)]
    except OSError:
        return []
    real_home = Path(os.path.realpath(home))
    children = (Path(os.path.realpath(entry.path)) for entry in entries)
    inside = {child for child in children if child.is_relative_to(real_home)}
    return sorted(inside, key=lambda path: (path.name.lower(), str(path)))


def _is_dir(entry: os.DirEntry[str]) -> bool:
    try:
        return entry.is_dir()
    except OSError:
        return False


def list_folder(raw: str | Path, home: Path) -> Listing:
    path = resolve_in_home(raw, home)
    real_home = Path(os.path.realpath(home))
    children = _child_dirs(path, home)
    return Listing(
        folder=_folder(path),
        parent=path.parent if path != real_home else None,
        in_git=in_git(path),
        entries=[_folder(child) for child in children[:MAX_ENTRIES]],
        truncated=len(children) > MAX_ENTRIES,
    )


def suggestions(root: Path, home: Path, registered: Iterable[Path]) -> list[Folder]:
    """`root`ning to'g'ridan-to'g'ri bolalari: qo'shilmaganlari, bekloqlilari birinchi."""
    try:
        base = resolve_in_home(root, home)
    except FolderError:
        return []
    taken = {Path(os.path.realpath(path)) for path in registered}
    folders = [_folder(child) for child in _child_dirs(base, home) if child not in taken]
    return sorted(folders, key=lambda folder: not folder.has_backlog)[:MAX_ENTRIES]
