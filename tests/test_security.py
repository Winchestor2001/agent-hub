from __future__ import annotations

import pytest
from fastapi import FastAPI, WebSocket
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from agent_hub.app import create_asgi_app
from agent_hub.security import HostOriginGuard
from agent_hub.settings import Settings

PORT = 8700
BASE = f"http://127.0.0.1:{PORT}"


def _client(extra_origins: tuple[str, ...] = ()) -> TestClient:
    inner = FastAPI()

    @inner.post("/api/x")
    async def post_x() -> dict[str, bool]:
        return {"ok": True}

    @inner.websocket("/ws/panes/p1")
    async def ws(websocket: WebSocket) -> None:
        await websocket.accept()
        await websocket.send_text("hello")
        await websocket.close()

    return TestClient(HostOriginGuard(inner, PORT, extra_origins), base_url=BASE)


def test_no_origin_passes() -> None:
    assert _client().post("/api/x").json() == {"ok": True}


@pytest.mark.parametrize("origin", [BASE, f"http://localhost:{PORT}", f"http://[::1]:{PORT}/"])
def test_own_origin_passes(origin: str) -> None:
    assert _client().post("/api/x", headers={"Origin": origin}).status_code == 200


@pytest.mark.parametrize(
    "origin",
    [
        "https://evil.example",
        "null",
        "http://127.0.0.1:8787",
        "http://127.0.0.1:5173",
        f"http://127.0.0.1:{PORT}.evil.example",
        f"https://127.0.0.1:{PORT}",
    ],
)
def test_foreign_origin_rejected(origin: str) -> None:
    resp = _client().post("/api/x", headers={"Origin": origin})
    assert resp.status_code == 403
    assert resp.json() == {"code": "forbidden_origin", "params": {"origin": origin}}
    assert _client().options("/api/x", headers={"Origin": origin}).status_code == 403


@pytest.mark.parametrize(
    "host", ["evil.example:8700", "127.0.0.1:8701", "127.0.0.1", "192.168.1.5:8700"]
)
def test_foreign_host_rejected(host: str) -> None:
    resp = _client().post("/api/x", headers={"Host": host})
    assert resp.status_code == 403
    assert resp.json()["code"] == "forbidden_host"


def test_extra_origin_allowed() -> None:
    client = _client(("http://127.0.0.1:5173/",))
    assert client.post("/api/x", headers={"Origin": "http://127.0.0.1:5173"}).status_code == 200


def test_websocket_own_origin_passes() -> None:
    headers = {"Host": f"127.0.0.1:{PORT}", "Origin": BASE}
    with _client().websocket_connect("/ws/panes/p1", headers=headers) as ws:
        assert ws.receive_text() == "hello"


def test_websocket_foreign_origin_rejected() -> None:
    headers = {"Host": f"127.0.0.1:{PORT}", "Origin": "https://evil.example"}
    with (
        pytest.raises(WebSocketDisconnect) as exc,
        _client().websocket_connect("/ws/panes/p1", headers=headers),
    ):
        pass
    assert exc.value.code == 1008


def test_websocket_foreign_host_rejected() -> None:
    with (
        pytest.raises(WebSocketDisconnect),
        _client().websocket_connect("/ws/panes/p1", headers={"Host": "evil.example:8700"}),
    ):
        pass


def test_asgi_app_is_guarded_and_creates_registry(settings: Settings) -> None:
    app = create_asgi_app(settings)
    with TestClient(app, base_url=f"http://127.0.0.1:{settings.port}") as client:
        assert settings.projects_file.is_file()
        resp = client.get("/api/nope", headers={"Origin": "https://evil.example"})
        assert resp.status_code == 403
        assert client.get("/api/nope").status_code == 404
