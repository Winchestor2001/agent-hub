from __future__ import annotations

import asyncio
import os
import stat
import time
from collections.abc import Callable, Sequence
from pathlib import Path

import pytest

from agent_hub.backlog_client import (
    BacklogClient,
    BacklogCliError,
    BacklogLocked,
    BacklogNotFound,
    BacklogTaskNotFound,
    CliResult,
    Milestone,
    compute_fingerprint,
    run_subprocess,
)

FIXTURES = Path(__file__).parent / "fixtures" / "backlog"


def fixture(name: str) -> str:
    return (FIXTURES / name).read_text()


def ok(stdout: str) -> CliResult:
    return CliResult(0, stdout, "")


def fail(stderr: str) -> CliResult:
    return CliResult(1, "", stderr)


Handler = Callable[[list[str]], CliResult]


class FakeRunner:
    """argv'ni yozib oladi va `backlog` dan keyingi argumentlar bo'yicha javob qaytaradi."""

    def __init__(self, handler: Handler, delay: float = 0.0) -> None:
        self.handler = handler
        self.delay = delay
        self.calls: list[list[str]] = []
        self.cwds: list[Path] = []
        self.active = 0
        self.max_active = 0

    async def __call__(self, argv: Sequence[str], cwd: Path, time_limit: float) -> CliResult:
        self.calls.append(list(argv[1:]))
        self.cwds.append(cwd)
        self.active += 1
        self.max_active = max(self.max_active, self.active)
        try:
            if self.delay:
                await asyncio.sleep(self.delay)
            return self.handler(list(argv[1:]))
        finally:
            self.active -= 1


def default_handler(args: list[str]) -> CliResult:
    match args:
        case ["task", "list", "--json"]:
            return ok(fixture("task_list.json"))
        case ["task", "view", "--json", "--", _]:
            return ok(fixture("task_view.json"))
        case ["config", "get", "statuses"]:
            return ok("To Do, In Progress, Done\n")
        case ["config", "get", "labels"]:
            return ok("ui, Bug, needs review\n")
        case ["milestone", "list", "--plain", "--show-completed"]:
            return ok(fixture("milestone_list.txt"))
        case ["task", "create", *_]:
            return ok(fixture("task_create.txt"))
        case ["task", "edit", *_]:
            return ok("Updated task TASK-2\n")
    raise AssertionError(f"kutilmagan buyruq: {args}")


@pytest.fixture
def project(tmp_path: Path) -> Path:
    root = tmp_path / "proj"
    tasks = root / ".backlog" / "tasks"
    tasks.mkdir(parents=True)
    (root / ".backlog" / "config.yml").write_text('project_name: "P"\ntask_prefix: "task"\n')
    (tasks / "task-1 - Login-sahifasi.md").write_text("one")
    (tasks / "task-2 - API.md").write_text("two")
    return root


def make_client(
    project: Path, handler: Handler = default_handler, delay: float = 0.0
) -> tuple[BacklogClient, FakeRunner]:
    runner = FakeRunner(handler, delay)
    return BacklogClient(project, runner=runner, lock_retry_delay=0), runner


def touch(path: Path, content: str | None = None) -> None:
    if content is not None:
        path.write_text(content)
    future = time.time() + 5
    os.utime(path, (future, future))


# --- parsing --------------------------------------------------------------------------------


async def test_list_tasks(project: Path) -> None:
    client, runner = make_client(project)
    tasks = await client.list_tasks()
    assert [t.id for t in tasks] == ["TASK-1", "TASK-1.1", "TASK-2"]
    first = tasks[0]
    assert first.title == "Login sahifasi"
    assert first.status == "To Do"
    assert first.type == "bug"
    assert first.labels == ("ui", "Bug")
    assert first.assignees == ("@alice",)
    assert first.milestone == "m-0"
    assert (first.acceptance_criteria_completed, first.acceptance_criteria_count) == (1, 2)
    assert tasks[1].parent_task_id == "TASK-1"
    assert tasks[2].is_ready is False
    assert runner.cwds == [project]


