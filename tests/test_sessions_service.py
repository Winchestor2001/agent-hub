from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from agent_hub.kanbot_client import AgentSession, Pane, Runner
from agent_hub.registry import Project
from agent_hub.services.sessions import (
    SESSION_FILES_HEADER,
    SESSION_PROMPT_TEMPLATE,
    SessionError,
    SessionService,
    TaskInfo,
    build_prompt,
    session_title,
)

# Talabdagi matnning UTF-8 baytlari (foydalanuvchi xabaridan, `<TASK-ID>` bilan) — o'zgartirilmasin.
SPEC_PROMPT_BYTES = bytes.fromhex(
    "d0a0d0b0d0b1d0bed182d0b0d0b920d182d0bed0bbd18cd0bad0be20d0bdd0b0d0b4203c5441534b2d49443e"
    "2e20d09fd180d0bed187d0b8d182d0b0d0b920606261636b6c6f6720696e737472756374696f6e73206f7665"
    "72766965776020d0b820d0b7d0b0d0b4d0b0d187d1832c20d0bfd0b5d180d0b5d0b2d0b5d0b4d0b820d0b5d1"
    "9120d0b220496e2050726f67726573732c20d0bdd0b0d0bfd0b8d188d0b820d0bfd0bbd0b0d0bd20d0b820d0"
    "b4d0bed0b6d0b4d0b8d181d18c20d0bcd0bed0b5d0b3d0be20d0bed0b4d0bed0b1d180d0b5d0bdd0b8d18f20"
    "d0bfd0b5d180d0b5d0b420d0bad0bed0b4d0bed0bc2e"
)
EXPECTED_PREFIX_TASK_12 = SPEC_PROMPT_BYTES.replace(b"<TASK-ID>", b"TASK-12").decode("utf-8")


def test_prompt_prefix_is_byte_exact() -> None:
    prompt = build_prompt(TaskInfo("TASK-12", "Login sahifasi"))
    assert prompt.encode("utf-8") == SPEC_PROMPT_BYTES.replace(b"<TASK-ID>", b"TASK-12")
    assert SESSION_PROMPT_TEMPLATE.encode("utf-8") == SPEC_PROMPT_BYTES.replace(
        b"<TASK-ID>", b"{task_id}"
    )


def test_prompt_with_extra_text_starts_with_prefix() -> None:
    prompt = build_prompt(TaskInfo("TASK-3", "X"), "  Testlarga e'tibor ber.\n")
    assert prompt.startswith(SESSION_PROMPT_TEMPLATE.format(task_id="TASK-3"))
    assert prompt.endswith("\n\nTestlarga e'tibor ber.")
    assert build_prompt(TaskInfo("TASK-3", "X"), "   ") == SESSION_PROMPT_TEMPLATE.format(
        task_id="TASK-3"
    )
    assert build_prompt(None, " salom ") == "salom"
    assert build_prompt(None) == ""


def test_session_title() -> None:
    assert session_title(TaskInfo("TASK-12", " Login  sahifasi ")) == "TASK-12 · Login sahifasi"
    assert session_title(None, "Leveling") == "Leveling"
    long = session_title(TaskInfo("TASK-1", "x" * 300))
    assert len(long) == 120
    assert long.endswith("…")


# --- SessionService -------------------------------------------------------------------------


class FakeKanbot:
    def __init__(self, runners: list[Runner]) -> None:
        self._runners = runners
        self.started: list[dict[str, Any]] = []

    async def runners(self) -> list[Runner]:
        return self._runners

    async def start_pane(self, agent: str, **kwargs: Any) -> Pane:
        self.started.append({"agent": agent, **kwargs})
        return Pane(id="new1", agent=agent, cwd=kwargs["cwd"], title=kwargs.get("title", ""))


def _runner(**overrides: Any) -> Runner:
    data: dict[str, Any] = {
        "id": "r1",
        "name": "mac",
        "status": "online",
        "capabilities": ["claude", "codex"],
        "auto_approve": 0,
    }
    data.update(overrides)
    return Runner.model_validate(data)


@pytest.fixture
def dirs(tmp_path: Path) -> dict[str, Path]:
    backend = tmp_path / "leveling-backend"
    web = tmp_path / "leveling-web"
    outside = tmp_path / "other"
    for directory in (backend / "sub", web, outside):
        directory.mkdir(parents=True)
    (tmp_path / "link").symlink_to(backend, target_is_directory=True)
    return {"root": tmp_path, "backend": backend, "web": web, "outside": outside}


@pytest.fixture
def project(dirs: dict[str, Path]) -> Project:
    # Bekloq papkasi repos'da takrorlanmaydi, lekin baribir birinchi (standart) loyiha papkasi.
    return Project(
        id="leveling", name="Leveling", backlog_dir=dirs["backend"], repos=(dirs["web"],)
    )


def _service(*runners: Runner) -> tuple[SessionService, FakeKanbot]:
    kanbot = FakeKanbot(list(runners) or [_runner()])
    return SessionService(kanbot), kanbot  # type: ignore[arg-type]


async def test_start_with_task(project: Project, dirs: dict[str, Path]) -> None:
    service, kanbot = _service(_runner(id="r0", status="offline"), _runner())
    pane = await service.start(
        project, "claude", cwd=str(dirs["web"]), task=TaskInfo("TASK-12", "Login sahifasi")
    )
    assert pane.id == "new1"
    assert kanbot.started == [
        {
            "agent": "claude",
            "prompt": EXPECTED_PREFIX_TASK_12,
            "cwd": str(dirs["web"]),
            "title": "TASK-12 · Login sahifasi",
            "runner_id": "r1",
        }
    ]


