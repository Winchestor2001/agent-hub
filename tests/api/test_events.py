"""Push yangilanishlar: EventHub (soxta upstream) va `/api/events` SSE (haqiqiy uvicorn) bilan."""

from __future__ import annotations

import asyncio
import json
import queue
import socket
import threading
import time
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx
import pytest
import uvicorn
from websockets.sync.server import ServerConnection, serve

from agent_hub.api.events import ALL_TOPICS, EventHub, event_stream, topics_for
from agent_hub.api.terminal import ChannelClosed
from agent_hub.app import create_asgi_app
from agent_hub.settings import Settings


class FakeUpstream:
    """KanBot `/ws/web` o'rniga: `push` qilingan xabarlar, `None` — uzilish."""

    def __init__(self) -> None:
        self.inbox: asyncio.Queue[str | None] = asyncio.Queue()
        self.received = 0
        self.closed = False

    def push(self, *messages: dict[str, Any] | None) -> None:
        for message in messages:
            self.inbox.put_nowait(None if message is None else json.dumps(message))

    async def recv(self) -> str | None:
        item = await self.inbox.get()
        self.received += 1
        return item

    async def send(self, text: str) -> None:
        raise ChannelClosed

    async def close(self, code: int, reason: str) -> None:
        self.closed = True


class FakeConnect:
    """Har chaqiruvda navbatdagi natija: `FakeUpstream` yoki ulanish xatosi."""

    def __init__(self, *results: FakeUpstream | Exception) -> None:
        self.results = list(results)
        self.calls = 0

    async def __call__(self) -> FakeUpstream:
        self.calls += 1
        result = self.results.pop(0) if self.results else OSError("refused")
        if isinstance(result, Exception):
            raise result
        return result


async def eventually(condition: Any) -> None:
    async with asyncio.timeout(1):
        while not condition():  # noqa: ASYNC110 — soxta upstream holatini kuzatish
            await asyncio.sleep(0.005)


def hub_for(*results: FakeUpstream | Exception) -> tuple[EventHub, FakeConnect]:
    connect = FakeConnect(*results)
    return EventHub(connect, coalesce=0.01, reconnect_delays=(0.01,)), connect


@pytest.mark.parametrize(
    ("raw", "topics"),
    [
        ('{"type": "pane.updated", "pane": {"id": "p1"}}', {"sessions"}),
        ('{"type": "panes.updated"}', {"sessions"}),
        ('{"type": "agent.blocked", "pane": {}}', {"sessions"}),
        ('{"type": "runner.updated", "runner": {}}', {"health"}),
        ('{"type": "agent.sessions.updated"}', set()),
        ('{"type": "pane.data", "pane_id": "p1", "data": ""}', set()),
        ('{"type": "hello", "version": "0.8.2"}', set()),
        ('{"type": 5}', set()),
        ("[]", set()),
        ("not json", set()),
    ],
)
def test_topics_for(raw: str, topics: set[str]) -> None:
    assert topics_for(raw) == topics


async def test_events_are_coalesced_per_subscriber() -> None:
    upstream = FakeUpstream()
    hub, _ = hub_for(upstream)
    async with hub.subscribe() as first, hub.subscribe() as second:
        await eventually(lambda: hub.connected)
        upstream.push(
            {"type": "hello"},
            {"type": "pane.updated"},
            {"type": "agent.blocked"},
            {"type": "panes.updated"},
            {"type": "runner.updated"},
        )
        assert await first.next() == {"sessions", "health"}
        assert await second.next() == {"sessions", "health"}
    assert upstream.closed


async def test_slow_subscriber_does_not_block_upstream() -> None:
    upstream = FakeUpstream()
    hub, _ = hub_for(upstream)
    async with hub.subscribe() as sub:
        await eventually(lambda: hub.connected)
        upstream.push(*[{"type": "panes.updated"}] * 10_000)
        # Obunachi o'qimayapti, lekin upstream oxirigacha o'qiladi va kutilayotgani bitta mavzu.
        await eventually(lambda: upstream.received == 10_000)
        assert await sub.next() == {"sessions"}


async def test_reconnect_marks_all_topics_and_logs_once(caplog: pytest.LogCaptureFixture) -> None:
    first, second = FakeUpstream(), FakeUpstream()
    hub, connect = hub_for(OSError("refused"), OSError("refused"), first, second)
    async with hub.subscribe() as sub:
        # Oldin ulanib bo'lmagan: ulangach o'tkazib yuborilgan hodisalar o'rniga hammasi.
        assert await sub.next() == ALL_TOPICS
        first.push(None)
        assert await sub.next() == ALL_TOPICS
        await eventually(lambda: connect.calls == 4 and hub.connected)
        second.push({"type": "pane.updated"})
        assert await sub.next() == {"sessions"}
    assert first.closed and second.closed
    failures = [r for r in caplog.records if "ulanib bo'lmadi" in r.getMessage()]
    assert len(failures) == 1


