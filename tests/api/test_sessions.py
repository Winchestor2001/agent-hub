from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from agent_hub.services.sessions import SESSION_PROMPT_TEMPLATE

from .conftest import ApiEnv, assert_error, runner

IDLE_SCREEN = "Tayyor.\n\n> \n? for shortcuts\n"


def test_list_sessions(api: ApiEnv) -> None:
    api.pane(id="work", title="TASK-2 · API", state="working", last_output_at=50.0)
    api.pane(id="blk", title="TASK-1 · Login", state="blocked", last_output_at=10.0)
    api.pane(id="fake", agent="claude", state="blocked", last_output_at=20.0)
    api.pane(id="dead", state="done", alive=False, ended_at=30.0, exit_code=0)
    api.pane(id="dead2", title="TASK-2 · API", state="done", alive=False, ended_at=40.0)
    api.pane(id="dead-out", cwd=str(api.outside), state="done", alive=False, ended_at=50.0)
    api.pane(id="out", cwd=str(api.outside), state="idle", last_output_at=5.0)
    api.screens["fake"] = IDLE_SCREEN
    api.session(session_id="11111111-aaaa", title="Работай только над TASK-1.", mtime=1.0)
    api.session(session_id="22222222-bbbb", cwd=str(api.web), mtime=3.0)
    api.session(session_id="33333333-cccc", cwd=str(api.outside), mtime=9.0)

    resp = api.client.get("/api/sessions")
    assert resp.status_code == 200
    data = resp.json()
    live = data["live"]
    # Tartib — boshlanish vaqti bo'yicha; holat va chiqish vaqti hisobga olinmaydi.
    assert [p["id"] for p in live] == ["work", "blk", "fake", "out"]
    work, blk, fake, out = live
    assert (blk["state"], blk["raw_state"], blk["approximate"]) == ("blocked", "blocked", False)
    assert blk["task"] == {"id": "TASK-1", "title": "Login sahifasi", "status": "To Do"}
    assert work["task"]["id"] == "TASK-2"
    # Hook'dan kelgan soxta blocked ekrandan idle deb tuzatiladi.
    assert (fake["state"], fake["raw_state"], fake["approximate"]) == ("idle", "blocked", True)
    assert (out["project_id"], out["task"]) == (None, None)

    finished = data["finished"]
    assert [p["id"] for p in finished] == ["dead-out", "dead2", "dead"]
    assert (finished[1]["alive"], finished[1]["task"]["id"]) == (False, "TASK-2")
    assert finished[2]["exit_code"] == 0

    past = data["past"]
    assert [s["session_id"] for s in past] == ["22222222-bbbb", "11111111-aaaa"]
    assert past[0]["project_id"] == "leveling"
    assert past[1]["task"]["id"] == "TASK-1"

    filtered = api.client.get("/api/sessions", params={"project": "leveling", "past_limit": 1})
    assert [p["id"] for p in filtered.json()["live"]] == ["work", "blk", "fake"]
    assert [p["id"] for p in filtered.json()["finished"]] == ["dead2", "dead"]
    assert len(filtered.json()["past"]) == 1
    assert_error(
        api.client.get("/api/sessions", params={"project": "nope"}), 404, "project_not_found"
    )


def live_ids(api: ApiEnv) -> list[str]:
    return [p["id"] for p in api.client.get("/api/sessions").json()["live"]]


def test_live_order_ignores_state_and_output(api: ApiEnv) -> None:
    first = api.pane(id="first", state="idle", last_output_at=1.0)
    second = api.pane(id="second", state="working", last_output_at=2.0)
    third = api.pane(id="third", state="idle")
    assert live_ids(api) == ["first", "second", "third"]

    # Holat va chiqish o'zgarsa ham qatorlar joyida qoladi.
    first.update(state="working", last_output_at=900.0)
    second.update(state="blocked", last_output_at=10.0)
    third.update(state="blocked", last_output_at=999.0)
    assert live_ids(api) == ["first", "second", "third"]


def test_live_order_ties_by_id_and_unknown_start_last(api: ApiEnv) -> None:
    api.pane(id="b", started_at=1000.0)
    api.pane(id="a", started_at=1000.0)
    api.pane(id="none", started_at=None)
    api.pane(id="old", started_at=10.0)
    assert live_ids(api) == ["old", "a", "b", "none"]


