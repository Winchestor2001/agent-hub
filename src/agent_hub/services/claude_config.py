"""Claude Code konfiguratsiya fayllari: global (~/.claude) va loyiha qamrovlarida ko'rish va yozish.

Ishonch chegarasi: brauzer faqat qamrov ID'si, tur (kind) va nom yuboradi. Fayl yo'li shu uchtasidan
katalog bo'yicha quriladi — erkin yo'l qabul qilinmaydi. Nom regex bilan tekshiriladi, ildiz
ostidagi har bir bo'g'in symlink emasligi tasdiqlanadi (symlink orqali ildizdan chiqib bo'lmaydi).

Hooks va settings kod ishga tushiradi, shuning uchun yozish: atomar, etag bilan (boshqa joyda
o'zgargan faylni ustidan yozmaydi), oldingi nusxa zaxiraga olinadi va fayl rejimi saqlanadi.
Global MCP (`~/.claude.json`) ataylab yo'q: bu Claude'ning jonli holat fayli. Agent Hub hech
narsani commit qilmaydi.
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import threading
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Literal

import yaml

from agent_hub.registry import Project
from agent_hub.services.linking import real_path

ScopeKind = Literal["global", "project"]
Format = Literal["markdown", "frontmatter", "json", "script"]
Layout = Literal["file", "skill"]

NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
HOOK_EXTENSIONS = (".sh", ".js", ".mjs", ".cjs", ".py")
MAX_SIZE = 512 * 1024
GLOBAL_SCOPE = "global"
_PROJECT_SCOPE_RE = re.compile(r"^project:([a-z0-9][a-z0-9-]{0,39})(?::([1-9][0-9]?))?$")
_FRONTMATTER_RE = re.compile(r"\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|\Z)", re.DOTALL)


class ConfigError(Exception):
    def __init__(self, code: str, **params: Any) -> None:
        super().__init__(f"{code}: {params}")
        self.code = code
        self.params = params


@dataclass(frozen=True)
class Kind:
    """Konfiguratsiya turi: qayerda yashaydi, qanday nomlanadi va qanday tekshiriladi.

    `fixed` — nomi oldindan ma'lum fayllar: nom → (global yo'l, loyiha yo'li); `None` — bu
    qamrovda yo'q. `folder` — to'plam turlari uchun papka (global, loyiha).
    """

    id: str
    format: Format
    fixed: Mapping[str, tuple[str | None, str | None]] = field(default_factory=dict)
    folder: tuple[str, str] | None = None
    layout: Layout = "file"
    extensions: tuple[str, ...] = (".md",)
    required: tuple[str, ...] = ()
    new_mode: int = 0o644
    # Bir xil nom ikki qamrovda bo'lsa qaysi biri ishlaydi (Claude Code hujjati bo'yicha).
    winner: ScopeKind | None = None

    @property
    def collection(self) -> bool:
        return self.folder is not None

    def scopes(self) -> list[ScopeKind]:
        if self.folder is not None:
            return ["global", "project"]
        found: list[ScopeKind] = []
        if any(paths[0] for paths in self.fixed.values()):
            found.append("global")
        if any(paths[1] for paths in self.fixed.values()):
            found.append("project")
        return found

    def fixed_names(self, scope: ScopeKind) -> list[str]:
        index = 0 if scope == "global" else 1
        return [name for name, paths in self.fixed.items() if paths[index]]

    def relative(self, scope: ScopeKind, name: str) -> Path:
        """Ildizga nisbatan yo'l; nom va qamrov katalogga mos kelmasa `ConfigError`."""
        if self.folder is None:
            paths = self.fixed.get(name)
            target = paths[0 if scope == "global" else 1] if paths else None
            if target is None:
                raise ConfigError("config_name_invalid", kind=self.id, name=name)
            return Path(target)
        folder = Path(self.folder[0] if scope == "global" else self.folder[1])
        stem, suffix = _split_name(name, self.extensions if self.layout == "file" else ())
        if self.layout == "skill":
            return folder / stem / "SKILL.md"
        return folder / f"{stem}{suffix}"

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "format": self.format,
            "collection": self.collection,
            "layout": self.layout,
            "extensions": list(self.extensions) if self.collection else [],
            "scopes": self.scopes(),
            "fixed": {
                scope: self.fixed_names(scope) for scope in self.scopes() if not self.collection
            },
            "required": list(self.required),
            "winner": self.winner,
        }


