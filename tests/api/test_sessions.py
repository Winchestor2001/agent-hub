from __future__ import annotations

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
    assert [p["id"] for p in live] == ["blk", "work", "fake", "out"]
    blk, work, fake, out = live
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
    assert [p["id"] for p in filtered.json()["live"]] == ["blk", "work", "fake"]
    assert [p["id"] for p in filtered.json()["finished"]] == ["dead2", "dead"]
    assert len(filtered.json()["past"]) == 1
    assert_error(
        api.client.get("/api/sessions", params={"project": "nope"}), 404, "project_not_found"
    )


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
