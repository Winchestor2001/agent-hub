"""Pane terminali: brauzer ↔ Agent Hub ↔ KanBot `/ws/web` WebSocket proxy'si.

KanBot hub'i `pane.data` ni har obunachiga ketma-ket `await send` bilan yuboradi: proxy upstream'ni
o'qimay qo'ysa, KanBot'ning butun jonli oqimi (va runner) tiqilib qoladi. Shuning uchun upstream
doim o'qiladi, mijozga ketadigan xabarlar esa bayt limiti bor navbatga tushadi. Navbat to'lsa —
brauzer o'qimayapti — mijoz `slow_client` bilan uziladi.

Mijoz protokoli (JSON matn):
  → {"type": "input", "data": "<matn>"} | {"type": "keys", "keys": [...]}
    | {"type": "resize", "rows": N, "cols": N}
  ← {"type": "data", "data": "<base64>", "replay": bool} | {"type": "error", "code": "..."}
Yopilish: `Close` kodlari, reason — xato kodi. pane_id doim URL'dan olinadi, mijoz xabaridan emas.
"""

from __future__ import annotations

import asyncio
import base64
import contextlib
import json
import logging
from collections import deque
from collections.abc import Awaitable, Mapping
from typing import Any, NamedTuple, Protocol

from fastapi import APIRouter, WebSocket
from starlette.websockets import WebSocketDisconnect
from websockets.asyncio.client import ClientConnection, connect
from websockets.exceptions import ConnectionClosed, InvalidHandshake

from agent_hub.kanbot_client import is_valid_pane_id, validate_keys

from .deps import Hub

logger = logging.getLogger(__name__)

router = APIRouter()

QUEUE_LIMIT = 2 * 1024 * 1024
MAX_INPUT = 64 * 1024
# Replay 512 KB scrollback'ni base64'da bitta xabarda olib keladi.
UPSTREAM_MAX_SIZE = 8 * 1024 * 1024
CONNECT_TIMEOUT = 3.0
CLOSE_TIMEOUT = 2.0
ROWS_RANGE = (2, 500)
COLS_RANGE = (10, 1000)


class Close(NamedTuple):
    code: int
    reason: str


CLIENT_LEFT = Close(1000, "")
BAD_REQUEST = Close(4400, "bad_request")
PANE_GONE = Close(4404, "pane_gone")
SLOW_CLIENT = Close(4408, "slow_client")
KANBOT_UNAVAILABLE = Close(4502, "kanbot_unavailable")
INTERNAL_ERROR = Close(1011, "internal_error")


class ChannelClosed(Exception):
    """Yopilgan ulanishga yuborishga urinildi."""


class Channel(Protocol):
    async def recv(self) -> str | None:
        """Keyingi matn xabar; ulanish yopilgan bo'lsa None."""

    async def send(self, text: str) -> None:
        """Yopilgan ulanishda `ChannelClosed`."""

    async def close(self, code: int, reason: str) -> None: ...


class _ByteQueue:
    """Mijozga ketadigan xabarlar: umumiy hajm limitdan oshsa `put` False qaytaradi."""

    def __init__(self, limit: int) -> None:
        self.limit = limit
        self._items: deque[str] = deque()
        self._size = 0
        self._ready = asyncio.Event()

    def put(self, text: str) -> bool:
        if self._size + len(text) > self.limit:
            return False
        self._items.append(text)
        self._size += len(text)
        self._ready.set()
        return True

    async def get(self) -> str:
        while not self._items:
            self._ready.clear()
            await self._ready.wait()
        text = self._items.popleft()
        self._size -= len(text)
        return text


def _clamp(value: object, bounds: tuple[int, int]) -> int | None:
    if not isinstance(value, int) or isinstance(value, bool):
        return None
    return min(max(value, bounds[0]), bounds[1])


def _error(code: str) -> str:
    return json.dumps({"type": "error", "code": code})


