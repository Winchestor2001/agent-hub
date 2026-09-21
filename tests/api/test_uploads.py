"""`POST /api/projects/{id}/uploads` va yuklangan fayllarning promptga/tavsifga tushishi."""

from __future__ import annotations

from typing import Any

from agent_hub.services import uploads

from .conftest import ApiEnv, assert_error

PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 32


def upload(api: ApiEnv, *files: tuple[str, bytes], **data: str) -> Any:
    payload = [("files", (name, content, "application/octet-stream")) for name, content in files]
    return api.client.post("/api/projects/leveling/uploads", files=payload, data=data)


def test_upload_returns_relative_paths(api: ApiEnv) -> None:
    resp = upload(api, ("shot.png", PNG), task_id="TASK-7")
    assert resp.status_code == 201, resp.text
    [item] = resp.json()["files"]
    assert item["path"].startswith(".agent-hub/uploads/task-7/")
    assert item["path"].endswith("-shot.png")
    assert item["size"] == len(PNG)
    assert item["kind"] == "image"
    assert (api.backend / item["path"]).read_bytes() == PNG


def test_upload_without_task_goes_to_inbox(api: ApiEnv) -> None:
    [item] = upload(api, ("notes.md", b"# salom")).json()["files"]
    assert item["path"].startswith(".agent-hub/uploads/inbox/")
    assert item["kind"] == "file"


def test_upload_to_second_repo(api: ApiEnv) -> None:
    [item] = upload(api, ("shot.png", PNG), cwd=str(api.web)).json()["files"]
    assert (api.web / item["path"]).is_file()
    assert not (api.backend / item["path"]).exists()


def test_upload_outside_project_is_rejected(api: ApiEnv) -> None:
    resp = upload(api, ("shot.png", PNG), cwd=str(api.outside))
    assert_error(resp, 422, "cwd_outside_project")


def test_upload_rejects_unknown_type(api: ApiEnv) -> None:
    assert_error(upload(api, ("virus.exe", b"MZ")), 415, "upload_type_invalid")


def test_upload_has_no_size_limit(api: ApiEnv) -> None:
    big = b"x" * (11 * 1024 * 1024)
    resp = upload(api, ("big.png", big))
    assert resp.status_code == 201, resp.text
    [item] = resp.json()["files"]
    assert item["size"] == len(big)
    assert (api.backend / item["path"]).stat().st_size == len(big)


def test_upload_accepts_video(api: ApiEnv) -> None:
    clip = b"\x00\x00\x00\x18ftypmp42" + b"0" * 64
    resp = upload(api, ("Demo clip.MOV", clip), task_id="TASK-7")
    assert resp.status_code == 201, resp.text
    [item] = resp.json()["files"]
    assert item["kind"] == "video"
    assert item["path"].startswith(".agent-hub/uploads/task-7/")
    assert item["path"].endswith("-Demo-clip.mov")
    assert (api.backend / item["path"]).read_bytes() == clip


def test_upload_type_error_lists_allowed_types(api: ApiEnv) -> None:
    resp = upload(api, ("notes.svg", b"<svg/>"))
    assert_error(resp, 415, "upload_type_invalid")
    allowed = resp.json()["params"]["allowed"]
    assert ".png" in allowed
    assert ".mp4" in allowed
    assert ".svg" not in allowed


def test_upload_rejects_too_many(api: ApiEnv) -> None:
    files = [(f"f{i}.png", PNG) for i in range(uploads.MAX_FILES + 1)]
    assert_error(upload(api, *files), 422, "upload_too_many")


def test_upload_unknown_project(api: ApiEnv) -> None:
    resp = api.client.post(
        "/api/projects/yo-q/uploads", files=[("files", ("a.png", PNG, "image/png"))]
    )
    assert_error(resp, 404, "project_not_found")


def test_created_task_description_lists_files(api: ApiEnv) -> None:
    [item] = upload(api, ("shot.png", PNG)).json()["files"]
    resp = api.client.post(
        "/api/projects/leveling/tasks",
        json={"title": "Media", "description": "Rasmga qara", "files": [item["path"]]},
    )
    assert resp.status_code == 201, resp.text
    [create] = api.backlog.commands("task", "create")
    [description] = [arg for arg in create if arg.startswith("--description=")]
    assert description.endswith(f"\n- {item['path']}")
    assert "Rasmga qara" in description


def test_task_files_without_description(api: ApiEnv) -> None:
    [item] = upload(api, ("shot.png", PNG)).json()["files"]
    body = {"title": "Media", "files": [item["path"]]}
    api.client.post("/api/projects/leveling/tasks", json=body)
    [create] = api.backlog.commands("task", "create")
    assert any(arg.startswith("--description=") and item["path"] in arg for arg in create)


def test_task_rejects_foreign_file(api: ApiEnv) -> None:
    (api.backend / "secret.txt").write_text("sir")
    resp = api.client.post(
        "/api/projects/leveling/tasks", json={"title": "Media", "files": ["secret.txt"]}
    )
    assert_error(resp, 404, "upload_not_found")


def test_started_session_prompt_lists_files(api: ApiEnv) -> None:
    [item] = upload(api, ("shot.png", PNG), task_id="TASK-7").json()["files"]
    resp = api.client.post(
        "/api/projects/leveling/sessions",
        json={"agent": "claude", "prompt": "Qara", "files": [item["path"]]},
    )
    assert resp.status_code == 201, resp.text
    [started] = api.started
    assert started["prompt"].endswith(f"\n- {item['path']}")
    assert "Qara" in started["prompt"]


def test_session_rejects_file_from_other_repo(api: ApiEnv) -> None:
    [item] = upload(api, ("shot.png", PNG), cwd=str(api.web)).json()["files"]
    resp = api.client.post(
        "/api/projects/leveling/sessions",
        json={"agent": "claude", "cwd": str(api.backend), "files": [item["path"]]},
    )
    assert_error(resp, 404, "upload_not_found")
