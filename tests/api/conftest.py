"""API testlari uchun muhit: vaqtinchalik loyihalar, soxta Backlog CLI va respx'dagi KanBot."""

from __future__ import annotations

import json
from collections.abc import Iterator, Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx
import pytest
import respx
import yaml
from fastapi.testclient import TestClient

from agent_hub.app import create_app
from agent_hub.backlog_client import BacklogClient, CliResult
from agent_hub.kanbot_client import KanbotClient
from agent_hub.settings import Settings

KANBOT = "http://kanbot.test"
FIXTURES = Path(__file__).parents[1] / "fixtures"


def fixture_text(name: str) -> str:
    return (FIXTURES / name).read_text()


class FakeBacklogCli:
    """`backlog` argv'lariga fixture'lardan javob beradi va chaqiruvlarni yozib oladi."""

    def __init__(self) -> None:
        self.calls: list[list[str]] = []
        self.cwds: list[Path] = []
        # ("task", "edit") kabi kalit bo'yicha majburiy javob (xatolarni sinash uchun).
        self.overrides: dict[tuple[str, str] | str, CliResult] = {}
        self.task_overrides: dict[str, dict[str, Any]] = {}

    def commands(self, *prefix: str) -> list[list[str]]:
        return [call for call in self.calls if tuple(call[: len(prefix)]) == prefix]

    async def __call__(self, argv: Sequence[str], cwd: Path, time_limit: float) -> CliResult:
        args = list(argv[1:])
        self.calls.append(args)
        self.cwds.append(cwd)
        key = (args[0], args[1])
        if key in self.overrides or args[0] in self.overrides:
            return self.overrides.get(key) or self.overrides[args[0]]
        if args[0] == "init":
            (cwd / ".backlog").mkdir()
            (cwd / ".backlog" / "config.yml").write_text(f'project_name: "{args[1]}"\n')
            return CliResult(0, "Initialized\n", "")
        if key == ("task", "list"):
            data = json.loads(fixture_text("backlog/task_list.json"))
            for task in data["tasks"]:
                task.update(self.task_overrides.get(task["id"], {}))
            return CliResult(0, json.dumps(data), "")
        if key == ("task", "view"):
            return self._view(args[-1])
        if args[:3] == ["config", "get", "statuses"]:
            return CliResult(0, "To Do, In Progress, Done\n", "")
        if args[:3] == ["config", "get", "labels"]:
            return CliResult(0, "backend, admin, client, bug\n", "")
        if key == ("milestone", "list"):
            return CliResult(0, fixture_text("backlog/milestone_list.txt"), "")
        if key == ("task", "create"):
            return CliResult(0, fixture_text("backlog/task_create.txt"), "")
        if key == ("task", "edit"):
            return CliResult(0, f"Updated task {args[-1]}\n", "")
        if key == ("task", "archive"):
            return CliResult(0, f"Archived task {args[-1]}\n", "")
        if key == ("task", "complete"):
            return CliResult(0, f"Completed task {args[-1]}\n", "")
        raise AssertionError(f"kutilmagan backlog buyrug'i: {args}")

    def _view(self, task_id: str) -> CliResult:
        tasks = json.loads(fixture_text("backlog/task_list.json"))["tasks"]
        summary = next((t for t in tasks if t["id"] == task_id), None)
        if summary is None:
            return CliResult(1, "", fixture_text("backlog/task_not_found.stderr"))
        data = json.loads(fixture_text("backlog/task_view.json"))
        data["task"].update(summary)
        data["task"].update(self.task_overrides.get(task_id, {}))
        return CliResult(0, json.dumps(data), "")


@dataclass
class ApiEnv:
    client: TestClient
    backlog: FakeBacklogCli
    kanbot: respx.MockRouter
    backend: Path
    web: Path
    outside: Path
    panes: list[dict[str, Any]] = field(default_factory=list)
    sessions: list[dict[str, Any]] = field(default_factory=list)
    runners: list[dict[str, Any]] = field(default_factory=list)
    screens: dict[str, str] = field(default_factory=dict)
    started: list[dict[str, Any]] = field(default_factory=list)
    killed: list[str] = field(default_factory=list)
    # Pane'ga yuborilgan matn/tugmalar: {"pane": id, "text": ..., "enter": ...}.
    inputs: list[dict[str, Any]] = field(default_factory=list)
    removed: list[str] = field(default_factory=list)
    kanbot_down: bool = False

    def pane(self, **overrides: Any) -> dict[str, Any]:
        data: dict[str, Any] = {
            "id": f"p{len(self.panes) + 1}",
            "agent": "claude",
            "title": "",
            "cwd": str(self.backend),
            "argv": ["claude"],
            "state": "working",
            "state_source": "hook",
            "started_at": 1000.0 + len(self.panes),
            "last_output_at": None,
            "alive": True,
            "runner_id": "r1",
            "runner_name": "mac",
        }
        data.update(overrides)
        self.panes.append(data)
        return data

    def session(self, **overrides: Any) -> dict[str, Any]:
        data: dict[str, Any] = {
            "agent": "codex",
            "session_id": f"0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a{len(self.sessions):02d}",
            "cwd": str(self.backend),
            "name": "leveling-backend",
            "title": None,
            "turns": 2,
            "mtime": 5000.0 + len(self.sessions),
            "active": False,
            "runner_id": "r1",
        }
        data.update(overrides)
        self.sessions.append(data)
        return data


