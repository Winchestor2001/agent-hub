from __future__ import annotations

import json
import logging
from collections.abc import AsyncIterator, Awaitable, Callable, Iterator
from pathlib import Path
from typing import Any

import httpx
import pytest
import respx

from agent_hub.kanbot_client import (
    HOOKS_PLACEHOLDER,
    RUNNER_CALL_TIMEOUT,
    KanbotClient,
    KanbotError,
    KanbotNoRunner,
    KanbotPaneNotFound,
    KanbotRunnerError,
    KanbotUnavailable,
    strip_settings_arg,
    validate_keys,
)

KANBOT = "http://kanbot.test"
FIXTURES = Path(__file__).parent / "fixtures" / "kanbot"


def fixture(name: str) -> Any:
    return json.loads((FIXTURES / name).read_text())


@pytest.fixture
async def client() -> AsyncIterator[KanbotClient]:
    kanbot = KanbotClient(KANBOT + "/")
    yield kanbot
    await kanbot.aclose()


@pytest.fixture
def mock() -> Iterator[respx.MockRouter]:
    with respx.mock(base_url=KANBOT, assert_all_called=False) as router:
        yield router


def pane_json(**overrides: Any) -> dict[str, Any]:
    pane: dict[str, Any] = fixture("panes.json")["panes"][0]
    pane.update(overrides)
    return pane


# --- muvaffaqiyatli chaqiruvlar -------------------------------------------------------------


async def test_list_panes(client: KanbotClient, mock: respx.MockRouter) -> None:
    mock.get("/api/panes").respond(json=fixture("panes.json"))
    panes = await client.list_panes()
    assert [p.id for p in panes] == ["a1b2c3d4", "e5f6a7b8"]
    blocked, done = panes
    assert (blocked.agent, blocked.state, blocked.state_source) == ("claude", "blocked", "hook")
    assert blocked.alive is True
    assert blocked.runner_id == "r1"
    assert blocked.title == "TASK-12 · Login sahifasi"
    assert not hasattr(blocked, "future_field")
    assert (done.exit_code, done.alive, done.session_id, done.card_id) == (0, False, "", "")
    assert done.argv == ["codex", "resume", "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b"]


async def test_pane_argv_hides_settings_json(client: KanbotClient, mock: respx.MockRouter) -> None:
    mock.get("/api/panes").respond(json=fixture("panes.json"))
    pane = (await client.list_panes())[0]
    assert pane.argv == ["claude", "--settings", HOOKS_PLACEHOLDER, "Работай только над TASK-12."]
    dumped = pane.model_dump_json()
    assert "_hook" not in dumped
    assert "/.local/share" not in dumped


@pytest.mark.parametrize(
    ("argv", "expected"),
    [
        (["claude", "--settings", "{}", "hi"], ["claude", "--settings", HOOKS_PLACEHOLDER, "hi"]),
        (["claude", "--settings={}", "hi"], ["claude", f"--settings={HOOKS_PLACEHOLDER}", "hi"]),
        (["claude", "--settings"], ["claude", "--settings"]),
        (["codex", "resume", "abc"], ["codex", "resume", "abc"]),
        ([], []),
    ],
)
def test_strip_settings_arg(argv: list[str], expected: list[str]) -> None:
    assert strip_settings_arg(argv) == expected


async def test_get_pane(client: KanbotClient, mock: respx.MockRouter) -> None:
    mock.get("/api/panes/a1b2c3d4").respond(json=pane_json(state="idle"))
    pane = await client.get_pane("a1b2c3d4")
    assert pane.state == "idle"


async def test_start_pane(client: KanbotClient, mock: respx.MockRouter) -> None:
    route = mock.post("/api/panes/start").respond(json=pane_json(state="unknown"))
    pane = await client.start_pane(
        "claude", prompt="Работай только над TASK-12.", cwd="/proj", title="TASK-12 · X"
    )
    assert pane.id == "a1b2c3d4"
    request = route.calls.last.request
    assert json.loads(request.content) == {
        "agent": "claude",
        "prompt": "Работай только над TASK-12.",
        "cwd": "/proj",
        "interactive": True,
        "resume": "",
        "title": "TASK-12 · X",
        "runner_id": "",
    }
    assert request.extensions["timeout"]["read"] == RUNNER_CALL_TIMEOUT.read


async def test_start_pane_resume(client: KanbotClient, mock: respx.MockRouter) -> None:
    route = mock.post("/api/panes/start").respond(json=pane_json(agent="codex"))
    await client.start_pane("codex", cwd="/proj", resume="sess-1", runner_id="r1")
    body = json.loads(route.calls.last.request.content)
    assert (body["resume"], body["runner_id"], body["prompt"]) == ("sess-1", "r1", "")


@pytest.mark.parametrize("agent", ["shell", "glm", "kimi", "gemini", ""])
async def test_start_pane_rejects_other_agents(
    client: KanbotClient, mock: respx.MockRouter, agent: str
) -> None:
    route = mock.post("/api/panes/start")
    with pytest.raises(ValueError, match="agent"):
        await client.start_pane(agent, cwd="/proj")  # type: ignore[arg-type]
    assert not route.called


