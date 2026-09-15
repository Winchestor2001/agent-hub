from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from agent_hub.app import create_app
from agent_hub.kanbot_client import KanbotClient

KANBOT = "http://kanbot.test"
SAFE_CONFIG = {"disabled_agents": ["shell", "glm", "kimi"], "auto_approve": False}


def _runner(**overrides: Any) -> dict[str, Any]:
    runner: dict[str, Any] = {
        "id": "r1",
        "name": "mac",
        "host": "mac.local",
        "capabilities": ["claude", "codex"],
        "status": "online",
        "auto_approve": 0,
        "last_seen": 1.0,
    }
    runner.update(overrides)
    return runner


@pytest.fixture
def config_path(tmp_path: Path) -> Path:
    path = tmp_path / "config.json"
    path.write_text(json.dumps(SAFE_CONFIG))
    return path


def _health(config_path: Path) -> dict[str, Any]:
    app = create_app(kanbot=KanbotClient(KANBOT), kanbot_config=config_path)
    with TestClient(app) as client:
        resp = client.get("/api/health")
    assert resp.status_code == 200
    data: dict[str, Any] = resp.json()
    return data


def _mock_kanbot(mock: respx.Router, runners: list[dict[str, Any]]) -> None:
    mock.get("/api/health").respond(json={"ok": True, "version": "0.8.2", "runners": 1})
    mock.get("/api/runners").respond(json={"runners": runners})


def _codes(data: dict[str, Any]) -> list[str]:
    return [p["code"] for p in data["problems"]]


@respx.mock(base_url=KANBOT)
def test_health_ok(respx_mock: respx.Router, config_path: Path) -> None:
    _mock_kanbot(respx_mock, [_runner()])
    data = _health(config_path)
    assert data["ok"] is True
    assert data["problems"] == []
    assert data["kanbot"]["reachable"] is True
    assert data["kanbot"]["version"] == "0.8.2"
    assert data["kanbot"]["runners_online"] == 1
    assert data["kanbot"]["agents"] == ["claude", "codex"]


@respx.mock(base_url=KANBOT)
def test_shell_enabled_on_runner(respx_mock: respx.Router, config_path: Path) -> None:
    _mock_kanbot(respx_mock, [_runner(capabilities=["claude", "shell", "glm"])])
    data = _health(config_path)
    assert data["ok"] is False
    assert _codes(data) == ["shell_enabled", "agent_enabled"]
    assert data["problems"][0]["params"] == {"agent": "shell", "source": "runner", "runner": "mac"}


@respx.mock(base_url=KANBOT)
def test_shell_enabled_in_config(respx_mock: respx.Router, config_path: Path) -> None:
    _mock_kanbot(respx_mock, [_runner()])
    config_path.write_text(json.dumps({"disabled_agents": ["glm", "kimi"]}))
    data = _health(config_path)
    assert data["ok"] is False
    params = {"agent": "shell", "source": "config"}
    assert data["problems"] == [{"code": "shell_enabled", "severity": "error", "params": params}]


@respx.mock(base_url=KANBOT)
def test_auto_approve_detected(respx_mock: respx.Router, config_path: Path) -> None:
    _mock_kanbot(respx_mock, [_runner(auto_approve=1)])
    config_path.write_text(json.dumps({**SAFE_CONFIG, "auto_approve": True}))
    data = _health(config_path)
    assert data["ok"] is False
    assert _codes(data) == ["auto_approve_enabled", "auto_approve_enabled"]


@respx.mock(base_url=KANBOT)
def test_offline_runner_ignored_and_no_runner_is_warning(
    respx_mock: respx.Router, config_path: Path
) -> None:
    _mock_kanbot(respx_mock, [_runner(status="offline", capabilities=["shell"])])
    data = _health(config_path)
    assert data["ok"] is True
    assert data["problems"] == [{"code": "no_runner", "severity": "warning", "params": {}}]


@respx.mock(base_url=KANBOT)
def test_multiple_runners_warning(respx_mock: respx.Router, config_path: Path) -> None:
    _mock_kanbot(respx_mock, [_runner(), _runner(id="r2", name="mac2", status="busy")])
    data = _health(config_path)
    assert data["ok"] is True
    assert _codes(data) == ["multiple_runners"]


@respx.mock(base_url=KANBOT)
def test_kanbot_unavailable(respx_mock: respx.Router, config_path: Path) -> None:
    respx_mock.get("/api/health").mock(side_effect=httpx.ConnectError("refused"))
    data = _health(config_path)
    assert data["ok"] is False
    assert data["kanbot"]["reachable"] is False
    assert _codes(data) == ["kanbot_unavailable"]


@respx.mock(base_url=KANBOT)
def test_kanbot_http_error(respx_mock: respx.Router, config_path: Path) -> None:
    respx_mock.get("/api/health").respond(500)
    data = _health(config_path)
    assert _codes(data) == ["kanbot_unavailable"]


@respx.mock(base_url=KANBOT)
def test_config_missing_is_warning(respx_mock: respx.Router, tmp_path: Path) -> None:
    _mock_kanbot(respx_mock, [_runner()])
    data = _health(tmp_path / "absent.json")
    assert data["ok"] is True
    assert _codes(data) == ["kanbot_config_missing"]


@respx.mock(base_url=KANBOT)
def test_config_unreadable_is_error(respx_mock: respx.Router, config_path: Path) -> None:
    _mock_kanbot(respx_mock, [_runner()])
    config_path.write_text("{not json")
    data = _health(config_path)
    assert data["ok"] is False
    assert _codes(data) == ["kanbot_config_unreadable"]