def test_session_open_in_live_pane_is_not_past(api: ApiEnv) -> None:
    """Tirik pane'dagi sessiya «Jonli agentlar»da — o'tganlarda takrorlanmaydi va resume qilinmaydi.

    KanBot fayl jim turgani uchun `active=False` desa ham u ochiq.
    """
    hooked = api.session(session_id="aaaaaaaa-hook")
    resumed = api.session(session_id="bbbbbbbb-resume")
    closed = api.session(session_id="cccccccc-closed")
    dead = api.session(session_id="dddddddd-dead")
    # Qo'lda ochilgan claude pane: session_id bo'sh, sessiya papka/vaqt bo'yicha topiladi.
    guessed = api.session(session_id="eeeeeeee-guess", agent="claude", started_at=1010.0)
    api.pane(session_id=hooked["session_id"])
    api.pane(argv=["codex", "resume", resumed["session_id"]], agent="codex")
    api.pane(session_id=dead["session_id"], state="done", alive=False)
    manual = api.pane(id="manual", started_at=1000.0)

    past = api.client.get("/api/sessions").json()["past"]
    assert {s["session_id"]: s["active"] for s in past} == {
        closed["session_id"]: False,
        dead["session_id"]: False,
    }
    url = "/api/projects/leveling/sessions/resume"
    for session in (hooked, resumed, guessed):
        body = {"agent": session["agent"], "session_id": session["session_id"]}
        assert_error(api.client.post(url, json=body), 409, "session_active")
    assert api.started == []

    # Pane tugagach sessiya o'tganlarga qaytadi va davom ettiriladi.
    manual["alive"] = False
    past_ids = [s["session_id"] for s in api.client.get("/api/sessions").json()["past"]]
    assert guessed["session_id"] in past_ids
    body = {"agent": "claude", "session_id": guessed["session_id"]}
    assert api.client.post(url, json=body).status_code == 201


def test_session_options_work_without_kanbot(api: ApiEnv) -> None:
    api.kanbot_down = True
    resp = api.client.get("/api/sessions/options")
    assert resp.status_code == 200
    data = resp.json()
    assert data == {"agents": ["claude", "codex"], "prompt_template": SESSION_PROMPT_TEMPLATE}
    assert "{task_id}" in data["prompt_template"]


def test_list_sessions_without_kanbot_is_503(api: ApiEnv) -> None:
    api.kanbot_down = True
    body = assert_error(api.client.get("/api/sessions"), 503, "kanbot_unavailable")
    assert body["detail"]


