"""Terminal WS proxy: PaneBridge oqimlari va soxta KanBot `/ws/web` bilan end-to-end."""

from __future__ import annotations

import asyncio
import base64
import json
import socket
import threading
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect
from websockets.sync.server import ServerConnection, serve

from agent_hub.api.terminal import (
    CLIENT_LEFT,
    KANBOT_UNAVAILABLE,
    PANE_GONE,
    SLOW_CLIENT,
    ChannelClosed,
    PaneBridge,
)
from agent_hub.app import create_app
from agent_hub.kanbot_client import KanbotClient
from agent_hub.settings import Settings


class FakeChannel:
    """Xotiradagi kanal. `stalled` — send hech qachon tugamaydi (brauzer o'qimayapti)."""

    def __init__(self, *, stalled: bool = False) -> None:
        self.inbox: asyncio.Queue[str | None] = asyncio.Queue()
        self.sent: list[str] = []
        self.received = 0
        self.stalled = stalled

    def push(self, *messages: dict[str, Any] | None) -> None:
        for message in messages:
            self.inbox.put_nowait(None if message is None else json.dumps(message))

    async def recv(self) -> str | None:
        item = await self.inbox.get()
        self.received += 1
        return item

    async def send(self, text: str) -> None:
        if self.stalled:
            await asyncio.Event().wait()
        self.sent.append(text)

    async def close(self, code: int, reason: str) -> None:
        raise AssertionError("PaneBridge kanallarni o'zi yopmasligi kerak")

    def sent_json(self) -> list[dict[str, Any]]:
        return [json.loads(text) for text in self.sent]


def pane_data(pane_id: str, payload: bytes, *, replay: bool = False) -> dict[str, Any]:
    data = base64.b64encode(payload).decode()
    return {"type": "pane.data", "pane_id": pane_id, "data": data, "replay": replay}


async def eventually(condition: Callable[[], bool]) -> None:
    async with asyncio.timeout(1):
        while not condition():  # noqa: ASYNC110 — fake kanal holatini kuzatish
            await asyncio.sleep(0.005)


# --- PaneBridge ----------------------------------------------------------------------------


async def test_stalled_client_does_not_block_upstream() -> None:
    upstream, client = FakeChannel(), FakeChannel(stalled=True)
    chunk = pane_data("p1", b"x" * 48_000)  # ~64 KB xabar; 20 tasi limitdan kam
    upstream.push(*[chunk] * 20, None)

    async with asyncio.timeout(1):
        close = await PaneBridge("p1").run(upstream, client, 40, 120)

    # Mijoz birorta xabarni ham olmadi, lekin upstream oxirigacha o'qildi.
    assert close == KANBOT_UNAVAILABLE
    assert upstream.received == 21
    assert client.sent == []


async def test_stalled_client_is_dropped_when_queue_overflows() -> None:
    upstream, client = FakeChannel(), FakeChannel(stalled=True)
    chunk = pane_data("p1", b"x" * 48_000)
    upstream.push(*[chunk] * 1000)

    async with asyncio.timeout(1):
        close = await PaneBridge("p1", queue_limit=2 * 1024 * 1024).run(upstream, client, 40, 120)

    assert close == SLOW_CLIENT
    message_size = len(PaneBridge("p1").from_upstream(json.dumps(chunk))[0] or "")
    fits = 2 * 1024 * 1024 // message_size
    # Navbatga sig'gan + (ehtimol) mijozga yuborilayotgan bitta + limitdan oshirgan bitta.
    assert fits + 1 <= upstream.received <= fits + 2


async def test_only_this_pane_output_reaches_client() -> None:
    upstream, client = FakeChannel(), FakeChannel()
    upstream.push(
        {"type": "hello", "version": "0.8.2"},
        {"type": "panes.updated"},
        {"type": "agent.blocked", "pane": {"id": "p1"}},
        pane_data("p2", b"begona"),
        pane_data("p1", b"scrollback", replay=True),
        pane_data("p1", b"yangi"),
        {"type": "pane.gone", "pane_id": "p2"},
    )

    task = asyncio.create_task(PaneBridge("p1").run(upstream, client, 40, 120))
    await eventually(lambda: len(client.sent) == 2)
    client.push(None)
    assert await task == CLIENT_LEFT

    assert client.sent_json() == [
        {"type": "data", "data": base64.b64encode(b"scrollback").decode(), "replay": True},
        {"type": "data", "data": base64.b64encode(b"yangi").decode(), "replay": False},
    ]
    assert upstream.sent[0] == json.dumps(
        {"type": "pane.attach", "pane_id": "p1", "rows": 40, "cols": 120}
    )


