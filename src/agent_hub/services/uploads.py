"""Media fayllarni loyiha papkasiga yuklash (agent ularni nisbiy yo'l bo'yicha o'qiydi).

Fayllar `<loyiha papkasi>/.agent-hub/uploads/<task-29|inbox>/` ichiga tushadi. Shu joy tanlangani
bejiz emas: claude/codex pane'i `cwd` sifatida aynan loyiha papkasida ishlaydi, shuning uchun
promptga nisbiy yo'l yozilsa agent faylni qo'shimcha ruxsatsiz o'qiydi.

Ishonch chegarasi: fayl nomi ham, mijoz qaytargan yo'l ham brauzerdan keladi. Nom `_safe_name`
bilan qayta quriladi (yo'l qismlari, boshqaruv belgilari va noma'lum kengaytmalar tashlanadi),
saqlangan yo'l esa yozishdan oldin `is_within` bilan uploads papkasi ichida ekani tasdiqlanadi.
"""

from __future__ import annotations

import re
from collections.abc import Awaitable, Callable, Iterable, Iterator
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from agent_hub.registry import Project
from agent_hub.services.linking import is_within, real_path

UPLOAD_ROOT = Path(".agent-hub") / "uploads"
INBOX_DIR = "inbox"

MAX_FILE_BYTES = 10 * 1024 * 1024
MAX_FILES = 10
MAX_NAME_LENGTH = 80
CHUNK_SIZE = 64 * 1024

IMAGE_EXTENSIONS = frozenset({".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic"})
# `.svg` ataylab yo'q: ichida skript bo'lishi mumkin.
DOC_EXTENSIONS = frozenset({".pdf", ".txt", ".md", ".csv", ".json", ".log", ".yaml", ".yml"})
ALLOWED_EXTENSIONS = IMAGE_EXTENSIONS | DOC_EXTENSIONS

# Nomda faqat shu belgilar qoladi; qolgani `-` ga aylanadi.
_UNSAFE_CHARS = re.compile(r"[^A-Za-z0-9._-]+")
_DASHES = re.compile(r"-{2,}")
# Papka nomi vazifa ID'sidan quriladi — faqat harf, raqam, nuqta va chiziqcha.
_TASK_DIR = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$")


class UploadError(Exception):
    def __init__(self, code: str, **params: Any) -> None:
        super().__init__(f"{code}: {params}")
        self.code = code
        self.params = params


@dataclass(frozen=True)
class StoredFile:
    """Saqlangan fayl; `path` — loyiha papkasiga nisbatan (promptga aynan shu yoziladi)."""

    name: str
    path: str
    size: int

    @property
    def kind(self) -> str:
        return "image" if Path(self.path).suffix.lower() in IMAGE_EXTENSIONS else "file"

    def as_dict(self) -> dict[str, Any]:
        return {"name": self.name, "path": self.path, "size": self.size, "kind": self.kind}


def _safe_name(raw: str) -> str:
    """Fayl nomi: faqat basename, xavfsiz belgilar va ruxsat etilgan kengaytma."""
    # Windows'dan kelgan `C:\dir\a.png` uchun ham: ikkala ajratuvchi bo'yicha oxirgi bo'lak.
    base = raw.replace("\\", "/").rsplit("/", 1)[-1].strip()
    suffix = Path(base).suffix.lower()
    if suffix not in ALLOWED_EXTENSIONS:
        raise UploadError("upload_type_invalid", name=raw, allowed=sorted(ALLOWED_EXTENSIONS))
    stem = _DASHES.sub("-", _UNSAFE_CHARS.sub("-", base[: -len(suffix)])).strip("-.")
    if not stem:
        stem = "file"
    return stem[: MAX_NAME_LENGTH - len(suffix)] + suffix


def _scope_dir(task_id: str | None) -> str:
    scope = (task_id or "").strip()
    if not scope:
        return INBOX_DIR
    if not _TASK_DIR.fullmatch(scope):
        raise UploadError("upload_name_invalid", name=task_id)
    return scope.lower()