async def test_start_pane_requires_cwd(client: KanbotClient, mock: respx.MockRouter) -> None:
    with pytest.raises(ValueError, match="cwd"):
        await client.start_pane("claude", cwd="")


async def test_read_pane(client: KanbotClient, mock: respx.MockRouter) -> None:
    route = mock.get("/api/panes/a1b2c3d4/read").respond(
        json={"text": "Do you want to proceed?\n❯ 1. Yes", "pane": pane_json()}
    )
    result = await client.read_pane("a1b2c3d4", lines=30)
    assert result.text.startswith("Do you want to proceed?")
    assert result.pane is not None and result.pane.state == "blocked"
    assert route.calls.last.request.url.params["lines"] == "30"


@pytest.mark.parametrize(("lines", "sent"), [(0, "1"), (-5, "1"), (10_000, "500")])
async def test_read_pane_clamps_lines(
    client: KanbotClient, mock: respx.MockRouter, lines: int, sent: str
) -> None:
    route = mock.get("/api/panes/a1b2c3d4/read").respond(json={"text": ""})
    result = await client.read_pane("a1b2c3d4", lines=lines)
    assert result.pane is None
    assert route.calls.last.request.url.params["lines"] == sent


async def test_send_text(client: KanbotClient, mock: respx.MockRouter) -> None:
    route = mock.post("/api/panes/a1b2c3d4/input").respond(json={"ok": True})
    await client.send_text("a1b2c3d4", "salom")
    await client.send_text("a1b2c3d4", "qism", enter=False)
    bodies = [json.loads(call.request.content) for call in route.calls]
    assert bodies == [{"text": "salom", "enter": True}, {"text": "qism", "enter": False}]


async def test_send_keys(client: KanbotClient, mock: respx.MockRouter) -> None:
    route = mock.post("/api/panes/a1b2c3d4/input").respond(json={"ok": True})
    await client.send_keys("a1b2c3d4", ["y", "Enter"])
    await client.send_keys("a1b2c3d4", ["Escape"])
    await client.send_keys("a1b2c3d4", ["C-c"])
    bodies = [json.loads(call.request.content) for call in route.calls]
    assert bodies == [{"keys": ["y", "Enter"]}, {"keys": ["Escape"]}, {"keys": ["C-c"]}]


@pytest.mark.parametrize("keys", [[], ["rm -rf /"], ["C-cc"], ["\x1b"], ["Enter", "F13"]])
def test_validate_keys_rejects(keys: list[str]) -> None:
    with pytest.raises(ValueError):
        validate_keys(keys)


async def test_kill_and_remove(client: KanbotClient, mock: respx.MockRouter) -> None:
    kill = mock.post("/api/panes/a1b2c3d4/kill").respond(json={"ok": True})
    remove = mock.delete("/api/panes/a1b2c3d4").respond(json={"ok": True})
    await client.kill_pane("a1b2c3d4")
    await client.remove_pane("a1b2c3d4")
    assert kill.call_count == 1
    assert remove.call_count == 1


@pytest.mark.parametrize("pane_id", ["../runners", "a/b", "", "x" * 65, "a b", "a?x=1"])
async def test_pane_id_validated(
    client: KanbotClient, mock: respx.MockRouter, pane_id: str
) -> None:
    with pytest.raises(ValueError, match="pane ID"):
        await client.get_pane(pane_id)
    with pytest.raises(ValueError, match="pane ID"):
        await client.kill_pane(pane_id)


async def test_list_agent_sessions(client: KanbotClient, mock: respx.MockRouter) -> None:
    mock.get("/api/agent-sessions").respond(json=fixture("agent_sessions.json"))
    sessions = await client.list_agent_sessions()
    claude, codex = sessions
    assert claude.agent == "claude"
    assert claude.session_id == "5f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b"
    assert claude.title is not None and claude.title.startswith("Работай только над TASK-12.")
    assert (claude.turns, claude.active, claude.runner_id) == (3, True, "r1")
    assert not hasattr(claude, "tail")
    assert (codex.title, codex.recap, codex.active) == (None, None, False)


async def test_health_and_runners(client: KanbotClient, mock: respx.MockRouter) -> None:
    mock.get("/api/health").respond(json={"ok": True, "version": "0.8.2", "runners": 1, "x": 1})
    mock.get("/api/runners").respond(
        json={"runners": [{"id": "r1", "status": "online", "auto_approve": 0, "extra": True}]}
    )
    health = await client.health()
    assert (health.version, health.version_supported) == ("0.8.2", True)
    [runner] = await client.runners()
    assert runner.online and runner.auto_approve is False


# --- xatolar --------------------------------------------------------------------------------

Call = Callable[[KanbotClient], Awaitable[object]]