async def test_pane_gone_closes_bridge() -> None:
    upstream, client = FakeChannel(), FakeChannel()
    upstream.push({"type": "pane.gone", "pane_id": "p1"})
    assert await PaneBridge("p1").run(upstream, client, None, None) == PANE_GONE
    assert json.loads(upstream.sent[0])["rows"] == 0


async def test_upstream_send_failure_means_kanbot_unavailable() -> None:
    class Broken(FakeChannel):
        async def send(self, text: str) -> None:
            raise ChannelClosed

    assert await PaneBridge("p1").run(Broken(), FakeChannel(), 1, 1) == KANBOT_UNAVAILABLE


@pytest.mark.parametrize(
    ("message", "upstream"),
    [
        (
            {"type": "input", "data": "ls ё\r"},
            {"type": "pane.input", "data": base64.b64encode("ls ё\r".encode()).decode()},
        ),
        (
            {"type": "keys", "keys": ["y", "Enter"], "pane_id": "p9"},
            {"type": "pane.input", "keys": ["y", "Enter"]},
        ),
        ({"type": "keys", "keys": ["C-c"]}, {"type": "pane.input", "keys": ["C-c"]}),
        (
            {"type": "resize", "rows": 1, "cols": 99999},
            {"type": "pane.resize", "rows": 2, "cols": 1000},
        ),
    ],
)
def test_client_messages_are_translated_for_this_pane(
    message: dict[str, Any], upstream: dict[str, Any]
) -> None:
    out, error = PaneBridge("p1").from_client(json.dumps(message))
    assert error is None
    assert out is not None
    assert json.loads(out) == {**upstream, "pane_id": "p1"}


@pytest.mark.parametrize(
    ("raw", "code"),
    [
        ("not json", "bad_message"),
        ("[]", "bad_message"),
        (json.dumps({"type": "pane.kill"}), "bad_message"),
        (json.dumps({"type": "input", "data": ""}), "bad_message"),
        (json.dumps({"type": "input", "data": "x" * 70_000}), "bad_message"),
        (json.dumps({"type": "resize", "rows": "40", "cols": 80}), "bad_message"),
        (json.dumps({"type": "resize", "rows": True, "cols": 80}), "bad_message"),
        (json.dumps({"type": "keys", "keys": ["rm -rf /"]}), "invalid_keys"),
        (json.dumps({"type": "keys", "keys": []}), "invalid_keys"),
        (json.dumps({"type": "keys", "keys": "y"}), "invalid_keys"),
    ],
)
def test_bad_client_messages_are_rejected(raw: str, code: str) -> None:
    out, error = PaneBridge("p1").from_client(raw)
    assert out is None
    assert error is not None
    assert json.loads(error) == {"type": "error", "code": code}


async def test_bad_client_message_does_not_close_bridge() -> None:
    upstream, client = FakeChannel(), FakeChannel()
    task = asyncio.create_task(PaneBridge("p1").run(upstream, client, 40, 120))
    client.push({"type": "keys", "keys": ["nope!"]}, {"type": "keys", "keys": ["n"]})
    await eventually(lambda: len(upstream.sent) == 2 and len(client.sent) == 1)
    upstream.push(None)
    assert await task == KANBOT_UNAVAILABLE
    assert client.sent_json() == [{"type": "error", "code": "invalid_keys"}]
    assert json.loads(upstream.sent[1])["keys"] == ["n"]


# --- /ws/panes/{id} end-to-end ------------------------------------------------------------


