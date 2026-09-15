"""Loyihalar registri: ~/.config/agent-hub/projects.yaml."""

from __future__ import annotations

import os
import re
import tempfile
import threading
from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, ConfigDict, Field, ValidationError

DEFAULT_PROJECTS: tuple[dict[str, Any], ...] = (
    {"id": "leveling", "name": "Leveling", "backlog_dir": "~/my-projects/leveling-backend"},
)
BACKLOG_CONFIG_CANDIDATES = (
    Path(".backlog") / "config.yml",
    Path("backlog") / "config.yml",
    Path("backlog.config.yml"),
)
PROJECT_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,39}$")


class RegistryError(Exception):
    def __init__(self, code: str, **params: Any) -> None:
        super().__init__(f"{code}: {params}")
        self.code = code
        self.params = params


class Project(BaseModel):
    model_config = ConfigDict(extra="ignore", frozen=True)

    id: str
    name: str
    backlog_dir: Path
    repos: tuple[Path, ...] = Field(default_factory=tuple)

    @property
    def dirs(self) -> tuple[Path, ...]:
        return self.repos or (self.backlog_dir,)


def _expand(path: str | Path) -> Path:
    return Path(os.path.abspath(Path(path).expanduser()))


def has_backlog(directory: Path) -> bool:
    return any((directory / candidate).is_file() for candidate in BACKLOG_CONFIG_CANDIDATES)


def validate_project(
    project_id: str, name: str, backlog_dir: str | Path, repos: list[str] | list[Path] | None = None
) -> Project:
    """Foydalanuvchi kiritgan loyihani tekshiradi va normallashtiradi."""
    if not PROJECT_ID_RE.fullmatch(project_id):
        raise RegistryError("project_id_invalid", id=project_id)
    if not name.strip():
        raise RegistryError("project_name_empty")
    backlog_path = _expand(backlog_dir)
    if not backlog_path.is_dir():
        raise RegistryError("path_invalid", path=str(backlog_path))
    if not has_backlog(backlog_path):
        raise RegistryError("backlog_not_found", path=str(backlog_path))
    repo_paths = tuple(_expand(repo) for repo in repos or ()) or (backlog_path,)
    for repo in repo_paths:
        if not repo.is_dir():
            raise RegistryError("path_invalid", path=str(repo))
    return Project(id=project_id, name=name.strip(), backlog_dir=backlog_path, repos=repo_paths)


class Registry:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._lock = threading.Lock()

    def load(self) -> list[Project]:
        """Registrni o'qiydi; fayl yo'q bo'lsa default loyihalar bilan yaratadi."""
        with self._lock:
            return self._load_locked()

    def get(self, project_id: str) -> Project:
        for project in self.load():
            if project.id == project_id:
                return project
        raise RegistryError("project_not_found", id=project_id)

    def add(self, project: Project) -> Project:
        with self._lock:
            projects = self._load_locked()
            if any(p.id == project.id for p in projects):
                raise RegistryError("project_exists", id=project.id)
            self._save_locked([*projects, project])
        return project

    def remove(self, project_id: str) -> None:
        with self._lock:
            projects = self._load_locked()
            remaining = [p for p in projects if p.id != project_id]
            if len(remaining) == len(projects):
                raise RegistryError("project_not_found", id=project_id)
            self._save_locked(remaining)

    def _load_locked(self) -> list[Project]:
        try:
            raw = self.path.read_text(encoding="utf-8")
        except FileNotFoundError:
            projects = [self._from_mapping(item) for item in DEFAULT_PROJECTS]
            self._save_locked(projects)
            return projects
        try:
            data = yaml.safe_load(raw) or {}
        except yaml.YAMLError as exc:
            raise RegistryError("registry_invalid", path=str(self.path), error=str(exc)) from exc
        items = data.get("projects") if isinstance(data, dict) else None
        if not isinstance(items, list):
            raise RegistryError("registry_invalid", path=str(self.path), error="projects: list")
        return [self._from_mapping(item) for item in items]

    def _from_mapping(self, item: object) -> Project:
        if not isinstance(item, dict):
            raise RegistryError("registry_invalid", path=str(self.path), error="project: mapping")
        try:
            project = Project.model_validate(item)
        except ValidationError as exc:
            raise RegistryError("registry_invalid", path=str(self.path), error=str(exc)) from exc
        backlog_dir = _expand(project.backlog_dir)
        repos = tuple(_expand(repo) for repo in project.repos) or (backlog_dir,)
        return project.model_copy(update={"backlog_dir": backlog_dir, "repos": repos})

    def _save_locked(self, projects: list[Project]) -> None:
        data = {
            "projects": [
                {
                    "id": p.id,
                    "name": p.name,
                    "backlog_dir": str(p.backlog_dir),
                    "repos": [str(repo) for repo in p.repos],
                }
                for p in projects
            ]
        }
        text = yaml.safe_dump(data, allow_unicode=True, sort_keys=False)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(prefix=".projects-", suffix=".tmp", dir=self.path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as tmp:
                tmp.write(text)
                tmp.flush()
                os.fsync(tmp.fileno())
            os.replace(tmp_name, self.path)
        except BaseException:
            Path(tmp_name).unlink(missing_ok=True)
            raise
