from __future__ import annotations

import os
from dataclasses import replace
from pathlib import Path

from agent_hub.api.deps import Hub
from agent_hub.backlog_client import CliResult

from .conftest import ApiEnv, assert_error


def _home(api: ApiEnv) -> Path:
    return api.backend.parent


def test_suggestions_skip_registered_and_list_backlogs_first(api: ApiEnv) -> None:
    home = _home(api)
    (home / "zeta" / "backlog").mkdir(parents=True)
    (home / "zeta" / "backlog" / "config.yml").write_text("project_name: z\n")
    (home / ".hidden").mkdir()
    (home / "notes.txt").write_text("fayl")

    resp = api.client.get("/api/folders/suggestions")
    assert resp.status_code == 200
    data = resp.json()
    assert data["root"] == str(home)
    assert data["home"] == str(home)
    names = [folder["name"] for folder in data["folders"]]
    # leveling-backend va broken registrda bor; yashirin papka va fayl ko'rinmaydi.
    assert names == ["zeta", "config", "leveling-web", "other"]
    assert data["folders"][0] == {"name": "zeta", "path": str(home / "zeta"), "has_backlog": True}


def test_suggestions_missing_root(api: ApiEnv, tmp_path: Path) -> None:
    hub: Hub = api.client.app.state.hub  # type: ignore[attr-defined]
    hub.settings = replace(hub.settings, projects_root=tmp_path / "yoq")
    resp = api.client.get("/api/folders/suggestions")
    assert resp.json()["folders"] == []


def test_browse_default_and_navigation(api: ApiEnv) -> None:
    home = _home(api)
    resp = api.client.get("/api/folders")
    assert resp.status_code == 200
    data = resp.json()
    assert data["path"] == str(home)
    assert data["parent"] is None
    assert "leveling-backend" in [entry["name"] for entry in data["entries"]]

    data = api.client.get("/api/folders", params={"path": str(api.backend)}).json()
    assert data["has_backlog"] is True
    assert data["parent"] == str(home)
    assert data["in_git"] is False
    assert [entry["name"] for entry in data["entries"]] == ["sub"]  # .backlog yashirin

    (api.web / ".git").mkdir()
    (api.web / "src").mkdir()
    data = api.client.get("/api/folders", params={"path": str(api.web / "src")}).json()
    assert data["in_git"] is True
    assert data["has_backlog"] is False


def test_browse_rejects_outside_home_and_files(api: ApiEnv) -> None:
    home = _home(api)
    resp = api.client.get("/api/folders", params={"path": str(home.parent)})
    assert_error(resp, 403, "path_outside_home")
    resp = api.client.get("/api/folders", params={"path": str(home / ".." / "..")})
    assert_error(resp, 403, "path_outside_home")
    (home / "notes.txt").write_text("fayl")
    resp = api.client.get("/api/folders", params={"path": str(home / "notes.txt")})
    assert_error(resp, 422, "path_invalid")
    resp = api.client.get("/api/folders", params={"path": str(home / "yoq")})
    assert_error(resp, 422, "path_invalid")


def test_browse_symlink_escape_is_rejected(api: ApiEnv) -> None:
    home = _home(api)
    outside = Path(os.path.realpath(home.parent))
    os.symlink(outside, home / "link")
    resp = api.client.get("/api/folders", params={"path": str(home / "link")})
    assert_error(resp, 403, "path_outside_home")
    names = [e["name"] for e in api.client.get("/api/folders").json()["entries"]]
    assert "link" not in names and outside.name not in names


def test_init_backlog_then_add_project(api: ApiEnv) -> None:
    resp = api.client.post(
        "/api/folders/init-backlog", json={"path": str(api.outside), "name": "  --Other  app "}
    )
    assert resp.status_code == 201, resp.text
    assert resp.json() == {"path": str(api.outside), "name": "Other app", "has_backlog": True}
    base = ["init", "Other app", "--defaults", "--backlog-dir", ".backlog", "--integration-mode"]
    assert api.backlog.commands("init") == [[*base, "none", "--no-git"]]
    assert (api.outside / ".backlog" / "config.yml").is_file()

    resp = api.client.post(
        "/api/projects", json={"id": "other", "name": "Other", "backlog_dir": str(api.outside)}
    )
    assert resp.status_code == 201, resp.text


def test_init_backlog_errors(api: ApiEnv) -> None:
    home = _home(api)
    post = api.client.post
    resp = post("/api/folders/init-backlog", json={"path": str(api.backend), "name": "X"})
    assert_error(resp, 409, "backlog_exists")
    resp = post("/api/folders/init-backlog", json={"path": str(home.parent), "name": "X"})
    assert_error(resp, 403, "path_outside_home")
    resp = post("/api/folders/init-backlog", json={"path": str(api.web), "name": " - "})
    assert_error(resp, 422, "project_name_empty")
    assert api.backlog.commands("init") == []

    api.backlog.overrides["init"] = CliResult(0, "No git repository found\n", "")
    resp = post("/api/folders/init-backlog", json={"path": str(api.web), "name": "Web"})
    body = assert_error(resp, 502, "backlog_init_failed")
    assert body["params"]["path"] == str(api.web)