async def test_view_task(project: Path) -> None:
    client, runner = make_client(project)
    task = await client.view_task("TASK-1")
    assert runner.calls == [["task", "view", "--json", "--", "TASK-1"]]
    assert task.description == "Tavsif **md**"
    assert [(c.index, c.text, c.checked) for c in task.acceptance_criteria] == [
        (1, "Forma bor", True),
        (2, "Xato ko'rsatiladi", False),
    ]
    assert task.dod_progress == (1, 1)
    assert [s.id for s in task.subtasks] == ["TASK-1.1"]
    assert task.implementation_notes == "izoh"
    assert task.implementation_plan is None


async def test_statuses_labels_milestones(project: Path) -> None:
    client, _ = make_client(project)
    assert await client.statuses() == ["To Do", "In Progress", "Done"]
    assert await client.labels() == ["ui", "Bug", "needs review"]
    assert await client.milestones() == [
        Milestone("m-0", "Release 1", 0, 1, completed=False),
        Milestone("m-2", "v2: Yangi (beta)", 0, 0, completed=False),
        Milestone("m-1", "Release 2", 1, 1, completed=True),
    ]


async def test_empty_labels(project: Path) -> None:
    client, _ = make_client(project, lambda args: ok("\n"))
    assert await client.labels() == []


@pytest.mark.parametrize(
    ("config", "expected"),
    [('task_prefix: "lev"\n', "lev"), ("project_name: x\n", "task"), ("[broken", "task")],
)
def test_task_prefix(project: Path, config: str, expected: str) -> None:
    (project / ".backlog" / "config.yml").write_text(config)
    client, runner = make_client(project)
    assert client.task_prefix() == expected
    assert runner.calls == []


# --- mutatsiyalar ---------------------------------------------------------------------------


async def test_create_task(project: Path) -> None:
    client, runner = make_client(project)
    task_id = await client.create_task(
        "-yangi",
        description="--draft",
        status="In Progress",
        labels=["ui", "bug"],
        milestone="m-0",
        acceptance_criteria=["Forma bor", "-x"],
    )
    assert task_id == "TASK-4"
    assert runner.calls == [
        [
            "task",
            "create",
            "--description=--draft",
            "--status=In Progress",
            "--labels=ui,bug",
            "--assignee=",
            "--milestone=m-0",
            "--ac=Forma bor",
            "--ac=-x",
            "--",
            "-yangi",
        ]
    ]


async def test_create_task_minimal(project: Path) -> None:
    client, runner = make_client(project)
    await client.create_task("Oddiy", assignees=["@me"])
    assert runner.calls == [["task", "create", "--assignee=@me", "--", "Oddiy"]]


async def test_create_task_without_id_in_output(project: Path) -> None:
    client, _ = make_client(project, lambda args: ok("nimadir\n"))
    with pytest.raises(BacklogCliError) as exc:
        await client.create_task("X")
    assert exc.value.code == "backlog_bad_output"


async def test_set_status_and_add_label(project: Path) -> None:
    client, runner = make_client(project)
    await client.set_status("TASK-2", "Done")
    await client.add_label("TASK-2", ["needs review", "ui"])
    assert runner.calls == [
        ["task", "edit", "--status=Done", "--", "TASK-2"],
        ["task", "edit", "--add-label=needs review,ui", "--", "TASK-2"],
    ]


async def test_mutation_invalidates_cache(project: Path) -> None:
    client, runner = make_client(project)
    await client.list_tasks()
    await client.set_status("TASK-2", "Done")
    await client.list_tasks()
    assert [c[:2] for c in runner.calls] == [["task", "list"], ["task", "edit"], ["task", "list"]]


# --- xatolar --------------------------------------------------------------------------------


async def test_parent_directory_backlog_is_not_used(project: Path) -> None:
    child = project / "packages" / "api"
    child.mkdir(parents=True)
    client, runner = make_client(child)
    with pytest.raises(BacklogNotFound) as exc:
        await client.list_tasks()
    assert exc.value.code == "backlog_not_found"
    assert exc.value.params == {"path": str(child)}
    with pytest.raises(BacklogNotFound):
        client.task_prefix()
    assert runner.calls == []