class PaneBridge:
    """Bitta pane uchun ikki tomonlama oqim; transport `Channel` orqali beriladi."""

    def __init__(self, pane_id: str, *, queue_limit: int = QUEUE_LIMIT) -> None:
        self.pane_id = pane_id
        self.queue_limit = queue_limit

    def attach_message(self, rows: int | None, cols: int | None) -> str:
        return json.dumps(
            {"type": "pane.attach", "pane_id": self.pane_id, "rows": rows or 0, "cols": cols or 0}
        )

    def from_upstream(self, raw: str) -> tuple[str | None, Close | None]:
        """KanBot xabari → (mijozga xabar, yopilish). Boshqa pane va board hodisalari tashlanadi."""
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            return None, None
        if not isinstance(msg, dict) or msg.get("pane_id") != self.pane_id:
            return None, None
        kind = msg.get("type")
        if kind == "pane.gone":
            return None, PANE_GONE
        data = msg.get("data")
        if kind != "pane.data" or not isinstance(data, str):
            return None, None
        return json.dumps({"type": "data", "data": data, "replay": bool(msg.get("replay"))}), None

    def from_client(self, raw: str) -> tuple[str | None, str | None]:
        """Mijoz xabari → (KanBot'ga xabar, mijozga xato)."""
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            return None, _error("bad_message")
        if not isinstance(msg, dict):
            return None, _error("bad_message")
        kind = msg.get("type")
        upstream: dict[str, Any]
        if kind == "input":
            data = msg.get("data")
            if not isinstance(data, str) or not data or len(data) > MAX_INPUT:
                return None, _error("bad_message")
            upstream = {"type": "pane.input", "data": base64.b64encode(data.encode()).decode()}
        elif kind == "keys":
            keys = msg.get("keys")
            if not isinstance(keys, list) or not all(isinstance(key, str) for key in keys):
                return None, _error("invalid_keys")
            try:
                upstream = {"type": "pane.input", "keys": validate_keys(keys)}
            except ValueError:
                return None, _error("invalid_keys")
        elif kind == "resize":
            rows, cols = _clamp(msg.get("rows"), ROWS_RANGE), _clamp(msg.get("cols"), COLS_RANGE)
            if rows is None or cols is None:
                return None, _error("bad_message")
            upstream = {"type": "pane.resize", "rows": rows, "cols": cols}
        else:
            return None, _error("bad_message")
        return json.dumps({**upstream, "pane_id": self.pane_id}), None

    async def run(
        self, upstream: Channel, client: Channel, rows: int | None, cols: int | None
    ) -> Close:
        """Bir tomon tugaguncha ishlaydi; yopilish sababini qaytaradi (kanallarni yopmaydi)."""
        queue = _ByteQueue(self.queue_limit)

        async def upstream_to_queue() -> Close:
            try:
                await upstream.send(self.attach_message(rows, cols))
            except ChannelClosed:
                return KANBOT_UNAVAILABLE
            while True:
                raw = await upstream.recv()
                if raw is None:
                    return KANBOT_UNAVAILABLE
                out, close = self.from_upstream(raw)
                if out is not None and not queue.put(out):
                    return SLOW_CLIENT
                if close is not None:
                    return close

        async def queue_to_client() -> Close:
            try:
                while True:
                    await client.send(await queue.get())
            except ChannelClosed:
                return CLIENT_LEFT

        async def client_to_upstream() -> Close:
            while True:
                raw = await client.recv()
                if raw is None:
                    return CLIENT_LEFT
                out, error = self.from_client(raw)
                if out is not None:
                    try:
                        await upstream.send(out)
                    except ChannelClosed:
                        return KANBOT_UNAVAILABLE
                if error is not None and not queue.put(error):
                    return SLOW_CLIENT

        tasks = [
            asyncio.create_task(upstream_to_queue()),
            asyncio.create_task(queue_to_client()),
            asyncio.create_task(client_to_upstream()),
        ]
        try:
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
        first = next(iter(done))
        if first.exception() is not None:
            logger.error("terminal proxy xatosi (%s)", self.pane_id, exc_info=first.exception())
            return INTERNAL_ERROR
        return first.result()


class _ClientChannel:
    def __init__(self, websocket: WebSocket) -> None:
        self._ws = websocket

    async def recv(self) -> str | None:
        try:
            message = await self._ws.receive()
        except (WebSocketDisconnect, RuntimeError):
            return None
        if message["type"] == "websocket.disconnect":
            return None
        text = message.get("text")
        if isinstance(text, str):
            return text
        data = message.get("bytes")
        return data.decode(errors="replace") if isinstance(data, bytes) else ""

    async def send(self, text: str) -> None:
        try:
            await self._ws.send_text(text)
        except (WebSocketDisconnect, RuntimeError, OSError) as exc:
            raise ChannelClosed from exc

    async def close(self, code: int, reason: str) -> None:
        with contextlib.suppress(WebSocketDisconnect, RuntimeError, OSError):
            await self._ws.close(code, reason)


class _UpstreamChannel:
    def __init__(self, connection: ClientConnection) -> None:
        self._ws = connection

    async def recv(self) -> str | None:
        try:
            data = await self._ws.recv()
        except ConnectionClosed:
            return None
        return data if isinstance(data, str) else data.decode(errors="replace")

    async def send(self, text: str) -> None:
        try:
            await self._ws.send(text)
        except ConnectionClosed as exc:
            raise ChannelClosed from exc

    async def close(self, code: int, reason: str) -> None:
        await self._ws.close(code, reason)


def _terminal_size(params: Mapping[str, str]) -> tuple[int | None, int | None]:
    def parse(name: str, bounds: tuple[int, int]) -> int | None:
        raw = params.get(name, "")
        return _clamp(int(raw), bounds) if raw.isdecimal() else None

    return parse("rows", ROWS_RANGE), parse("cols", COLS_RANGE)


async def _quietly(action: Awaitable[None]) -> None:
    """Yopish to'xtab qolgan mijozda osilib qolmasligi uchun vaqt cheklovi bilan."""
    with contextlib.suppress(Exception):
        async with asyncio.timeout(CLOSE_TIMEOUT):
            await action


@router.websocket("/ws/panes/{pane_id}")
async def pane_terminal(websocket: WebSocket, pane_id: str) -> None:
    hub: Hub = websocket.app.state.hub
    # Avval accept: aks holda brauzer yopilish kodini ko'rmaydi (HTTP 403 → 1006).
    await websocket.accept()
    client = _ClientChannel(websocket)
    if not is_valid_pane_id(pane_id):
        await _quietly(client.close(*BAD_REQUEST))
        return
    rows, cols = _terminal_size(websocket.query_params)
    url = hub.kanbot.web_socket_url
    try:
        connection = await connect(
            url,
            proxy=None,
            open_timeout=CONNECT_TIMEOUT,
            max_size=UPSTREAM_MAX_SIZE,
            compression=None,
        )
    except (OSError, TimeoutError, InvalidHandshake) as exc:
        logger.warning("KanBot WebSocket'iga ulanib bo'lmadi (%s): %s", url, exc)
        await _quietly(client.close(*KANBOT_UNAVAILABLE))
        return
    upstream = _UpstreamChannel(connection)
    try:
        close = await PaneBridge(pane_id).run(upstream, client, rows, cols)
    finally:
        # Upstream birinchi: KanBot obunani darhol bo'shatadi, mijoz osilib qolsa ham.
        await _quietly(upstream.close(1000, ""))
    if close.code != CLIENT_LEFT.code:
        logger.info("terminal %s yopildi: %s", pane_id, close.reason)
    await _quietly(client.close(*close))