def project_dir(project: Project, cwd: str | None) -> Path:
    """cwd loyiha papkalaridan biri bo'lishi shart (default — birinchisi)."""
    if not cwd:
        return project.dirs[0]
    target = real_path(cwd)
    for directory in project.dirs:
        if real_path(directory) == target:
            return directory
    raise UploadError("cwd_outside_project", cwd=cwd, project=project.id)


def uploads_dir(project: Project, cwd: str | None = None, task_id: str | None = None) -> Path:
    """Yuklash papkasi; yo'q bo'lsa `.gitignore` bilan birga yaratiladi."""
    root = project_dir(project, cwd) / UPLOAD_ROOT
    target = root / _scope_dir(task_id)
    target.mkdir(parents=True, exist_ok=True)
    # Yuklangan fayllar repoga tushmasin — loyihaning o'z `.gitignore` fayliga tegilmaydi.
    marker = root / ".gitignore"
    if not marker.exists():
        marker.write_text("*\n", encoding="utf-8")
    return target


def _unique_path(directory: Path, name: str) -> Path:
    """Nom band bo'lsa `-1`, `-2` … qo'shiladi (mavjud fayl hech qachon ustiga yozilmaydi)."""
    stem, suffix = name[: len(name) - len(Path(name).suffix)], Path(name).suffix
    candidate = directory / name
    counter = 1
    while candidate.exists():
        candidate = directory / f"{stem}-{counter}{suffix}"
        counter += 1
    return candidate


def store(
    directory: Path,
    base_dir: Path,
    raw_name: str,
    chunks: Iterable[bytes],
    *,
    now: datetime | None = None,
) -> StoredFile:
    """Bitta faylni saqlaydi; limitdan oshsa yarim yozilgan fayl o'chiriladi."""
    stamp = (now or datetime.now()).strftime("%Y%m%d-%H%M%S")
    target = _unique_path(directory, f"{stamp}-{_safe_name(raw_name)}")
    if not is_within(directory, base_dir / UPLOAD_ROOT):
        raise UploadError("upload_name_invalid", name=raw_name)

    size = 0
    try:
        with target.open("wb") as handle:
            for chunk in chunks:
                size += len(chunk)
                if size > MAX_FILE_BYTES:
                    raise UploadError("upload_too_large", name=raw_name, limit=MAX_FILE_BYTES)
                handle.write(chunk)
    except BaseException:
        target.unlink(missing_ok=True)
        raise
    if size == 0:
        target.unlink(missing_ok=True)
        raise UploadError("upload_empty", name=raw_name)
    return StoredFile(name=target.name, path=target.relative_to(base_dir).as_posix(), size=size)


def check_count(count: int) -> None:
    if count == 0:
        raise UploadError("upload_empty", name="")
    if count > MAX_FILES:
        raise UploadError("upload_too_many", count=count, limit=MAX_FILES)


def resolve(project: Project, paths: Iterable[str], cwd: str | None = None) -> list[str]:
    """Mijoz qaytargan yo'llar: uploads papkasi ichida va mavjud bo'lishi shart."""
    base = project_dir(project, cwd)
    root = base / UPLOAD_ROOT
    resolved: list[str] = []
    for raw in paths:
        candidate = (base / raw).resolve() if not Path(raw).is_absolute() else Path(raw).resolve()
        if not is_within(candidate, root) or not candidate.is_file():
            raise UploadError("upload_not_found", path=raw)
        relative = candidate.relative_to(real_path(base)).as_posix()
        if relative not in resolved:
            resolved.append(relative)
    return resolved


def chunked(data: bytes, size: int = CHUNK_SIZE) -> Iterator[bytes]:
    """Xotiradagi baytlarni `store` kutgan bo'laklarga ajratadi (testlar uchun qulay)."""
    for start in range(0, len(data), size):
        yield data[start : start + size]


async def read_upload(reader: Callable[[int], Awaitable[bytes]], name: str) -> list[bytes]:
    """Yuklamani bo'lak-bo'lak o'qiydi; limitdan oshgan zahoti to'xtaydi (xotira chegaralangan)."""
    parts: list[bytes] = []
    size = 0
    while chunk := await reader(CHUNK_SIZE):
        size += len(chunk)
        if size > MAX_FILE_BYTES:
            raise UploadError("upload_too_large", name=name, limit=MAX_FILE_BYTES)
        parts.append(chunk)
    return parts
