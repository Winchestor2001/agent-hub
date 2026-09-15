"""Papka takliflari, uy papkasi ichidagi brauzer va yangi papkada bekloq yaratish."""

from __future__ import annotations

import os
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, Field

from agent_hub.services.folders import (
    Folder,
    FolderError,
    in_git,
    list_folder,
    resolve_in_home,
    suggestions,
)

from .deps import Hub, HubDep
from .errors import ApiError

router = APIRouter(prefix="/api/folders")

_FOLDER_STATUS = {"path_outside_home": 403, "path_invalid": 422}


class BacklogInit(BaseModel):
    model_config = ConfigDict(extra="forbid")

    path: str = Field(max_length=1024)
    name: str = Field(max_length=100)


def _api_error(exc: FolderError) -> ApiError:
    return ApiError(_FOLDER_STATUS[exc.code], exc.code, path=exc.path)


def _home(hub: Hub) -> str:
    """UI yo'llarni `~/...` ko'rinishida qisqartirishi uchun (yo'llar haqiqiy, symlink'siz)."""
    return os.path.realpath(hub.settings.home)


def folder_view(folder: Folder) -> dict[str, Any]:
    return {"name": folder.name, "path": str(folder.path), "has_backlog": folder.has_backlog}


@router.get("")
async def browse(hub: HubDep, path: str = "") -> dict[str, Any]:
    settings = hub.settings
    if not path:
        root = settings.projects_root
        path = str(root if root.is_dir() else settings.home)
    try:
        listing = list_folder(path, settings.home)
    except FolderError as exc:
        raise _api_error(exc) from exc
    return {
        **folder_view(listing.folder),
        "home": _home(hub),
        "parent": str(listing.parent) if listing.parent else None,
        "in_git": listing.in_git,
        "entries": [folder_view(entry) for entry in listing.entries],
        "truncated": listing.truncated,
    }


@router.get("/suggestions")
async def list_suggestions(hub: HubDep) -> dict[str, Any]:
    settings = hub.settings
    registered = [project.backlog_dir for project in hub.registry.load()]
    folders = suggestions(settings.projects_root, settings.home, registered)
    return {
        "root": str(settings.projects_root),
        "home": _home(hub),
        "folders": [folder_view(folder) for folder in folders],
    }


@router.post("/init-backlog", status_code=201)
async def init_backlog(hub: HubDep, body: BacklogInit) -> dict[str, Any]:
    try:
        path = resolve_in_home(body.path, hub.settings.home)
    except FolderError as exc:
        raise _api_error(exc) from exc
    # Nom CLI argumenti bo'ladi: bayroq deb o'qilmasin, qatorlar bitta bo'lsin.
    name = " ".join(body.name.split()).lstrip("- ")
    if not name:
        raise ApiError(422, "project_name_empty")
    await hub.backlog_at(path).init(name, git=in_git(path))
    return {"path": str(path), "name": name, "has_backlog": True}
