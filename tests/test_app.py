from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from agent_hub.__main__ import DEFAULT_PORT, HOST, resolve_port
from agent_hub.app import create_app


@pytest.fixture
def static_dir(tmp_path: Path) -> Path:
    (tmp_path / "index.html").write_text("<html>hub</html>")
    (tmp_path / "assets").mkdir()
    (tmp_path / "assets" / "app.js").write_text("console.log(1)")
    (tmp_path.parent / "secret.txt").write_text("secret")
    return tmp_path


def test_health() -> None:
    client = TestClient(create_app())
    assert client.get("/api/health").json()["ok"] is True


def test_unknown_api_is_json_404(static_dir: Path) -> None:
    client = TestClient(create_app(static_dir))
    resp = client.get("/api/nope")
    assert resp.status_code == 404
    assert resp.json()["code"] == "not_found"


def test_spa_fallback_serves_index(static_dir: Path) -> None:
    client = TestClient(create_app(static_dir))
    assert client.get("/").text == "<html>hub</html>"
    assert client.get("/projects/leveling").text == "<html>hub</html>"
    assert client.get("/assets/app.js").text == "console.log(1)"


def test_spa_does_not_escape_static_dir(static_dir: Path) -> None:
    client = TestClient(create_app(static_dir))
    resp = client.get("/..%2Fsecret.txt")
    assert "secret" not in resp.text


def test_ws_prefix_not_swallowed(static_dir: Path) -> None:
    client = TestClient(create_app(static_dir))
    assert client.get("/ws/anything").status_code == 404


def test_frontend_not_built(tmp_path: Path) -> None:
    client = TestClient(create_app(tmp_path / "missing"))
    resp = client.get("/")
    assert resp.status_code == 503
    assert resp.json()["code"] == "frontend_not_built"


def test_host_is_loopback_only() -> None:
    assert HOST == "127.0.0.1"


def test_resolve_port() -> None:
    assert resolve_port({}) == DEFAULT_PORT == 8700
    assert resolve_port({"AGENT_HUB_PORT": "8711"}) == 8711
    with pytest.raises(ValueError):
        resolve_port({"AGENT_HUB_PORT": "70000"})
