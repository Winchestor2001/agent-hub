"""Claude Code konfiguratsiyasi: qamrovlar, turlar, fayllar va bir nechta qamrovga qo'llash.

Endpoint'lar sinxron (`def`): fayl tizimi ishi threadpool'da bajariladi.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query
from pydantic import BaseModel, ConfigDict, Field

from agent_hub.services.claude_config import KINDS, MAX_SIZE

from .deps import HubDep

router = APIRouter()

ScopeQuery = Query(max_length=80)
KindQuery = Query(max_length=40)
NameQuery = Query(max_length=80)


class FileWrite(BaseModel):
    model_config = ConfigDict(extra="forbid")

    scope: str = Field(max_length=80)
    kind: str = Field(max_length=40)
    name: str = Field(max_length=80)
    # Hajm chegarasini servis aniq kod bilan tekshiradi; bu yerda — juda katta tana uchun to'siq.
    content: str = Field(max_length=MAX_SIZE * 2)
    # `null` — yangi fayl yaratish; aks holda o'qishda olingan etag.
    etag: str | None = Field(default=None, max_length=64)


class ConfigApply(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: str = Field(max_length=40)
    name: str = Field(max_length=80)
    content: str = Field(max_length=MAX_SIZE * 2)
    scopes: list[str] = Field(min_length=1, max_length=100)
    overwrite: bool = False


@router.get("/api/claude-config/scopes")
def config_scopes(hub: HubDep) -> dict[str, Any]:
    return {
        "scopes": [scope.as_dict() for scope in hub.claude_config.scopes()],
        "kinds": [kind.as_dict() for kind in KINDS.values()],
    }


@router.get("/api/claude-config/items")
def config_items(hub: HubDep, scope: str = ScopeQuery, kind: str = KindQuery) -> dict[str, Any]:
    return hub.claude_config.list_items(scope, kind)


@router.get("/api/claude-config/file")
def config_read(
    hub: HubDep, scope: str = ScopeQuery, kind: str = KindQuery, name: str = NameQuery
) -> dict[str, Any]:
    return hub.claude_config.read(scope, kind, name)


@router.put("/api/claude-config/file")
def config_write(hub: HubDep, body: FileWrite) -> dict[str, Any]:
    return hub.claude_config.write(body.scope, body.kind, body.name, body.content, body.etag)


@router.delete("/api/claude-config/file")
def config_delete(
    hub: HubDep,
    scope: str = ScopeQuery,
    kind: str = KindQuery,
    name: str = NameQuery,
    etag: str = Query(max_length=64),
) -> dict[str, Any]:
    return hub.claude_config.delete(scope, kind, name, etag)


@router.post("/api/claude-config/apply")
def config_apply(hub: HubDep, body: ConfigApply) -> dict[str, Any]:
    results = hub.claude_config.apply(
        body.kind, body.name, body.content, body.scopes, overwrite=body.overwrite
    )
    return {"results": results}
