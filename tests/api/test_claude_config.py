"""`/api/claude-config/*`: qamrovlar, CRUD, xato statuslari va apply."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import httpx

from .conftest import ApiEnv, assert_error

SKILL = "---\nname: deploy\ndescription: Deploy\n---\n\nQadamlar.\n"


def put(api: ApiEnv, **body: Any) -> httpx.Response:
    payload: dict[str, Any] = {
        "scope": "project:leveling",
        "kind": "rules",
        "name": "style",
        "etag": None,
    }
    payload.update(body)
    resp: httpx.Response = api.client.put("/api/claude-config/file", json=payload)
    return resp


def test_scopes_and_kinds(api: ApiEnv) -> None:
    data = api.client.get("/api/claude-config/scopes").json()
    ids = [scope["id"] for scope in data["scopes"]]
    assert ids == ["global", "project:leveling", "project:leveling:1", "project:broken"]
    kinds = {kind["id"]: kind for kind in data["kinds"]}
    assert len(kinds) == 9
    assert kinds["mcp"]["scopes"] == ["project"]
    assert kinds["settings"]["fixed"]["project"] == ["settings", "settings-local"]
    assert kinds["skills"]["winner"] == "global"


def test_crud_over_http(api: ApiEnv, tmp_path: Path) -> None:
    resp = api.client.put(
        "/api/claude-config/file",
        json={"scope": "global", "kind": "skills", "name": "deploy", "content": SKILL},
    )
    assert resp.status_code == 200, resp.text
    assert (tmp_path / ".claude" / "skills" / "deploy" / "SKILL.md").read_text() == SKILL

    items = api.client.get("/api/claude-config/items", params={"scope": "global", "kind": "skills"})
    assert [item["name"] for item in items.json()["items"]] == ["deploy"]

    params = {"scope": "global", "kind": "skills", "name": "deploy"}
    read = api.client.get("/api/claude-config/file", params=params).json()
    assert read["content"] == SKILL

    stale = {**params, "etag": "0" * 64}
    assert_error(api.client.delete("/api/claude-config/file", params=stale), 409, "config_conflict")
    deleted = api.client.delete("/api/claude-config/file", params={**params, "etag": read["etag"]})
    assert deleted.status_code == 200, deleted.text
    assert Path(deleted.json()["backup"]).parent == tmp_path / "config" / "config-backups"


def test_error_statuses(api: ApiEnv) -> None:
    assert_error(put(api, content="# a\n", name="../x"), 422, "config_name_invalid")
    assert_error(put(api, content="# a\n", scope="project:nope"), 404, "config_scope_unknown")
    assert_error(put(api, content="# a\n", kind="secrets"), 422, "config_kind_unknown")
    assert put(api, content="# a\n").status_code == 200
    assert_error(put(api, content="# b\n"), 409, "config_exists")
    assert_error(
        put(api, kind="settings", name="settings", content="{"),
        422,
        "config_json_invalid",
    )
    big = "x" * (512 * 1024 + 1)
    assert_error(put(api, content=big), 413, "config_too_large")
    assert_error(
        put(api, content="# a\n", extra=1),
        422,
        "validation_error",
    )


def test_put_without_etag_field_means_create(api: ApiEnv) -> None:
    body = {"scope": "project:leveling", "kind": "commands", "name": "ship", "content": "x\n"}
    assert api.client.put("/api/claude-config/file", json=body).status_code == 200
    assert (api.backend / ".claude" / "commands" / "ship.md").read_text() == "x\n"


def test_apply_endpoint(api: ApiEnv, tmp_path: Path) -> None:
    resp = api.client.post(
        "/api/claude-config/apply",
        json={
            "kind": "skills",
            "name": "deploy",
            "content": SKILL,
            "scopes": ["global", "project:leveling", "project:leveling:1"],
        },
    )
    assert resp.status_code == 200, resp.text
    statuses = [result["status"] for result in resp.json()["results"]]
    assert statuses == ["created", "created", "created"]
    assert (api.web / ".claude" / "skills" / "deploy" / "SKILL.md").is_file()
    assert (tmp_path / ".claude" / "skills" / "deploy" / "SKILL.md").is_file()


def test_nothing_is_committed(api: ApiEnv) -> None:
    """Agent Hub faqat fayl yozadi: hech qanday git buyrug'i (commit, add) chaqirilmaydi."""
    source = (Path(__file__).parents[2] / "src/agent_hub/services/claude_config.py").read_text()
    assert '"commit"' not in source and '"add"' not in source