async def test_cli_project_not_found(project: Path) -> None:
    client, _ = make_client(project, lambda args: fail(fixture("project_not_found.stderr")))
    with pytest.raises(BacklogNotFound):
        await client.statuses()


async def test_task_not_found(project: Path) -> None:
    client, _ = make_client(project, lambda args: fail(fixture("task_not_found.stderr")))
    with pytest.raises(BacklogTaskNotFound) as exc:
        await client.view_task("task-99")
    assert exc.value.code == "task_not_found"


async def test_lock_retried_once_then_succeeds(project: Path) -> None:
    results = [fail(fixture("locked.stderr")), ok("Updated task TASK-1\n")]
    client, runner = make_client(project, lambda args: results.pop(0))
    await client.set_status("TASK-1", "Done")
    assert len(runner.calls) == 2


async def test_lock_retried_once_then_raises(project: Path) -> None:
    client, runner = make_client(project, lambda args: fail(fixture("locked.stderr")))
    with pytest.raises(BacklogLocked) as exc:
        await client.add_label("TASK-1", ["x"])
    assert exc.value.code == "backlog_locked"
    assert len(runner.calls) == 2


async def test_generic_cli_error(project: Path) -> None:
    client, runner = make_client(project, lambda args: fail(fixture("invalid_status.stderr")))
    with pytest.raises(BacklogCliError) as exc:
        await client.set_status("TASK-2", "Blah")
    assert exc.value.code == "backlog_cli_error"
    assert "Invalid status: Blah" in exc.value.params["detail"]
    assert len(runner.calls) == 1


def _init_handler(root: Path, create: bool = True) -> Handler:
    def handler(args: list[str]) -> CliResult:
        assert args[0] == "init"
        if create:
            (root / ".backlog").mkdir()
            (root / ".backlog" / "config.yml").write_text('project_name: "New"\n')
        return ok("Initialized\n")

    return handler


@pytest.mark.parametrize(("git", "tail"), [(True, []), (False, ["--no-git"])])
async def test_init(tmp_path: Path, git: bool, tail: list[str]) -> None:
    client, runner = make_client(tmp_path, _init_handler(tmp_path))
    await client.init("New app", git=git)
    base = ["init", "New app", "--defaults", "--backlog-dir", ".backlog", "--integration-mode"]
    assert runner.calls == [[*base, "none", *tail]]
    assert runner.cwds == [tmp_path]


async def test_init_rejects_existing_backlog(project: Path) -> None:
    client, runner = make_client(project, _init_handler(project))
    with pytest.raises(BacklogCliError) as exc:
        await client.init("P", git=True)
    assert exc.value.code == "backlog_exists"
    assert runner.calls == []


async def test_init_without_config_fails(tmp_path: Path) -> None:
    client, _ = make_client(tmp_path, _init_handler(tmp_path, create=False))
    with pytest.raises(BacklogCliError) as exc:
        await client.init("New", git=False)
    assert exc.value.code == "backlog_init_failed"
    client, _ = make_client(tmp_path, lambda args: fail("boom"))
    with pytest.raises(BacklogCliError) as exc:
        await client.init("New", git=False)
    assert exc.value.code == "backlog_init_failed"
    assert exc.value.params["detail"] == "boom"


@pytest.mark.parametrize(
    "stdout", ["not json", '{"kind": "other"}', '{"kind": "task-list", "tasks": [{}]}']
)
async def test_bad_json_output(project: Path, stdout: str) -> None:
    client, _ = make_client(project, lambda args: ok(stdout))
    with pytest.raises(BacklogCliError) as exc:
        await client.list_tasks()
    assert exc.value.code == "backlog_bad_output"


# --- kesh -----------------------------------------------------------------------------------


async def test_cache_skips_subprocess_when_files_unchanged(project: Path) -> None:
    client, runner = make_client(project)
    for _ in range(3):
        await client.list_tasks()
        await client.statuses()
        await client.labels()
        await client.milestones()
    assert len(runner.calls) == 4


