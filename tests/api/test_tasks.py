from __future__ import annotations

from typing import Any

import pytest

from agent_hub.backlog_client import CliResult

from .conftest import ApiEnv, assert_error, fixture_text


def _by_id(tasks: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {task["id"]: task for task in tasks}


def test_board(api: ApiEnv) -> None:
    api.pane(id="p1", title="task-001 · Login", state="working", last_output_at=10.0)
    api.pane(id="p2", cwd=str(api.web), argv=["codex", "Работай только над TASK-1."], state="idle")
    api.pane(id="p3", title="TASK-1", state="done", alive=False)
    api.pane(id="p4", title="TASK-2", cwd=str(api.outside))

    resp = api.client.get("/api/projects/leveling/board")
    assert resp.status_code == 200
    data = resp.json()
    assert data["project"]["id"] == "leveling"
    assert data["kanbot_available"] is True
    assert data["task_prefix"] == "task"
    assert data["statuses"] == ["To Do", "In Progress", "Done"]
    assert data["labels"] == ["backend", "admin", "client", "bug"]
    assert data["milestones"][0] == {
        "id": "m-0",
        "title": "Release 1",
        "done": 0,
        "total": 1,
        "completed": False,
    }

    tasks = _by_id(data["tasks"])
    assert list(tasks) == ["TASK-1", "TASK-1.1", "TASK-2"]
    card = tasks["TASK-1"]
    assert card["title"] == "Login sahifasi"
    assert card["labels"] == ["ui", "Bug"]
    assert card["assignees"] == ["@alice"]
    assert card["milestone"] == "m-0"
    assert (card["acceptance_criteria_completed"], card["acceptance_criteria_count"]) == (1, 2)
    assert (card["dod_completed"], card["dod_count"]) == (1, 1)
    # Bog'lanish: sarlavha (kanonik ID) va argv'dagi prompt; o'lik va loyihadan tashqari pane yo'q.
    assert [s["id"] for s in card["sessions"]] == ["p1", "p2"]
    assert card["sessions"][0]["task"] == {
        "id": "TASK-1",
        "title": "Login sahifasi",
        "status": "To Do",
    }
    assert card["sessions"][0]["project_id"] == "leveling"
    assert tasks["TASK-2"]["sessions"] == []
    assert tasks["TASK-1.1"]["parent_task_id"] == "TASK-1"


def test_board_without_kanbot_is_200(api: ApiEnv) -> None:
    api.pane(title="TASK-1")
    api.kanbot_down = True
    resp = api.client.get("/api/projects/leveling/board")
    assert resp.status_code == 200
    data = resp.json()
    assert data["kanbot_available"] is False
    assert len(data["tasks"]) == 3
    assert all(task["sessions"] == [] for task in data["tasks"])


def test_board_errors(api: ApiEnv) -> None:
    assert_error(api.client.get("/api/projects/nope/board"), 404, "project_not_found")
    assert_error(api.client.get("/api/projects/broken/board"), 503, "backlog_not_found")
    api.backlog.overrides["task", "list"] = CliResult(0, "not json", "")
    assert_error(api.client.get("/api/projects/leveling/board"), 502, "backlog_bad_output")


def test_task_detail(api: ApiEnv) -> None:
    api.pane(id="p1", title="TASK-1 · Login", state="blocked")
    resp = api.client.get("/api/projects/leveling/tasks/task-001")
    assert resp.status_code == 200
    data = resp.json()
    assert data["id"] == "TASK-1"
    assert data["description"] == "Tavsif **md**"
    assert data["implementation_notes"] == "izoh"
    assert data["implementation_plan"] is None
    assert data["subtasks"] == [{"id": "TASK-1.1", "title": "Sub"}]
    assert data["acceptance_criteria"][1] == {
        "index": 2,
        "text": "Xato ko'rsatiladi",
        "checked": False,
    }
    assert (data["dod_completed"], data["dod_count"]) == (1, 1)
    assert [s["id"] for s in data["sessions"]] == ["p1"]
    assert data["kanbot_available"] is True
    # Asl ID CLI'ga `--` dan keyin beriladi.
    assert api.backlog.commands("task", "view") == [["task", "view", "--json", "--", "TASK-1"]]


def test_task_detail_errors(api: ApiEnv) -> None:
    body = assert_error(
        api.client.get("/api/projects/leveling/tasks/TASK-99"), 404, "task_not_found"
    )
    assert body["params"] == {"task_id": "TASK-99"}
    for bad in ("UTF-8", "--help", "task-1x"):
        assert_error(api.client.get(f"/api/projects/leveling/tasks/{bad}"), 422, "task_id_invalid")
    assert api.backlog.commands("task", "view") == []


def test_create_task(api: ApiEnv) -> None:
    body = {
        "title": "Yangi vazifa",
        "description": "Ko'p\nqatorli",
        "status": "In Progress",
        "labels": ["backend", "bug"],
        "milestone": "m-0",
        "acceptance_criteria": ["Birinchi", "-- ikkinchi"],
    }
    resp = api.client.post("/api/projects/leveling/tasks", json=body)
    assert resp.status_code == 201
    assert resp.json() == {"id": "TASK-4"}
    assert api.backlog.commands("task", "create") == [
        [
            "task",
            "create",
            "--description=Ko'p\nqatorli",
            "--status=In Progress",
            "--labels=backend,bug",
            "--assignee=",
            "--milestone=m-0",
            "--ac=Birinchi",
            "--ac=-- ikkinchi",
            "--",
            "Yangi vazifa",
        ]
    ]


@pytest.mark.parametrize(
    ("body", "code", "params"),
    [
        ({"title": "X", "status": "Blah"}, "status_invalid", {"status": "Blah"}),
        ({"title": "  "}, "field_invalid", {"field": "title"}),
        ({"title": "a\nb"}, "field_invalid", {"field": "title"}),
        ({"title": "X", "labels": ["a,b"]}, "field_invalid", {"field": "labels"}),
        ({"title": "X", "assignees": ["@a,@b"]}, "field_invalid", {"field": "assignees"}),
        ({"title": "X", "acceptance_criteria": ["a\tb"]}, "field_invalid", {}),
        ({"title": "X", "unknown": 1}, "validation_error", {}),
    ],
)
def test_create_task_validation(
    api: ApiEnv, body: dict[str, Any], code: str, params: dict[str, Any]
) -> None:
    error = assert_error(api.client.post("/api/projects/leveling/tasks", json=body), 422, code)
    assert params.items() <= error["params"].items()
    assert api.backlog.commands("task", "create") == []


def test_set_status(api: ApiEnv) -> None:
    resp = api.client.post("/api/projects/leveling/tasks/task-2/status", json={"status": "Done"})
    assert resp.status_code == 200
    assert resp.json() == {"id": "TASK-2", "status": "Done"}
    assert api.backlog.commands("task", "edit") == [
        ["task", "edit", "--status=Done", "--", "TASK-2"]
    ]

    error = assert_error(
        api.client.post("/api/projects/leveling/tasks/TASK-2/status", json={"status": "Nope"}),
        422,
        "status_invalid",
    )
    assert error["params"]["allowed"] == ["To Do", "In Progress", "Done"]
    assert_error(
        api.client.post("/api/projects/leveling/tasks/TASK-9/status", json={"status": "Done"}),
        404,
        "task_not_found",
    )
    assert len(api.backlog.commands("task", "edit")) == 1


def test_complete_task(api: ApiEnv) -> None:
    resp = api.client.post("/api/projects/leveling/tasks/task-2/complete")
    assert resp.status_code == 200
    assert resp.json() == {"id": "TASK-2", "status": "Done"}
    assert api.backlog.commands("task", "edit") == [
        ["task", "edit", "--status=Done", "--", "TASK-2"]
    ]


def test_set_acceptance(api: ApiEnv) -> None:
    resp = api.client.post(
        "/api/projects/leveling/tasks/task-001/acceptance/2", json={"checked": True}
    )
    assert resp.status_code == 200
    assert resp.json() == {"id": "TASK-1", "index": 2, "checked": True}
    resp = api.client.post(
        "/api/projects/leveling/tasks/task-001/acceptance/1", json={"checked": False}
    )
    assert resp.status_code == 200
    assert api.backlog.commands("task", "edit") == [
        ["task", "edit", "--check-ac", "2", "--", "TASK-1"],
        ["task", "edit", "--uncheck-ac", "1", "--", "TASK-1"],
    ]


def test_set_acceptance_rejected(api: ApiEnv) -> None:
    assert_error(
        api.client.post(
            "/api/projects/leveling/tasks/task-001/acceptance/99",
            json={"checked": True},
        ),
        404,
        "checklist_item_not_found",
    )
    assert_error(
        api.client.post(
            "/api/projects/leveling/tasks/task-001/acceptance/1",
            json={"checked": "yes"},
        ),
        422,
        "validation_error",
    )
    assert api.backlog.commands("task", "edit") == []


def test_add_labels(api: ApiEnv) -> None:
    resp = api.client.post(
        "/api/projects/leveling/tasks/TASK-2/labels", json={"labels": ["backend", " api "]}
    )
    assert resp.status_code == 200
    assert resp.json() == {"id": "TASK-2", "labels": ["backend", "api"]}
    assert api.backlog.commands("task", "edit") == [
        ["task", "edit", "--add-label=backend,api", "--", "TASK-2"]
    ]
    assert_error(
        api.client.post("/api/projects/leveling/tasks/TASK-2/labels", json={"labels": []}),
        422,
        "validation_error",
    )


def test_delete_task_archives(api: ApiEnv) -> None:
    resp = api.client.delete("/api/projects/leveling/tasks/task-2")
    assert resp.status_code == 200
    assert resp.json() == {"id": "TASK-2", "archived": True}
    assert api.backlog.commands("task", "archive") == [["task", "archive", "TASK-2"]]
    assert api.backlog.commands("task", "complete") == []


def test_delete_done_task_completes_cleanup(api: ApiEnv) -> None:
    api.backlog.task_overrides["TASK-2"] = {"status": "Done"}
    resp = api.client.delete("/api/projects/leveling/tasks/task-2")
    assert resp.status_code == 200
    assert resp.json() == {"id": "TASK-2", "archived": True}
    assert api.backlog.commands("task", "archive") == []
    assert api.backlog.commands("task", "complete") == [["task", "complete", "TASK-2"]]


def test_delete_task_blocks_live_sessions(api: ApiEnv) -> None:
    api.pane(id="p1", title="TASK-1 · Login", state="working")
    body = assert_error(
        api.client.delete("/api/projects/leveling/tasks/task-001"),
        409,
        "task_has_live_sessions",
    )
    assert body["params"] == {"task_id": "TASK-1", "count": 1}
    assert api.backlog.commands("task", "archive") == []


def test_mutation_cli_errors(api: ApiEnv) -> None:
    url = "/api/projects/leveling/tasks/TASK-2/status"
    api.backlog.overrides["task", "edit"] = CliResult(1, "", fixture_text("backlog/locked.stderr"))
    assert_error(api.client.post(url, json={"status": "Done"}), 409, "backlog_locked")
    assert len(api.backlog.commands("task", "edit")) == 2  # bir marta qayta urinadi

    api.backlog.overrides["task", "edit"] = CliResult(2, "", "boom")
    body = assert_error(api.client.post(url, json={"status": "Done"}), 502, "backlog_cli_error")
    assert body["detail"] == "boom"