def _split_name(name: str, extensions: tuple[str, ...]) -> tuple[str, str]:
    """`foo` yoki (bir nechta kengaytmali tur uchun) `foo.sh` → (stem, kengaytma)."""
    if len(extensions) == 1 or not extensions:
        stem, suffix = name, extensions[0] if extensions else ""
    else:
        stem, dot, ext = name.rpartition(".")
        suffix = f".{ext}" if dot else ""
        if suffix not in extensions:
            raise ConfigError("config_name_invalid", name=name, allowed=list(extensions))
    if not NAME_RE.fullmatch(stem):
        raise ConfigError("config_name_invalid", name=name, allowed=list(extensions))
    return stem, suffix


KINDS: dict[str, Kind] = {
    kind.id: kind
    for kind in (
        Kind("claude_md", "markdown", fixed={"claude-md": ("CLAUDE.md", "CLAUDE.md")}),
        Kind("claude_local_md", "markdown", fixed={"claude-local-md": (None, "CLAUDE.local.md")}),
        Kind("mcp", "json", fixed={"mcp": (None, ".mcp.json")}),
        Kind(
            "settings",
            "json",
            fixed={
                "settings": ("settings.json", ".claude/settings.json"),
                "settings-local": ("settings.local.json", ".claude/settings.local.json"),
            },
            new_mode=0o600,
        ),
        Kind("rules", "frontmatter", folder=("rules", ".claude/rules")),
        Kind("commands", "frontmatter", folder=("commands", ".claude/commands")),
        Kind(
            "skills",
            "frontmatter",
            folder=("skills", ".claude/skills"),
            layout="skill",
            required=("description",),
            winner="global",
        ),
        Kind(
            "agents",
            "frontmatter",
            folder=("agents", ".claude/agents"),
            required=("name", "description"),
            winner="project",
        ),
        Kind(
            "hooks",
            "script",
            folder=("hooks", ".claude/hooks"),
            extensions=HOOK_EXTENSIONS,
            new_mode=0o755,
        ),
    )
}


def kind_for(kind_id: str) -> Kind:
    kind = KINDS.get(kind_id)
    if kind is None:
        raise ConfigError("config_kind_unknown", kind=kind_id)
    return kind


@dataclass(frozen=True)
class Scope:
    id: str
    kind: ScopeKind
    root: Path
    label: str
    project_id: str | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "kind": self.kind,
            "root": str(self.root),
            "label": self.label,
            "project_id": self.project_id,
            "exists": self.root.is_dir(),
        }


def etag_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# --- Validatsiya ---------------------------------------------------------------------------


def parse_frontmatter(content: str) -> dict[str, Any] | None:
    """`---` bloki bo'lmasa `None`; bo'lsa YAML mapping bo'lishi shart."""
    match = _FRONTMATTER_RE.match(content)
    if match is None:
        if content.startswith("---"):
            raise ConfigError("config_frontmatter_invalid", error="closing --- not found")
        return None
    try:
        data = yaml.safe_load(match.group(1))
    except yaml.YAMLError as exc:
        raise ConfigError("config_frontmatter_invalid", error=str(exc)) from exc
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ConfigError("config_frontmatter_invalid", error="mapping expected")
    return data


def validate(kind: Kind, content: str) -> None:
    """Kontent tur qoidalariga mos; mos kelmasa aniq kodli `ConfigError`."""
    size = len(content.encode("utf-8"))
    if size > MAX_SIZE:
        raise ConfigError("config_too_large", size=size, limit=MAX_SIZE)
    if "\x00" in content:
        raise ConfigError("config_not_text")
    if kind.format == "json":
        _validate_json(kind, content)
    elif kind.format == "frontmatter":
        meta = parse_frontmatter(content)
        if kind.required and meta is None:
            fields = list(kind.required)
            raise ConfigError("config_frontmatter_missing", kind=kind.id, fields=fields)
        for name in kind.required:
            value = (meta or {}).get(name)
            if not isinstance(value, str) or not value.strip():
                raise ConfigError("config_frontmatter_field", kind=kind.id, field=name)


def _validate_json(kind: Kind, content: str) -> None:
    try:
        data = json.loads(content)
    except json.JSONDecodeError as exc:
        raise ConfigError(
            "config_json_invalid", line=exc.lineno, column=exc.colno, error=exc.msg
        ) from exc
    if not isinstance(data, dict):
        raise ConfigError("config_json_not_object")
    if kind.id == "mcp" and not isinstance(data.get("mcpServers", {}), dict):
        raise ConfigError("config_mcp_invalid")
    if kind.id == "settings" and not isinstance(data.get("hooks", {}), dict):
        raise ConfigError("config_settings_hooks_invalid")