def runner(**overrides: Any) -> dict[str, Any]:
    data: dict[str, Any] = {
        "id": "r1",
        "name": "mac",
        "status": "online",
        "capabilities": ["claude", "codex"],
        "auto_approve": 0,
    }
    data.update(overrides)
    return data


def _install_kanbot_routes(env: ApiEnv) -> None:
    def guarded(payload: Any) -> httpx.Response:
        if env.kanbot_down:
            raise httpx.ConnectError("refused")
        return httpx.Response(200, json=payload)

    def start(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        response = guarded({"id": "new1", "state": "working", "alive": True, **body})
        env.started.append(body)
        return response

    def read(request: httpx.Request, pane_id: str) -> httpx.Response:
        return guarded({"text": env.screens.get(pane_id, "")})

    def kill(request: httpx.Request, pane_id: str) -> httpx.Response:
        if not any(p["id"] == pane_id for p in env.panes):
            return httpx.Response(404, json={"detail": "pane not found"})
        response = guarded({"ok": True})
        env.killed.append(pane_id)
        return response

    def pane_input(request: httpx.Request, pane_id: str) -> httpx.Response:
        response = guarded({"ok": True})
        env.inputs.append({"pane": pane_id, **json.loads(request.content)})
        return response

    def get_pane(request: httpx.Request, pane_id: str) -> httpx.Response:
        pane = next((p for p in env.panes if p["id"] == pane_id), None)
        if pane is None:
            return httpx.Response(404, json={"detail": "pane not found"})
        return guarded(pane)

    def remove(request: httpx.Request, pane_id: str) -> httpx.Response:
        response = guarded({"ok": True})
        env.panes = [p for p in env.panes if p["id"] != pane_id]
        env.removed.append(pane_id)
        return response

    router = env.kanbot
    router.get(path__regex=r"^/api/panes/(?P<pane_id>[^/]+)$").mock(side_effect=get_pane)
    router.delete(path__regex=r"^/api/panes/(?P<pane_id>[^/]+)$").mock(side_effect=remove)
    router.get("/api/panes").mock(side_effect=lambda _: guarded({"panes": env.panes}))
    router.get("/api/agent-sessions").mock(
        side_effect=lambda _: guarded({"sessions": env.sessions})
    )
    router.get("/api/runners").mock(side_effect=lambda _: guarded({"runners": env.runners}))
    router.post("/api/panes/start").mock(side_effect=start)
    router.get(path__regex=r"^/api/panes/(?P<pane_id>[^/]+)/read$").mock(side_effect=read)
    router.post(path__regex=r"^/api/panes/(?P<pane_id>[^/]+)/kill$").mock(side_effect=kill)
    router.post(path__regex=r"^/api/panes/(?P<pane_id>[^/]+)/input$").mock(side_effect=pane_input)


@pytest.fixture
def api(tmp_path: Path) -> Iterator[ApiEnv]:
    backend = tmp_path / "leveling-backend"
    web = tmp_path / "leveling-web"
    outside = tmp_path / "other"
    broken = tmp_path / "broken"
    for directory in (backend / ".backlog", backend / "sub", web, outside, broken):
        directory.mkdir(parents=True)
    (backend / ".backlog" / "config.yml").write_text('project_name: "Leveling"\n')

    config_dir = tmp_path / "config"
    config_dir.mkdir()
    projects = [
        {
            "id": "leveling",
            "name": "Leveling",
            "backlog_dir": str(backend),
            "repos": [str(backend), str(web)],
        },
        {"id": "broken", "name": "Broken", "backlog_dir": str(broken)},
    ]
    (config_dir / "projects.yaml").write_text(yaml.safe_dump({"projects": projects}))

    settings = Settings(
        config_dir=config_dir,
        kanbot_config=tmp_path / "kanbot.json",
        home=tmp_path,
        projects_root=tmp_path,
    )
    cli = FakeBacklogCli()
    app = create_app(
        settings,
        static_dir=tmp_path / "static",
        kanbot=KanbotClient(KANBOT),
        backlog_factory=lambda root: BacklogClient(root, runner=cli, lock_retry_delay=0),
    )
    with (
        respx.mock(base_url=KANBOT, assert_all_called=False) as router,
        TestClient(app) as client,
    ):
        env = ApiEnv(client, cli, router, backend, web, outside, runners=[runner()])
        _install_kanbot_routes(env)
        yield env


def assert_error(resp: httpx.Response, status: int, code: str) -> dict[str, Any]:
    assert resp.status_code == status, resp.text
    body: dict[str, Any] = resp.json()
    assert set(body) == {"code", "params", "detail"}
    assert body["code"] == code
    return body
