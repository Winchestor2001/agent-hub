from __future__ import annotations

from pathlib import Path

from .conftest import ApiEnv, assert_error


def test_list_projects_with_summary(api: ApiEnv) -> None:
    api.pane(id="p1", title="TASK-1 · Login", state="blocked")
    api.pane(id="p2", cwd=str(api.web), state="working")
    api.pane(id="p3", state="done", alive=False)
    api.pane(id="p4", cwd=str(api.outside), state="blocked")

    resp = api.client.get("/api/projects")
    assert resp.status_code == 200
    data = resp.json()
    assert data["kanbot_available"] is True
    leveling, broken = data["projects"]
    assert leveling["id"] == "leveling"
    assert leveling["repos"] == [str(api.backend), str(api.web)]
    assert leveling["error"] is None
    assert leveling["summary"] == {
        "status_counts": [
            {"status": "To Do", "count": 2},
            {"status": "In Progress", "count": 1},
            {"status": "Done", "count": 0},
        ],
        "total": 3,
        "bugs": 1,
        "open_bugs": 1,
        "active_sessions": 2,
        "blocked_sessions": 1,
        "blocked_pane_ids": ["p1"],
    }
    # Bekloqi yo'q loyiha ro'yxatni buzmaydi.
    assert broken["summary"] is None
    assert broken["error"]["code"] == "backlog_not_found"
    assert api.backlog.cwds and set(api.backlog.cwds) == {api.backend}


def test_list_projects_without_kanbot(api: ApiEnv) -> None:
    api.kanbot_down = True
    resp = api.client.get("/api/projects")
    assert resp.status_code == 200
    data = resp.json()
    assert data["kanbot_available"] is False
    summary = data["projects"][0]["summary"]
    assert summary["total"] == 3
    assert summary["active_sessions"] is None
    assert summary["blocked_sessions"] is None


def test_project_summary(api: ApiEnv) -> None:
    resp = api.client.get("/api/projects/leveling/summary")
    assert resp.status_code == 200
    assert resp.json()["summary"]["bugs"] == 1
    assert_error(api.client.get("/api/projects/nope/summary"), 404, "project_not_found")
    body = assert_error(api.client.get("/api/projects/broken/summary"), 503, "backlog_not_found")
    assert body["params"]["path"].endswith("broken")


def test_add_and_remove_project(api: ApiEnv, tmp_path: Path) -> None:
    new = tmp_path / "shop"
    (new / "backlog").mkdir(parents=True)
    (new / "backlog" / "config.yml").write_text("project_name: Shop\n")

    resp = api.client.post(
        "/api/projects", json={"id": "shop", "name": " Shop ", "backlog_dir": str(new)}
    )
    assert resp.status_code == 201
    assert resp.json() == {
        "id": "shop",
        "name": "Shop",
        "backlog_dir": str(new),
        "repos": [str(new)],
    }
    ids = [p["id"] for p in api.client.get("/api/projects").json()["projects"]]
    assert ids == ["leveling", "broken", "shop"]

    duplicate = {"id": "shop", "name": "Shop", "backlog_dir": str(new)}
    assert_error(api.client.post("/api/projects", json=duplicate), 409, "project_exists")

    assert api.client.delete("/api/projects/shop").json() == {"ok": True}
    assert_error(api.client.delete("/api/projects/shop"), 404, "project_not_found")


def test_add_project_validation(api: ApiEnv) -> None:
    cases = [
        ({"id": "Bad Id", "name": "X", "backlog_dir": str(api.backend)}, "project_id_invalid"),
        ({"id": "x", "name": "X", "backlog_dir": str(api.outside)}, "backlog_not_found"),
        ({"id": "x", "name": "X", "backlog_dir": str(api.outside / "none")}, "path_invalid"),
        ({"id": "x", "name": "  ", "backlog_dir": str(api.backend)}, "project_name_empty"),
        ({"id": "x", "name": "X", "backlog_dir": str(api.backend), "extra": 1}, "validation_error"),
    ]
    for body, code in cases:
        assert_error(api.client.post("/api/projects", json=body), 422, code)
    body = assert_error(api.client.post("/api/projects", json={"id": "x"}), 422, "validation_error")
    assert {tuple(err["loc"]) for err in body["params"]["errors"]} == {
        ("body", "name"),
        ("body", "backlog_dir"),
    }


def test_unknown_api_route_uses_error_format(api: ApiEnv) -> None:
    body = assert_error(api.client.get("/api/nope"), 404, "not_found")
    assert body == {"code": "not_found", "params": {"path": "/api/nope"}, "detail": None}