@pytest.mark.parametrize(
    "change",
    [
        lambda root: touch(root / ".backlog" / "tasks" / "task-1 - Login-sahifasi.md", "edited"),
        lambda root: (root / ".backlog" / "tasks" / "task-3 - New.md").write_text("new"),
        lambda root: (root / ".backlog" / "tasks" / "task-2 - API.md").unlink(),
        lambda root: touch(root / ".backlog" / "config.yml", 'statuses: ["A"]\n'),
        lambda root: (root / ".backlog" / "milestones").mkdir(),
    ],
)
async def test_cache_refreshes_on_file_change(
    project: Path, change: Callable[[Path], object]
) -> None:
    client, runner = make_client(project)
    await client.list_tasks()
    change(project)
    await client.list_tasks()
    assert len(runner.calls) == 2


async def test_view_cache_is_per_task_file(project: Path) -> None:
    client, runner = make_client(project)
    await client.view_task("TASK-1")
    await client.view_task("task-2")
    await client.view_task("TASK-1")
    assert len(runner.calls) == 2
    touch(project / ".backlog" / "tasks" / "task-1 - Login-sahifasi.md", "edited")
    await client.view_task("TASK-1")
    await client.view_task("TASK-2")
    assert len(runner.calls) == 3


async def test_single_flight(project: Path) -> None:
    client, runner = make_client(project, delay=0.05)
    results = await asyncio.gather(*(client.list_tasks() for _ in range(5)))
    assert len(runner.calls) == 1
    assert all(r == results[0] for r in results)


async def test_single_flight_error_shared_and_not_cached(project: Path) -> None:
    responses = [fail("boom"), ok(fixture("task_list.json"))]
    client, runner = make_client(project, lambda args: responses.pop(0), delay=0.05)
    outcomes = await asyncio.gather(
        *(client.list_tasks() for _ in range(3)), return_exceptions=True
    )
    assert all(isinstance(o, BacklogCliError) for o in outcomes)
    assert len(await client.list_tasks()) == 3
    assert len(runner.calls) == 2


async def test_dod_progress_limits_concurrency(project: Path) -> None:
    tasks_dir = project / ".backlog" / "tasks"
    ids = [f"TASK-{n}" for n in range(1, 11)]
    for n in range(3, 11):
        (tasks_dir / f"task-{n} - T.md").write_text(str(n))
    client, runner = make_client(project, delay=0.02)
    progress = await client.dod_progress(ids)
    assert progress == dict.fromkeys(ids, (1, 1))
    assert len(runner.calls) == 10
    assert runner.max_active == 4
    await client.dod_progress(ids)
    assert len(runner.calls) == 10


def test_fingerprint_ignores_locks_dir(project: Path) -> None:
    before = compute_fingerprint(project)
    (project / ".backlog" / ".locks").mkdir()
    (project / ".backlog" / ".locks" / "task-1.lock").write_text("")
    after = compute_fingerprint(project)
    assert before.digest == after.digest
    assert set(after.task_files) == {"task-1", "task-2"}


# --- haqiqiy subprocess ---------------------------------------------------------------------


def _script(path: Path, body: str) -> Path:
    path.write_text(f"#!/bin/sh\n{body}\n")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


async def test_run_subprocess_environment(project: Path, tmp_path: Path) -> None:
    script = _script(
        tmp_path / "fake-backlog",
        'echo "$NO_COLOR|$BACKLOG_CWD|$(pwd -P)|$*"; cat; echo err >&2',
    )
    result = await run_subprocess([str(script), "task", "list"], project, 5)
    assert result.returncode == 0
    real = await asyncio.to_thread(project.resolve)
    assert result.stdout.strip() == f"1|{project}|{real}|task list"
    assert result.stderr == "err\n"


async def test_run_subprocess_timeout(project: Path, tmp_path: Path) -> None:
    script = _script(tmp_path / "slow-backlog", "exec sleep 10")
    started = time.monotonic()
    with pytest.raises(BacklogCliError) as exc:
        await run_subprocess([str(script), "task", "list"], project, 0.2)
    assert exc.value.code == "backlog_timeout"
    assert time.monotonic() - started < 3


async def test_missing_executable(project: Path, tmp_path: Path) -> None:
    client = BacklogClient(project, executable=str(tmp_path / "nope"))
    with pytest.raises(BacklogCliError) as exc:
        await client.statuses()
    assert exc.value.code == "backlog_cli_missing"