async def test_first_connect_does_not_mark_topics() -> None:
    upstream = FakeUpstream()
    hub, _ = hub_for(upstream)
    async with hub.subscribe() as sub:
        await eventually(lambda: hub.connected)
        with pytest.raises(TimeoutError):
            async with asyncio.timeout(0.05):
                await sub.next()


async def test_upstream_closes_when_last_subscriber_leaves() -> None:
    first, second = FakeUpstream(), FakeUpstream()
    hub, connect = hub_for(first, second)
    async with hub.subscribe():
        await eventually(lambda: hub.connected)
    assert first.closed
    assert not hub.connected
    assert hub.subscribers == 0
    # Yangi obunachi — yangi upstream.
    async with hub.subscribe():
        await eventually(lambda: hub.connected)
    assert connect.calls == 2
    assert second.closed


async def test_event_stream_format() -> None:
    upstream = FakeUpstream()
    hub, _ = hub_for(upstream)
    stream = event_stream(hub, heartbeat=0.05)
    assert await anext(stream) == "retry: 2000\nevent: ready\ndata: {}\n\n"
    assert await anext(stream) == ": ping\n\n"
    upstream.push({"type": "runner.updated"}, {"type": "pane.updated"})
    assert await anext(stream) == (
        'event: invalidate\ndata: {"topics": ["health", "sessions"]}\n\n'
    )
    await stream.aclose()
    assert upstream.closed
    assert hub.subscribers == 0


# --- /api/events end-to-end ----------------------------------------------------------------


@dataclass
class FakeKanbotEvents:
    """KanBot `/ws/web` taqlidi: hello'dan keyin `outbox` dagi hodisalarni yuboradi."""

    url: str = ""
    outbox: queue.Queue[dict[str, Any]] = field(default_factory=queue.Queue)
    connections: int = 0
    closed: threading.Event = field(default_factory=threading.Event)

    def handle(self, ws: ServerConnection) -> None:
        self.connections += 1
        try:
            ws.send(json.dumps({"type": "hello", "version": "0.8.2"}))
            while True:
                try:
                    ws.send(json.dumps(self.outbox.get(timeout=0.05)))
                except queue.Empty:
                    ws.ping()
        except Exception:  # noqa: S110 — mijoz ketdi
            pass
        finally:
            self.closed.set()


@pytest.fixture
def kanbot_events() -> Iterator[FakeKanbotEvents]:
    fake = FakeKanbotEvents()
    with serve(fake.handle, "127.0.0.1", 0) as server:
        fake.url = f"http://127.0.0.1:{server.socket.getsockname()[1]}"
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        yield fake
    thread.join(timeout=5)


@pytest.fixture
def hub_server(tmp_path: Path, kanbot_events: FakeKanbotEvents) -> Iterator[str]:
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    settings = Settings(
        config_dir=tmp_path,
        port=port,
        kanbot_url=kanbot_events.url,
        kanbot_config=tmp_path / "kanbot.json",
    )
    config = uvicorn.Config(
        create_asgi_app(settings, static_dir=tmp_path / "static"),
        log_level="warning",
        timeout_graceful_shutdown=1,
    )
    server = uvicorn.Server(config)
    thread = threading.Thread(target=server.run, kwargs={"sockets": [sock]}, daemon=True)
    thread.start()
    deadline = time.monotonic() + 5
    while not server.started:
        assert time.monotonic() < deadline, "uvicorn ishga tushmadi"
        time.sleep(0.01)
    yield f"http://127.0.0.1:{port}"
    server.should_exit = True
    thread.join(timeout=5)
    sock.close()


def _sse_events(lines: Iterator[str]) -> Iterator[tuple[str, str]]:
    event = data = ""
    for line in lines:
        if line.startswith("event: "):
            event = line.removeprefix("event: ")
        elif line.startswith("data: "):
            data = line.removeprefix("data: ")
        elif line == "" and event:
            yield event, data
            event = data = ""


def test_sse_end_to_end(hub_server: str, kanbot_events: FakeKanbotEvents) -> None:
    with (
        httpx.Client(base_url=hub_server, timeout=5) as client,
        client.stream("GET", "/api/events") as resp,
    ):
        assert resp.status_code == 200
        assert resp.headers["content-type"].startswith("text/event-stream")
        events = _sse_events(resp.iter_lines())
        assert next(events) == ("ready", "{}")

        started = time.monotonic()
        kanbot_events.outbox.put({"type": "pane.updated", "pane": {"id": "p1", "state": "blocked"}})
        assert next(events) == ("invalidate", '{"topics": ["sessions"]}')
        assert time.monotonic() - started < 1

    # Brauzer ketdi → upstream ham yopiladi.
    assert kanbot_events.closed.wait(timeout=5)
    assert kanbot_events.connections == 1


def test_sse_rejects_foreign_origin(hub_server: str) -> None:
    with httpx.Client(base_url=hub_server, timeout=5) as client:
        resp = client.get("/api/events", headers={"Origin": "http://evil.example"})
    assert resp.status_code == 403
    assert resp.json()["code"] == "forbidden_origin"