# --- Fayl tizimi --------------------------------------------------------------------------


def _ensure_plain(root: Path, relative: Path) -> Path:
    """Ildiz ostidagi har bo'g'in symlink emas va yo'l ildizdan chiqmaydi."""
    if relative.is_absolute() or ".." in relative.parts:
        raise ConfigError("config_path_outside", path=str(relative))
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise ConfigError("config_symlink", path=str(current))
    return current


def _mkdirs(root: Path, relative: Path) -> None:
    """Ota papkalarni ildiz ichida, symlink'larsiz yaratadi."""
    current = root
    for part in relative.parts:
        current = current / part
        with contextlib.suppress(FileExistsError):
            current.mkdir()
        if current.is_symlink() or not current.is_dir():
            raise ConfigError("config_symlink", path=str(current))


def _atomic_write(path: Path, data: bytes, mode: int, *, exclusive: bool) -> None:
    """Vaqtinchalik faylga yozib almashtiradi: yarim yozilgan fayl hech qachon ko'rinmaydi.

    `exclusive` — fayl yo'q bo'lsagina yaratiladi (`os.link` atomar ravishda rad etadi).
    """
    fd, tmp_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, mode)
        if exclusive:
            try:
                os.link(tmp, path)
            except FileExistsError as exc:
                raise ConfigError("config_exists", path=str(path)) from exc
            tmp.unlink()
        else:
            os.replace(tmp, path)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def _read_bytes(path: Path) -> bytes | None:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(info.st_mode):
        raise ConfigError("config_not_file", path=str(path))
    if info.st_size > MAX_SIZE:
        raise ConfigError("config_too_large", size=info.st_size, limit=MAX_SIZE)
    return path.read_bytes()


def _decode(data: bytes, path: Path) -> str:
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ConfigError("config_not_text", path=str(path)) from exc


