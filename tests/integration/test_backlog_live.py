"""Haqiqiy `backlog` CLI bilan BacklogClient (opt-in: `pytest -m integration`).

Hammasi vaqtinchalik papkada — boshqa loyihalarga tegilmaydi.
"""

from __future__ import annotations

import asyncio
import shutil
import subprocess
from pathlib import Path

import pytest

from agent_hub.backlog_client import (
    BacklogClient,
    BacklogCliError,
    BacklogNotFound,
    BacklogTaskNotFound,
)

pytestmark = pytest.mark.integration


@pytest.fixture
def project(tmp_path: Path) -> Path:
    if shutil.which("backlog") is None:
        pytest.skip("backlog topilmadi")
    root = tmp_path / "proj"
    root.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=root, check=True)
    subprocess.run(
        [
            "backlog",
            "init",
            "IT",
            "--defaults",
            "--integration-mode",
            "none",
            "--backlog-dir",
            ".backlog",
            "--task-prefix",
            "lev",
            "--zero-padded-ids",
            "3",
            "--check-branches",
            "false",
            "--include-remote",
            "false",
        ],
        cwd=root,
        check=True,
        capture_output=True,
    )
    return root


async def test_create_edit_list_view(project: Path) -> None:
    client = BacklogClient(project)
    assert client.task_prefix() == "lev"
    assert await client.statuses() == ["To Do", "In Progress", "Done"]
    assert await client.list_tasks() == []

    first = await client.create_task(
        "-Login sahifasi",
        description="--draft emas",
        labels=["ui", "bug"],
        acceptance_criteria=["Forma bor", "Xato ko'rsatiladi"],
    )
    second = await client.create_task("API", status="In Progress")
    assert (first, second) == ("LEV-001", "LEV-002")

    await client.set_status(first, "Done")
    await client.add_label(second, ["backend"])

    tasks = {task.id: task for task in await client.list_tasks()}
    assert tasks[first].title == "-Login sahifasi"
    assert tasks[first].status == "Done"
    assert tasks[first].labels == ("ui", "bug")
    assert tasks[first].assignees == ()
    assert tasks[first].acceptance_criteria_count == 2
    assert tasks[second].status == "In Progress"
    assert tasks[second].labels == ("backend",)

    detail = await client.view_task(first)
    assert detail.description == "--draft emas"
    assert [item.text for item in detail.acceptance_criteria] == ["Forma bor", "Xato ko'rsatiladi"]
    assert any((project / ".backlog" / "tasks").glob("lev-001 - *.md"))


async def test_cache_sees_external_cli_changes(project: Path) -> None:
    client = BacklogClient(project)
    assert await client.list_tasks() == []
    await asyncio.to_thread(
        subprocess.run,
        ["backlog", "task", "create", "--", "Tashqaridan"],
        cwd=project,
        check=True,
        capture_output=True,
    )
    assert [task.title for task in await client.list_tasks()] == ["Tashqaridan"]


async def test_errors(project: Path) -> None:
    client = BacklogClient(project)
    with pytest.raises(BacklogTaskNotFound):
        await client.view_task("LEV-099")
    with pytest.raises(BacklogTaskNotFound):
        await client.set_status("LEV-099", "Done")
    with pytest.raises(BacklogCliError) as invalid:
        await client.create_task("X", status="Blah")
    assert invalid.value.code == "backlog_cli_error"

    child = project / "sub"
    child.mkdir()
    with pytest.raises(BacklogNotFound):
        await BacklogClient(child).list_tasks()