CALLS: dict[str, tuple[str, str, Call]] = {
    "health": ("GET", "/api/health", lambda c: c.health()),
    "runners": ("GET", "/api/runners", lambda c: c.runners()),
    "list_panes": ("GET", "/api/panes", lambda c: c.list_panes()),
    "get_pane": ("GET", "/api/panes/p1", lambda c: c.get_pane("p1")),
    "start_pane": ("POST", "/api/panes/start", lambda c: c.start_pane("claude", cwd="/p")),
    "read_pane": ("GET", "/api/panes/p1/read", lambda c: c.read_pane("p1")),
    "send_text": ("POST", "/api/panes/p1/input", lambda c: c.send_text("p1", "x")),
    "send_keys": ("POST", "/api/panes/p1/input", lambda c: c.send_keys("p1", ["y"])),
    "kill_pane": ("POST", "/api/panes/p1/kill", lambda c: c.kill_pane("p1")),
    "remove_pane": ("DELETE", "/api/panes/p1", lambda c: c.remove_pane("p1")),
    "list_agent_sessions": ("GET", "/api/agent-sessions", lambda c: c.list_agent_sessions()),
}
CALL_NAMES = sorted(CALLS)


@pytest.mark.parametrize("name", CALL_NAMES)
@pytest.mark.parametrize(
    "exc",
    [httpx.ConnectError("refused"), httpx.ReadTimeout("slow"), httpx.RemoteProtocolError("x")],
)
async def test_transport_errors_are_unavailable(
    client: KanbotClient, mock: respx.MockRouter, name: str, exc: Exception
) -> None:
    method, path, call = CALLS[name]
    mock.route(method=method, path=path).mock(side_effect=exc)
    with pytest.raises(KanbotUnavailable) as info:
        await call(client)
    assert info.value.code == "kanbot_unavailable"


@pytest.mark.parametrize("name", CALL_NAMES)
@pytest.mark.parametrize(
    ("status", "error", "code"),
    [
        (409, KanbotNoRunner, "kanbot_no_runner"),
        (502, KanbotRunnerError, "kanbot_runner_error"),
        (404, KanbotPaneNotFound, "pane_not_found"),
        (500, KanbotError, "kanbot_error"),
        (422, KanbotError, "kanbot_error"),
    ],
)
async def test_http_errors_are_typed(
    client: KanbotClient,
    mock: respx.MockRouter,
    name: str,
    status: int,
    error: type[KanbotError],
    code: str,
) -> None:
    method, path, call = CALLS[name]
    mock.route(method=method, path=path).respond(status, json={"detail": "no online runner has x"})
    with pytest.raises(error) as info:
        await call(client)
    assert type(info.value) is error
    assert info.value.code == code
    assert info.value.status == status
    assert info.value.detail == "no online runner has x"


async def test_start_pane_409_and_502_detail(client: KanbotClient, mock: respx.MockRouter) -> None:
    mock.post("/api/panes/start").mock(
        side_effect=[
            httpx.Response(409, json={"detail": "no online runner has 'codex'"}),
            httpx.Response(502, json={"detail": "runner did not answer"}),
        ]
    )
    with pytest.raises(KanbotNoRunner, match="no online runner has 'codex'"):
        await client.start_pane("codex", cwd="/p")
    with pytest.raises(KanbotRunnerError, match="runner did not answer"):
        await client.start_pane("codex", cwd="/p")


async def test_non_json_error_body(client: KanbotClient, mock: respx.MockRouter) -> None:
    mock.get("/api/panes").respond(502, text="Bad Gateway")
    with pytest.raises(KanbotRunnerError) as info:
        await client.list_panes()
    assert info.value.detail == "Bad Gateway"


@pytest.mark.parametrize(
    ("path", "call", "body"),
    [
        ("/api/panes", lambda c: c.list_panes(), "not json"),
        ("/api/panes", lambda c: c.list_panes(), '{"items": []}'),
        ("/api/agent-sessions", lambda c: c.list_agent_sessions(), "[]"),
        ("/api/runners", lambda c: c.runners(), '{"runners": null}'),
    ],
)
async def test_bad_payload(
    client: KanbotClient, mock: respx.MockRouter, path: str, call: Call, body: str
) -> None:
    mock.get(path).respond(200, text=body)
    with pytest.raises(KanbotError):
        await call(client)


# --- versiya --------------------------------------------------------------------------------


async def test_unsupported_version_warns_once(
    client: KanbotClient, mock: respx.MockRouter, caplog: pytest.LogCaptureFixture
) -> None:
    mock.get("/api/health").respond(json={"ok": True, "version": "0.9.1", "runners": 0})
    with caplog.at_level(logging.WARNING, logger="agent_hub.kanbot_client"):
        for _ in range(3):
            health = await client.health()
    assert health.version_supported is False
    warnings = [r for r in caplog.records if "0.9.1" in r.getMessage()]
    assert len(warnings) == 1


async def test_supported_version_does_not_warn(
    client: KanbotClient, mock: respx.MockRouter, caplog: pytest.LogCaptureFixture
) -> None:
    mock.get("/api/health").respond(json={"ok": True, "version": "0.8.9"})
    with caplog.at_level(logging.WARNING, logger="agent_hub.kanbot_client"):
        await client.health()
    assert caplog.records == []