def git_ignored(root: Path, relative: Path) -> bool | None:
    """Fayl git'da e'tiborsizmi; git yoki repo bo'lmasa `None` (faqat o'qiydi)."""
    git = shutil.which("git")
    if git is None:
        return None
    try:
        result = subprocess.run(  # noqa: S603 — argv ro'yxat, shell yo'q
            [git, "-C", str(root), "check-ignore", "-q", "--", str(relative)],
            capture_output=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return {0: True, 1: False}.get(result.returncode)


# --- Servis -------------------------------------------------------------------------------


class ClaudeConfigService:
    def __init__(
        self, claude_home: Path, backups_dir: Path, projects: Callable[[], list[Project]]
    ) -> None:
        self.claude_home = claude_home
        self.backups_dir = backups_dir
        self._projects = projects
        # Etag tekshiruvi va yozish bitta qadam bo'lsin (threadpool'dagi parallel so'rovlar).
        self._lock = threading.Lock()

    # Qamrovlar

    def scopes(self) -> list[Scope]:
        found = [Scope(GLOBAL_SCOPE, "global", self.claude_home, "Global")]
        for project in self._projects():
            found.extend(self._project_scopes(project))
        return found

    @staticmethod
    def _project_scopes(project: Project) -> list[Scope]:
        scopes = []
        for index, directory in enumerate(project.dirs):
            scope_id = f"project:{project.id}" if index == 0 else f"project:{project.id}:{index}"
            label = project.name if index == 0 else f"{project.name} · {directory.name}"
            scopes.append(Scope(scope_id, "project", directory, label, project.id))
        return scopes

    def scope(self, scope_id: str) -> Scope:
        if scope_id == GLOBAL_SCOPE:
            return Scope(GLOBAL_SCOPE, "global", self.claude_home, "Global")
        match = _PROJECT_SCOPE_RE.fullmatch(scope_id)
        if match is not None:
            for project in self._projects():
                if project.id == match.group(1):
                    for scope in self._project_scopes(project):
                        if scope.id == scope_id:
                            return scope
        raise ConfigError("config_scope_unknown", scope=scope_id)

    def _root(self, scope: Scope, *, create: bool = False) -> Path:
        if scope.kind == "global":
            # ~/.claude hali yo'q bo'lishi mumkin: o'qishda fayllar shunchaki "yo'q".
            if create:
                self.claude_home.mkdir(parents=True, exist_ok=True)
            elif not self.claude_home.exists():
                return self.claude_home.absolute()
        if not scope.root.is_dir():
            raise ConfigError("config_scope_missing", scope=scope.id, path=str(scope.root))
        return real_path(scope.root)

    def _target(self, scope: Scope, kind: Kind, name: str) -> tuple[Path, Path, Path]:
        """(ildiz, nisbiy yo'l, to'liq yo'l); qamrovda yo'q tur — `config_kind_scope`."""
        if scope.kind not in kind.scopes():
            raise ConfigError("config_kind_scope", kind=kind.id, scope=scope.id)
        relative = kind.relative(scope.kind, name)
        root = self._root(scope)
        return root, relative, _ensure_plain(root, relative)

    # Ro'yxat

    def list_items(self, scope_id: str, kind_id: str) -> dict[str, Any]:
        scope, kind = self.scope(scope_id), kind_for(kind_id)
        if scope.kind not in kind.scopes():
            raise ConfigError("config_kind_scope", kind=kind.id, scope=scope.id)
        if not scope.root.is_dir():
            return {"items": [], "skipped": []}
        root = real_path(scope.root)
        if not kind.collection:
            items = [self._item(root, kind, scope, name) for name in kind.fixed_names(scope.kind)]
            return {"items": items, "skipped": []}
        names, skipped = self._collection_names(root, kind, scope.kind)
        items = [self._item(root, kind, scope, name) for name in names]
        if kind.winner is not None:
            self._mark_shadows(scope, kind, items)
        return {"items": items, "skipped": skipped}

    def _collection_names(
        self, root: Path, kind: Kind, scope_kind: ScopeKind
    ) -> tuple[list[str], list[str]]:
        if kind.folder is None:
            return [], []
        folder = root / (kind.folder[0] if scope_kind == "global" else kind.folder[1])
        if folder.is_symlink() or not folder.is_dir():
            return [], []
        names: list[str] = []
        skipped: list[str] = []
        for entry in sorted(folder.iterdir()):
            if entry.name.startswith("."):
                continue
            if kind.layout == "skill":
                if not (entry / "SKILL.md").is_file():
                    continue
                name = entry.name
            elif entry.suffix in kind.extensions and (entry.is_file() or entry.is_symlink()):
                name = entry.stem if len(kind.extensions) == 1 else entry.name
            else:
                continue
            try:
                kind.relative(scope_kind, name)
            except ConfigError:
                skipped.append(entry.name)
                continue
            names.append(name)
        return names, skipped

    def _item(self, root: Path, kind: Kind, scope: Scope, name: str) -> dict[str, Any]:
        relative = kind.relative(scope.kind, name)
        path = root / relative
        try:
            _ensure_plain(root, relative)
            symlink = False
        except ConfigError:
            symlink = True
        info = path.stat() if not symlink and path.is_file() else None
        return {
            "name": name,
            "path": relative.as_posix(),
            "exists": info is not None,
            "size": info.st_size if info else None,
            "mtime": info.st_mtime if info else None,
            "symlink": symlink,
            "shadow": [],
        }

    def _mark_shadows(self, scope: Scope, kind: Kind, items: list[dict[str, Any]]) -> None:
        """Bir xil nomli element boshqa qamrovda bo'lsa: kim ustun ekani (`winner`)."""
        others = (
            [other for other in self.scopes() if other.kind == "project"]
            if scope.kind == "global"
            else [self.scope(GLOBAL_SCOPE)]
        )
        names = {item["name"] for item in items}
        for other in others:
            if not other.root.is_dir():
                continue
            other_names, _ = self._collection_names(real_path(other.root), kind, other.kind)
            for item in items:
                if item["name"] in names and item["name"] in other_names:
                    winner = "this" if kind.winner == scope.kind else "other"
                    item["shadow"].append({"scope": other.id, "winner": winner})

    # O'qish

    def read(self, scope_id: str, kind_id: str, name: str) -> dict[str, Any]:
        scope, kind = self.scope(scope_id), kind_for(kind_id)
        root, relative, path = self._target(scope, kind, name)
        data = _read_bytes(path)
        result: dict[str, Any] = {
            "scope": scope.id,
            "kind": kind.id,
            "name": name,
            "path": relative.as_posix(),
            "abs_path": str(path),
            "exists": data is not None,
            "content": _decode(data, path) if data is not None else None,
            "etag": etag_of(data) if data is not None else None,
            "mode": f"{stat.S_IMODE(path.stat().st_mode):o}" if data is not None else None,
            "warnings": [],
        }
        if kind.id == "claude_local_md" and git_ignored(root, relative) is False:
            result["warnings"].append("local_not_ignored")
        return result

    # Yozish

    def write(
        self, scope_id: str, kind_id: str, name: str, content: str, etag: str | None
    ) -> dict[str, Any]:
        """`etag=None` — yangi fayl (mavjud bo'lsa 409), aks holda joriy etag bilan teng bo'lsin."""
        scope, kind = self.scope(scope_id), kind_for(kind_id)
        validate(kind, content)
        return self._write(scope, kind, name, content, etag)

    def _write(
        self, scope: Scope, kind: Kind, name: str, content: str, etag: str | None
    ) -> dict[str, Any]:
        if scope.kind == "global":
            self._root(scope, create=True)
        root, relative, path = self._target(scope, kind, name)
        data = content.encode("utf-8")
        backup: Path | None = None
        with self._lock:
            current = _read_bytes(path)
            if etag is None and current is not None:
                raise ConfigError("config_exists", path=relative.as_posix())
            if etag is not None and current is None:
                raise ConfigError("config_not_found", path=relative.as_posix())
            if etag is not None and current is not None and etag_of(current) != etag:
                raise ConfigError("config_conflict", path=relative.as_posix())
            if current is None:
                _mkdirs(root, relative.parent)
                _ensure_plain(root, relative)
                _atomic_write(path, data, kind.new_mode, exclusive=True)
            else:
                mode = stat.S_IMODE(path.stat().st_mode)
                backup = self._backup(scope, kind, name, path, current)
                _atomic_write(path, data, mode, exclusive=False)
        return {
            "scope": scope.id,
            "kind": kind.id,
            "name": name,
            "path": relative.as_posix(),
            "etag": etag_of(data),
            "created": current is None,
            "backup": str(backup) if backup else None,
        }

    def delete(self, scope_id: str, kind_id: str, name: str, etag: str) -> dict[str, Any]:
        scope, kind = self.scope(scope_id), kind_for(kind_id)
        _, relative, path = self._target(scope, kind, name)
        with self._lock:
            current = _read_bytes(path)
            if current is None:
                raise ConfigError("config_not_found", path=relative.as_posix())
            if etag_of(current) != etag:
                raise ConfigError("config_conflict", path=relative.as_posix())
            backup = self._backup(scope, kind, name, path, current)
            path.unlink()
        if kind.layout == "skill":
            # Skill papkasida boshqa fayllar (skriptlar, misollar) bo'lsa papka qoladi.
            with contextlib.suppress(OSError):
                path.parent.rmdir()
        return {"scope": scope.id, "path": relative.as_posix(), "backup": str(backup)}

    def _backup(self, scope: Scope, kind: Kind, name: str, path: Path, data: bytes) -> Path:
        self.backups_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        scope_slug = scope.id.replace(":", "_")
        target = self.backups_dir / f"{stamp}-{scope_slug}-{kind.id}-{name}{path.suffix}"
        _atomic_write(target, data, 0o600, exclusive=True)
        return target

    # Bir nechta qamrovga

    def apply(
        self,
        kind_id: str,
        name: str,
        content: str,
        scope_ids: Iterable[str],
        *,
        overwrite: bool,
    ) -> list[dict[str, Any]]:
        """Bitta kontentni bir nechta qamrovga yozadi; har qamrov natijasi alohida."""
        kind = kind_for(kind_id)
        validate(kind, content)
        if kind.collection:
            kind.relative("project", name)  # nom bir marta, hamma qamrovdan oldin tekshiriladi
        results: list[dict[str, Any]] = []
        for scope_id in dict.fromkeys(scope_ids):
            try:
                results.append(self._apply_one(scope_id, kind, name, content, overwrite))
            except ConfigError as exc:
                error = {"code": exc.code, "params": exc.params, "detail": None}
                results.append({"scope": scope_id, "ok": False, "status": "error", "error": error})
        return results

    def _apply_one(
        self, scope_id: str, kind: Kind, name: str, content: str, overwrite: bool
    ) -> dict[str, Any]:
        scope = self.scope(scope_id)
        if scope.kind == "global":
            self._root(scope, create=True)
        _, relative, path = self._target(scope, kind, name)
        current = _read_bytes(path)
        if current is not None and current == content.encode("utf-8"):
            return {"scope": scope.id, "ok": True, "status": "unchanged", "error": None}
        if current is not None and not overwrite:
            raise ConfigError("config_exists", path=relative.as_posix())
        etag = None if current is None else etag_of(current)
        result = self._write(scope, kind, name, content, etag)
        status = "created" if result["created"] else "updated"
        return {**result, "ok": True, "status": status, "error": None}
