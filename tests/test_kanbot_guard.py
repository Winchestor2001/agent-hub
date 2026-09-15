from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType
from typing import Any, cast

import pytest
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route, WebSocketRoute
from starlette.testclient import TestClient
from starlette.websockets import WebSocket, WebSocketDisconnect

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "kanbot_guarded_server.py"
PORT = 8787


def _load_guard_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("kanbot_guarded_server", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


guard_mod = _load_guard_module()


async def _start(request: Request) -> JSONResponse:
    return JSONResponse({"started": True})


async def _ws(websocket: WebSocket) -> None:
    await websocket.accept()
    await websocket.send_text("hello")
    await websocket.close()


def _client(extra_origins: tuple[str, ...] = ()) -> TestClient:
    inner = Starlette(
        routes=[
            Route("/api/panes/start", _start, methods=["POST", "OPTIONS"]),
            WebSocketRoute("/ws/web", _ws),
        ]
    )
    app = guard_mod.HostOriginGuard(inner, PORT, extra_origins)
    return TestClient(cast(Any, app), base_url=f"http://127.0.0.1:{PORT}")


def test_request_without_origin_passes() -> None:
    resp = _client().post("/api/panes/start")
    assert resp.status_code == 200
    assert resp.json() == {"started": True}


@pytest.mark.parametrize(
    "origin",
    [f"http://127.0.0.1:{PORT}", f"http://localhost:{PORT}", f"http://LOCALHOST:{PORT}/"],
)
def test_own_origin_passes(origin: str) -> None:
    resp = _client().post("/api/panes/start", headers={"Origin": origin})
    assert resp.status_code == 200


@pytest.mark.parametrize(
    "origin",
    [
        "https://evil.example",
        "null",
        "http://127.0.0.1:8700",
        f"http://127.0.0.1:{PORT}.evil.example",
        f"https://127.0.0.1:{PORT}",
    ],
)
def test_foreign_origin_rejected(origin: str) -> None:
    resp = _client().post("/api/panes/start", headers={"Origin": origin})
    assert resp.status_code == 403
    preflight = _client().options("/api/panes/start", headers={"Origin": origin})
    assert preflight.status_code == 403


@pytest.mark.parametrize(
    "host", ["evil.example:8787", f"127.0.0.1:{PORT + 1}", "127.0.0.1", "192.168.1.5:8787"]
)
def test_foreign_host_rejected(host: str) -> None:
    resp = _client().post("/api/panes/start", headers={"Host": host})
    assert resp.status_code == 403


def test_extra_origin_allowed() -> None:
    client = _client(("http://127.0.0.1:9000/",))
    resp = client.post("/api/panes/start", headers={"Origin": "http://127.0.0.1:9000"})
    assert resp.status_code == 200


def test_websocket_without_origin_passes() -> None:
    with _client().websocket_connect("/ws/web", headers={"Host": f"127.0.0.1:{PORT}"}) as ws:
        assert ws.receive_text() == "hello"


def test_websocket_foreign_origin_rejected() -> None:
    with (
        pytest.raises(WebSocketDisconnect) as exc,
        _client().websocket_connect(
            "/ws/web", headers={"Host": f"127.0.0.1:{PORT}", "Origin": "https://evil.example"}
        ),
    ):
        pass
    assert exc.value.code == 1008


def test_websocket_foreign_host_rejected() -> None:
    with (
        pytest.raises(WebSocketDisconnect),
        _client().websocket_connect("/ws/web", headers={"Host": "evil.example:8787"}),
    ):
        pass


def test_parse_args_defaults() -> None:
    args = guard_mod.parse_args([])
    assert args.port == PORT
    assert args.log_level == "warning"
    assert args.allow_origin == []