def test_start_session_for_task(api: ApiEnv) -> None:
    resp = api.client.post(
        "/api/projects/leveling/sessions",
        json={"agent": "claude", "cwd": str(api.web), "task_id": "task-1", "prompt": "Testlar"},
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["id"] == "new1"
    assert data["task"]["id"] == "TASK-1"
    assert api.started == [
        {
            "agent": "claude",
            "prompt": SESSION_PROMPT_TEMPLATE.format(task_id="TASK-1") + "\n\nTestlar",
            "cwd": str(api.web),
            "interactive": True,
            "resume": "",
            "title": "TASK-1 · Login sahifasi",
            "runner_id": "r1",
        }
    ]


@pytest.mark.parametrize(
    ("body", "status", "code"),
    [
        ({"agent": "shell"}, 422, "agent_invalid"),
        ({"agent": "claude", "cwd": "OUTSIDE"}, 422, "cwd_outside_project"),
        ({"agent": "claude", "task_id": "TASK-42"}, 404, "task_not_found"),
        ({"agent": "claude", "runner_id": "r1"}, 422, "validation_error"),
    ],
)
def test_start_session_rejected(api: ApiEnv, body: dict[str, Any], status: int, code: str) -> None:
    if body.get("cwd") == "OUTSIDE":
        body["cwd"] = str(api.outside)
    assert_error(api.client.post("/api/projects/leveling/sessions", json=body), status, code)
    assert api.started == []


def test_start_session_needs_safe_runner(api: ApiEnv) -> None:
    url = "/api/projects/leveling/sessions"
    api.runners[:] = [runner(capabilities=["claude"])]
    assert_error(api.client.post(url, json={"agent": "codex"}), 409, "agent_unavailable")
    api.runners[:] = [runner(auto_approve=1)]
    assert_error(api.client.post(url, json={"agent": "codex"}), 409, "runner_unsafe")
    api.kanbot_down = True
    assert_error(api.client.post(url, json={"agent": "codex"}), 503, "kanbot_unavailable")
    assert api.started == []


def test_resume_in_original_cwd(api: ApiEnv) -> None:
    api.runners[:] = [runner(id="r0"), runner(id="r1")]
    session = api.session(
        agent="codex",
        session_id="0199a1b2-c3d4-7e5f",
        cwd=str(api.backend / "sub"),
        title="Работай только над TASK-1.",
        runner_id="r1",
    )
    resp = api.client.post(
        "/api/projects/leveling/sessions/resume",
        json={"agent": "codex", "session_id": session["session_id"]},
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["task"]["id"] == "TASK-1"
    assert api.started == [
        {
            "agent": "codex",
            "prompt": "",
            "cwd": str(api.backend / "sub"),
            "interactive": True,
            "resume": "0199a1b2-c3d4-7e5f",
            "title": "TASK-1 · Login sahifasi",
            "runner_id": "r1",
        }
    ]


def test_resume_does_not_accept_cwd_from_client(api: ApiEnv) -> None:
    session = api.session(cwd=str(api.outside))
    body = {"agent": "codex", "session_id": session["session_id"], "cwd": str(api.backend)}
    assert_error(
        api.client.post("/api/projects/leveling/sessions/resume", json=body),
        422,
        "validation_error",
    )
    assert api.started == []


def test_resume_rejected(api: ApiEnv) -> None:
    outside = api.session(session_id="aaaaaaaa-0001", cwd=str(api.outside))
    active = api.session(session_id="aaaaaaaa-0002", active=True)
    codex = api.session(session_id="aaaaaaaa-0003", agent="codex")
    url = "/api/projects/leveling/sessions/resume"

    def resume(session: dict[str, Any]) -> Any:
        return api.client.post(
            url, json={"agent": session["agent"], "session_id": session["session_id"]}
        )

    body = assert_error(resume(outside), 422, "cwd_outside_project")
    assert body["params"] == {"cwd": str(api.outside), "project": "leveling"}
    assert_error(resume(active), 409, "session_active")
    assert_error(
        resume({"agent": "claude", "session_id": codex["session_id"]}), 404, "session_not_found"
    )
    api.runners[:] = [runner(capabilities=["claude"])]
    body = assert_error(resume(codex), 409, "agent_unavailable")
    assert body["params"] == {"agent": "codex"}
    assert api.started == []


def test_remove_finished_session(api: ApiEnv) -> None:
    api.pane(id="alive")
    api.pane(id="done-alive", state="done")
    api.pane(id="dead", state="done", alive=False)
    assert api.client.delete("/api/sessions/dead").json() == {"ok": True}
    assert api.removed == ["dead"]
    assert api.client.get("/api/sessions").json()["finished"] == []

    # Tirik pane (SessionEnd hook'dan keyingi done ham) olib tashlanmaydi — KanBot uni o'ldiradi.
    for pane_id in ("alive", "done-alive"):
        assert_error(api.client.delete(f"/api/sessions/{pane_id}"), 409, "pane_alive")
    assert_error(api.client.delete("/api/sessions/zzz"), 404, "pane_not_found")
    assert_error(api.client.delete("/api/sessions/a.b"), 422, "pane_id_invalid")
    api.kanbot_down = True
    assert_error(api.client.delete("/api/sessions/alive"), 503, "kanbot_unavailable")
    assert api.removed == ["dead"]


def test_kill_session(api: ApiEnv) -> None:
    api.pane(id="p1")
    assert api.client.post("/api/sessions/p1/kill").json() == {"ok": True}
    assert api.killed == ["p1"]
    assert_error(api.client.post("/api/sessions/zzz/kill"), 404, "pane_not_found")
    assert_error(api.client.post("/api/sessions/a.b/kill"), 422, "pane_id_invalid")
    api.kanbot_down = True
    assert_error(api.client.post("/api/sessions/p1/kill"), 503, "kanbot_unavailable")
    assert api.killed == ["p1"]


def _transcript(api: ApiEnv, session_id: str, agent: str = "claude") -> Path:
    root = api.backend.parent
    if agent == "claude":
        path = root / ".claude" / "projects" / "-leveling" / f"{session_id}.jsonl"
    else:
        path = root / ".codex" / "sessions" / "2026" / f"rollout-2026-05-01-{session_id}.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("{}\n")
    return path


def test_delete_past_sessions(api: ApiEnv) -> None:
    claude_file = _transcript(api, "aaaaaaaa-0001")
    codex_file = _transcript(api, "aaaaaaaa-0002", agent="codex")
    kept_file = _transcript(api, "aaaaaaaa-0003")
    api.session(agent="claude", session_id="aaaaaaaa-0001", path=str(claude_file))
    api.session(agent="codex", session_id="aaaaaaaa-0002", cwd=str(api.web), path=str(codex_file))
    api.session(agent="claude", session_id="aaaaaaaa-0003", path=str(kept_file))

    body = {
        "sessions": [
            {"agent": "claude", "session_id": "aaaaaaaa-0001"},
            {"agent": "codex", "session_id": "aaaaaaaa-0002"},
            {"agent": "claude", "session_id": "aaaaaaaa-0001"},
        ]
    }
    resp = api.client.post("/api/projects/leveling/sessions/delete", json=body)
    assert resp.status_code == 200, resp.text
    assert resp.json() == {"deleted": 2}
    assert not claude_file.exists() and not codex_file.exists() and kept_file.exists()

    # Runner qayta skanerlaguncha KanBot eski ro'yxatni beradi — Agent Hub ularni ko'rsatmaydi.
    past = api.client.get("/api/sessions?project=leveling").json()["past"]
    assert [s["session_id"] for s in past] == ["aaaaaaaa-0003"]
    assert "path" not in past[0]
    assert_error(
        api.client.post("/api/projects/leveling/sessions/resume", json=body["sessions"][0]),
        404,
        "session_not_found",
    )


def test_delete_past_sessions_rejected(api: ApiEnv) -> None:
    files = {sid: _transcript(api, sid) for sid in ("bbbbbbbb-0001", "bbbbbbbb-0002")}
    api.session(agent="claude", session_id="bbbbbbbb-0001", path=str(files["bbbbbbbb-0001"]))
    active = api.session(agent="claude", session_id="bbbbbbbb-0002", active=True)
    active["path"] = str(files["bbbbbbbb-0002"])
    outside = api.session(agent="claude", session_id="bbbbbbbb-0003", cwd=str(api.outside))
    open_pane = api.session(agent="claude", session_id="bbbbbbbb-0004")
    api.pane(agent="claude", argv=["claude", "--resume", open_pane["session_id"]])
    stray = api.backend.parent / "stray" / "bbbbbbbb-0005.jsonl"
    stray.parent.mkdir()
    stray.write_text("{}\n")
    api.session(agent="claude", session_id="bbbbbbbb-0005", path=str(stray))
    url = "/api/projects/leveling/sessions/delete"

    def delete(*session_ids: str) -> Any:
        items = [{"agent": "claude", "session_id": sid} for sid in session_ids]
        return api.client.post(url, json={"sessions": items})

    # Bittasi mos kelmasa, oldingi to'g'ri sessiya ham o'chirilmaydi.
    assert_error(delete("bbbbbbbb-0001", "bbbbbbbb-0002"), 409, "session_active")
    assert_error(delete("bbbbbbbb-0001", "bbbbbbbb-0004"), 409, "session_active")
    assert_error(delete("bbbbbbbb-0001", outside["session_id"]), 404, "session_not_found")
    assert_error(delete("bbbbbbbb-0001", "missing"), 404, "session_not_found")
    body = assert_error(delete("bbbbbbbb-0001", "bbbbbbbb-0005"), 404, "session_file_not_found")
    assert body["params"] == {"session_id": "bbbbbbbb-0005"}
    assert all(path.exists() for path in files.values()) and stray.exists()

    assert_error(api.client.post(url, json={"sessions": []}), 422, "validation_error")
    assert_error(
        api.client.post(
            "/api/projects/nope/sessions/delete",
            json={"sessions": [{"agent": "claude", "session_id": "bbbbbbbb-0001"}]},
        ),
        404,
        "project_not_found",
    )