@dataclass
class FakeKanbotWs:
    """KanBot `/ws/web` taqlidi: attach'ga replay beradi, C-c'ga javob chiqaradi."""

    url: str
    received: list[dict[str, Any]] = field(default_factory=list)
    closed: threading.Event = field(default_factory=threading.Event)

    def handle(self, ws: ServerConnection) -> None:
        try:
            ws.send(json.dumps({"type": "hello", "version": "0.8.2"}))
            for raw in ws:
                msg = json.loads(raw)
                self.received.append(msg)
                pane_id = msg.get("pane_id", "")
                if msg["type"] == "pane.attach":
                    if pane_id == "missing":
                        ws.send(json.dumps({"type": "pane.gone", "pane_id": pane_id}))
                        continue
                    ws.send(json.dumps({"type": "panes.updated"}))
                    ws.send(json.dumps(pane_data("other", b"begona")))
                    ws.send(json.dumps(pane_data(pane_id, b"hello", replay=True)))
                elif msg.get("keys") == ["C-c"]:
                    ws.send(json.dumps(pane_data(pane_id, b"^C")))
        finally:
            self.closed.set()


@pytest.fixture
def kanbot_ws() -> Iterator[FakeKanbotWs]:
    fake = FakeKanbotWs(url="")
    with serve(fake.handle, "127.0.0.1", 0) as server:
        port = server.socket.getsockname()[1]
        fake.url = f"http://127.0.0.1:{port}"
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        yield fake
    thread.join(timeout=5)


def _hub_client(tmp_path: Path, kanbot_url: str) -> TestClient:
    settings = Settings(config_dir=tmp_path, kanbot_config=tmp_path / "kanbot.json")
    app = create_app(settings, static_dir=tmp_path / "static", kanbot=KanbotClient(kanbot_url))
    return TestClient(app)


def test_terminal_proxy_end_to_end(tmp_path: Path, kanbot_ws: FakeKanbotWs) -> None:
    client = _hub_client(tmp_path, kanbot_ws.url)
    with client.websocket_connect("/ws/panes/p1?rows=30&cols=100") as ws:
        assert ws.receive_json() == {
            "type": "data",
            "data": base64.b64encode(b"hello").decode(),
            "replay": True,
        }
        ws.send_json({"type": "keys", "keys": ["C-c"]})
        assert ws.receive_json()["data"] == base64.b64encode(b"^C").decode()
        ws.send_json({"type": "keys", "keys": ["Enter; rm"]})
        assert ws.receive_json() == {"type": "error", "code": "invalid_keys"}
        ws.send_json({"type": "input", "data": "ls\r"})
        ws.send_json({"type": "resize", "rows": 50, "cols": 160})

    # Mijoz ketdi → upstream ham yopiladi (KanBot obunani bo'shatadi).
    assert kanbot_ws.closed.wait(timeout=5)
    assert kanbot_ws.received == [
        {"type": "pane.attach", "pane_id": "p1", "rows": 30, "cols": 100},
        {"type": "pane.input", "keys": ["C-c"], "pane_id": "p1"},
        {"type": "pane.input", "data": base64.b64encode(b"ls\r").decode(), "pane_id": "p1"},
        {"type": "pane.resize", "rows": 50, "cols": 160, "pane_id": "p1"},
    ]


def test_terminal_missing_pane_closes_with_pane_gone(
    tmp_path: Path, kanbot_ws: FakeKanbotWs
) -> None:
    client = _hub_client(tmp_path, kanbot_ws.url)
    with (
        pytest.raises(WebSocketDisconnect) as exc,
        client.websocket_connect("/ws/panes/missing") as ws,
    ):
        ws.receive_json()
    assert (exc.value.code, exc.value.reason) == (4404, "pane_gone")
    assert kanbot_ws.closed.wait(timeout=5)


def test_terminal_kanbot_down(tmp_path: Path) -> None:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    client = _hub_client(tmp_path, f"http://127.0.0.1:{port}")
    with (
        pytest.raises(WebSocketDisconnect) as exc,
        client.websocket_connect("/ws/panes/p1") as ws,
    ):
        ws.receive_json()
    assert (exc.value.code, exc.value.reason) == (4502, "kanbot_unavailable")


def test_terminal_invalid_pane_id(tmp_path: Path) -> None:
    client = _hub_client(tmp_path, "http://127.0.0.1:9")
    with (
        pytest.raises(WebSocketDisconnect) as exc,
        client.websocket_connect("/ws/panes/bad.id") as ws,
    ):
        ws.receive_json()
    assert exc.value.code == 4400