async def test_start_defaults(project: Project, dirs: dict[str, Path]) -> None:
    service, kanbot = _service()
    await service.start(project, "codex", prompt="Salom")
    assert kanbot.started[0] == {
        "agent": "codex",
        "prompt": "Salom",
        "cwd": str(dirs["backend"]),
        "title": "Leveling",
        "runner_id": "r1",
    }
    # Symlink orqali berilgan loyiha papkasi — asl registr yo'li ishlatiladi.
    await service.start(project, "codex", cwd=str(dirs["root"] / "link"))
    assert kanbot.started[1]["cwd"] == str(dirs["backend"])


@pytest.mark.parametrize(
    "agent", ["shell", "glm", "kimi", "", "claude --dangerously-skip-permissions"]
)
async def test_start_rejects_other_agents(project: Project, agent: str) -> None:
    service, kanbot = _service(_runner(capabilities=["claude", "codex", "shell"]))
    with pytest.raises(SessionError) as err:
        await service.start(project, agent)
    assert err.value.code == "agent_invalid"
    assert kanbot.started == []


@pytest.mark.parametrize("where", ["outside", "sub", "root"])
async def test_start_rejects_cwd_outside_project_dirs(
    project: Project, dirs: dict[str, Path], where: str
) -> None:
    service, kanbot = _service()
    cwd = dirs["backend"] / "sub" if where == "sub" else dirs[where]
    with pytest.raises(SessionError) as err:
        await service.start(project, "claude", cwd=str(cwd))
    assert err.value.code == "cwd_outside_project"
    assert kanbot.started == []


async def test_start_missing_project_dir(dirs: dict[str, Path]) -> None:
    gone = dirs["root"] / "gone"
    project = Project(id="x", name="X", backlog_dir=gone)
    service, _ = _service()
    with pytest.raises(SessionError) as err:
        await service.start(project, "claude")
    assert (err.value.code, err.value.params) == ("path_invalid", {"path": str(gone)})


@pytest.mark.parametrize(
    ("runners", "code"),
    [
        ([], "agent_unavailable"),
        ([_runner(status="offline")], "agent_unavailable"),
        ([_runner(capabilities=["claude"])], "agent_unavailable"),
        ([_runner(auto_approve=1)], "runner_unsafe"),
    ],
)
async def test_start_requires_safe_runner_with_agent(
    project: Project, runners: list[Runner], code: str
) -> None:
    kanbot = FakeKanbot(runners)
    service = SessionService(kanbot)  # type: ignore[arg-type]
    with pytest.raises(SessionError) as err:
        await service.start(project, "codex")
    assert err.value.code == code
    assert kanbot.started == []


async def test_start_skips_auto_approve_runner(project: Project) -> None:
    service, kanbot = _service(_runner(id="unsafe", auto_approve=1), _runner(id="safe"))
    await service.start(project, "claude")
    assert kanbot.started[0]["runner_id"] == "safe"


def _session(**overrides: Any) -> AgentSession:
    data: dict[str, Any] = {
        "agent": "codex",
        "session_id": "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b",
        "cwd": "",
        "name": "leveling-backend",
        "title": None,
        "runner_id": "r1",
    }
    data.update(overrides)
    return AgentSession.model_validate(data)


async def test_resume_uses_original_cwd_and_runner(project: Project, dirs: dict[str, Path]) -> None:
    service, kanbot = _service(_runner(id="r0"), _runner(id="r1"))
    cwd = str(dirs["backend"] / "sub")
    await service.resume(project, _session(cwd=cwd))
    assert kanbot.started == [
        {
            "agent": "codex",
            "cwd": cwd,
            "resume": "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b",
            "title": "leveling-backend",
            "runner_id": "r1",
        }
    ]
    assert "prompt" not in kanbot.started[0]

    await service.resume(
        project, _session(agent="claude", cwd=cwd, runner_id=""), title="TASK-1 · X"
    )
    assert kanbot.started[1]["runner_id"] == "r0"
    assert kanbot.started[1]["title"] == "TASK-1 · X"


async def test_resume_validation(project: Project, dirs: dict[str, Path]) -> None:
    service, kanbot = _service()
    cases: list[tuple[AgentSession, str]] = [
        (_session(cwd=str(dirs["outside"])), "cwd_outside_project"),
        (_session(cwd=""), "cwd_outside_project"),
        (_session(cwd=str(dirs["backend"] / "deleted")), "path_invalid"),
        (_session(cwd=str(dirs["backend"]), agent="shell"), "agent_invalid"),
        (_session(cwd=str(dirs["backend"]), session_id="--last"), "session_id_invalid"),
        (_session(cwd=str(dirs["backend"]), session_id="abc"), "session_id_invalid"),
        (_session(cwd=str(dirs["backend"]), runner_id="gone"), "runner_offline"),
    ]
    for session, code in cases:
        with pytest.raises(SessionError) as err:
            await service.resume(project, session)
        assert err.value.code == code, session
    assert kanbot.started == []


def test_prompt_lists_attached_files() -> None:
    files = [".agent-hub/uploads/task-3/a.png", ".agent-hub/uploads/task-3/b.pdf"]
    prompt = build_prompt(TaskInfo("TASK-3", "X"), "Qara", files)
    assert prompt.startswith(SESSION_PROMPT_TEMPLATE.format(task_id="TASK-3"))
    assert prompt.endswith(f"{SESSION_FILES_HEADER}\n- {files[0]}\n- {files[1]}")
    # Vazifasiz va matnsiz ham fayllar ro'yxati yolg'iz qoladi.
    assert build_prompt(None, "", files[:1]) == f"{SESSION_FILES_HEADER}\n- {files[0]}"
    assert build_prompt(None, "salom", []) == "salom"
