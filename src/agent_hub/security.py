"""Agent Hub uchun Host/Origin himoyasi (HTTP va WebSocket).

* Host faqat loopback nomi + port (DNS rebinding'dan himoya).
* Origin bo'lsa — faqat Agent Hub'ning o'z manzili yoki aniq ruxsat etilganlar (masalan, Vite dev).
"""

from __future__ import annotations

import json
import logging
from collections.abc import Iterable

from starlette.types import ASGIApp, Receive, Scope, Send

LOOPBACK_NAMES = ("127.0.0.1", "localhost", "[::1]")

logger = logging.getLogger(__name__)


def _header(scope: Scope, name: bytes) -> str | None:
    for key, value in scope.get("headers", ()):
        if key == name:
            return bytes(value).decode("latin-1")
    return None


def _normalize_origin(origin: str) -> str:
    return origin.strip().rstrip("/").lower()


class HostOriginGuard:
    def __init__(self, app: ASGIApp, port: int, extra_origins: Iterable[str] = ()) -> None:
        self.app = app
        self.allowed_hosts = frozenset(f"{name}:{port}" for name in LOOPBACK_NAMES)
        self.allowed_origins = frozenset(
            [f"http://{name}:{port}" for name in LOOPBACK_NAMES]
            + [_normalize_origin(origin) for origin in extra_origins]
        )

    def rejection(self, scope: Scope) -> tuple[str, dict[str, str | None]] | None:
        host = _header(scope, b"host")
        if host is None or host.lower() not in self.allowed_hosts:
            return "forbidden_host", {"host": host}
        origin = _header(scope, b"origin")
        if origin is not None and _normalize_origin(origin) not in self.allowed_origins:
            return "forbidden_origin", {"origin": origin}
        return None

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] not in ("http", "websocket"):
            await self.app(scope, receive, send)
            return
        rejected = self.rejection(scope)
        if rejected is None:
            await self.app(scope, receive, send)
            return
        code, params = rejected
        logger.warning("rad etildi %s: %s %s", scope.get("path", ""), code, params)
        if scope["type"] == "websocket":
            # accept'dan oldingi close'ni uvicorn HTTP 403 ga aylantiradi.
            await send({"type": "websocket.close", "code": 1008})
            return
        body = json.dumps({"code": code, "params": params}).encode()
        await send(
            {
                "type": "http.response.start",
                "status": 403,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(body)).encode()),
                ],
            }
        )
        await send({"type": "http.response.body", "body": body})
