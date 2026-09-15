from __future__ import annotations

import json
from pathlib import Path

import pytest

from agent_hub.kanbot_client import AgentSession, Pane
from agent_hub.registry import Project
from agent_hub.services.linking import (
    find_task_keys,
    index_task_ids,
    is_within,
    pane_task_key,
    panes_for_project,
    project_for_path,
    resume_session_id,
    task_key,
)

FIXTURES = Path(__file__).parent / "fixtures" / "kanbot"


def _panes() -> list[Pane]:
    data = json.loads((FIXTURES / "panes.json").read_text(encoding="utf-8"))
    return [Pane.model_validate(item) for item in data["panes"]]


def _sessions() -> list[AgentSession]:
    data = json.loads((FIXTURES / "agent_sessions.json").read_text(encoding="utf-8"))
    return [AgentSession.model_validate(item) for item in data["sessions"]]


# --- ID ------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("task_id", "expected"),
    [
        ("TASK-001", "task-1"),
        ("task-1", "task-1"),
        ("Task-01", "task-1"),
        ("TASK-12", "task-12"),
        ("TASK-1.01", "task-1.1"),
        (" TASK-7 ", "task-7"),
        ("TASK-", None),
        ("TASK-1a", None),
        ("UTF-8", None),
        ("LEV-1", None),
    ],
)
def test_task_key(task_id: str, expected: str | None) -> None:
    assert task_key(task_id, "task") == expected


def test_task_1_equals_task_001() -> None:
    assert task_key("task-1", "task") == task_key("TASK-001", "task")
    assert task_key("TASK-10", "task") != task_key("TASK-1", "task")


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("Работай только над TASK-12. Прочитай", ["task-12"]),
        ("UTF-8 va ISO-8601", []),
        ("subtask-3 va mytask-4 emas", []),
        ("task-1, TASK-001 va (task-2)", ["task-1", "task-2"]),
        ("TASK-1.2 subtask", ["task-1.2"]),
        ("TASK-3.", ["task-3"]),
        ("TASK-3-extra TASK-4_x", []),
        ("", []),
    ],
)
def test_find_task_keys(text: str, expected: list[str]) -> None:
    assert find_task_keys(text, "task") == expected


def test_prefix_is_regex_escaped_and_project_specific() -> None:
    assert find_task_keys("LEV-001 va TASK-1", "lev") == ["lev-1"]
    assert find_task_keys("UTF-8", "utf") == ["utf-8"]
    assert find_task_keys("a.b-1 axb-1", "a.b") == ["a.b-1"]
    with pytest.raises(ValueError):
        task_key("TASK-1", "")


def test_index_task_ids() -> None:
    index = index_task_ids(["TASK-1", "TASK-1.1", "TASK-12", "draft-1"], "task")
    assert index == {"task-1": "TASK-1", "task-1.1": "TASK-1.1", "task-12": "TASK-12"}


# --- pane ↔ vazifa --------------------------------------------------------------------------


CLAUDE_SID = "5f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b"
CODEX_SID = "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b"


@pytest.mark.parametrize(
    ("argv", "expected"),
    [
        (["claude", "--resume", CLAUDE_SID], CLAUDE_SID),
        (["claude", "--resume=5f1e2d3c-4b5a", "--settings", "{hooks}"], "5f1e2d3c-4b5a"),
        (["claude", "-r", "5f1e2d3c-4b5a"], "5f1e2d3c-4b5a"),
        (["codex", "resume", CODEX_SID], CODEX_SID),
        (["codex", "resume", "--last"], None),
        (["codex", "resume the work"], None),
        (["claude", "--resume", "--settings"], None),
        (["claude", "--resume"], None),
        (["claude", "Работай только над TASK-1."], None),
        ([], None),
    ],
)
def test_resume_session_id(argv: list[str], expected: str | None) -> None:
    assert resume_session_id(argv) == expected


def test_pane_task_key_from_title_and_argv() -> None:
    blocked, resumed = _panes()
    assert pane_task_key(blocked, "task") == "task-12"
    by_argv = blocked.model_copy(update={"title": "claude"})
    assert pane_task_key(by_argv, "task") == "task-12"
    # --settings JSON (placeholder) ichidagi matnlar hisobga olinmaydi.
    assert pane_task_key(resumed, "task") is None


def test_pane_task_key_from_resumed_session_title() -> None:
    sessions = _sessions()
    pane = Pane.model_validate(
        {
            "id": "p1",
            "agent": "claude",
            "title": "leveling-backend",
            "argv": ["claude", "--settings", "{}", "--resume", sessions[0].session_id],
        }
    )
    titles = {s.session_id: s.title or "" for s in sessions}
    assert pane_task_key(pane, "task", titles) == "task-12"
    assert pane_task_key(pane, "task") is None
    assert pane_task_key(pane, "task", {}) is None


# --- loyihaga tegishlilik -------------------------------------------------------------------


@pytest.fixture
def tree(tmp_path: Path) -> dict[str, Path]:
    proj = tmp_path / "proj"
    proj2 = tmp_path / "proj2"
    api = tmp_path / "work" / "api"
    for directory in (proj / "src", proj2, api):
        directory.mkdir(parents=True)
    link = tmp_path / "link-to-proj"
    link.symlink_to(proj, target_is_directory=True)
    return {"root": tmp_path, "proj": proj, "proj2": proj2, "api": api, "link": link}


def _project(project_id: str, *dirs: Path) -> Project:
    return Project(id=project_id, name=project_id, backlog_dir=dirs[0], repos=dirs)


def test_is_within_uses_realpath(tree: dict[str, Path]) -> None:
    proj = tree["proj"]
    assert is_within(proj, proj)
    assert is_within(proj / "src", proj)
    assert is_within(tree["link"] / "src", proj)
    assert is_within(proj / "src", tree["link"])
    assert is_within(f"{proj}/src/../src", proj)
    assert not is_within(tree["proj2"], proj)  # umumiy prefiks, lekin boshqa papka
    assert not is_within(f"{proj}/../proj2", proj)
    assert not is_within("", proj)


def test_project_for_path(tree: dict[str, Path]) -> None:
    leveling = _project("leveling", tree["proj"], tree["api"])
    other = _project("other", tree["proj2"])
    nested = _project("nested", tree["proj"] / "src")
    projects = [leveling, other]
    assert project_for_path(tree["link"], projects) is leveling
    assert project_for_path(tree["api"], projects) is leveling
    assert project_for_path(tree["proj2"], projects) is other
    assert project_for_path(tree["root"], projects) is None
    assert project_for_path("", projects) is None
    # Ichma-ich papkalarda eng ichkisi tanlanadi.
    assert project_for_path(tree["proj"] / "src", [leveling, nested]) is nested
    assert project_for_path(tree["proj"] / "src", [nested, leveling]) is nested


def test_panes_for_project(tree: dict[str, Path]) -> None:
    leveling = _project("leveling", tree["proj"])
    other = _project("other", tree["proj2"])
    panes = [
        Pane(id="a", cwd=str(tree["link"])),
        Pane(id="b", cwd=str(tree["proj2"])),
        Pane(id="c", cwd=""),
    ]
    assert [p.id for p in panes_for_project(panes, leveling, [leveling, other])] == ["a"]
    assert [p.id for p in panes_for_project(panes, other, [leveling, other])] == ["b"]
