"""KanBot serverini Host/Origin himoyasi bilan ishga tushiradi.

KanBot 0.8.x da CORS `*`, autentifikatsiya yo'q va `/ws/web` Origin'ni tekshirmaydi: brauzerda
ochilgan istalgan sayt 127.0.0.1:8787 ga so'rov yuborib agent ishga tushirishi mumkin. Bu skript
KanBot fayllarini o'zgartirmaydi — `kanbot.server.app.create_app()` ni ASGI middleware bilan
o'raydi:

* Host sarlavhasi faqat loopback nomi + port bo'lishi kerak (DNS rebinding'dan himoya).
* Origin sarlavhasi bo'lsa, u KanBot'ning o'z manzili (yoki --allow-origin) bo'lishi kerak.
  Brauzer bo'lmagan mijozlar (runner, `kanbot` CLI, Agent Hub backend) Origin yubormaydi va o'tadi.

Skript KanBot'ning venv python'ida ishlaydi, shuning uchun faqat stdlib va uvicorn'ga tayanadi.
"""

from __future__ import annotations

import argparse
import importlib
import sys
from collections.abc import Awaitable, Callable, Iterable, MutableMapping
from typing import Any

Scope = MutableMapping[str, Any]
Message = MutableMapping[str, Any]
Receive = Callable[[], Awaitable[Message]]
Send = Callable[[Message], Awaitable[None]]
ASGIApp = Callable[[Scope, Receive, Send], Awaitable[None]]

LOOPBACK_HOST = "127.0.0.1"
LOOPBACK_NAMES = ("127.0.0.1", "localhost", "[::1]")


def _header(scope: Scope, name: bytes) -> str | None:
    for key, value in scope.get("headers", ()):
        if key == name:
            return bytes(value).decode("latin-1")
    return None


class HostOriginGuard:
    """Begona Host yoki Origin bilan kelgan HTTP va WebSocket so'rovlarini rad etadi."""

    def __init__(self, app: ASGIApp, port: int, extra_origins: Iterable[str] = ()) -> None:
        self.app = app
        self.allowed_hosts = frozenset(f"{name}:{port}" for name in LOOPBACK_NAMES)
        self.allowed_origins = frozenset(
            [f"http://{name}:{port}" for name in LOOPBACK_NAMES]
            + [origin.rstrip("/").lower() for origin in extra_origins]
        )

    def rejection(self, scope: Scope) -> str | None:
        host = _header(scope, b"host")
        if host is None or host.lower() not in self.allowed_hosts:
            return f"host {host!r}"
        origin = _header(scope, b"origin")
        if origin is not None and origin.rstrip("/").lower() not in self.allowed_origins:
            return f"origin {origin!r}"
        return None

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] not in ("http", "websocket"):
            await self.app(scope, receive, send)
            return
        reason = self.rejection(scope)
        if reason is None:
            await self.app(scope, receive, send)
            return
        print(f"kanbot-guard: rad etildi {scope.get('path', '')} ({reason})", file=sys.stderr)
        if scope["type"] == "websocket":
            # accept'dan oldingi close'ni uvicorn HTTP 403 ga aylantiradi.
            await send({"type": "websocket.close", "code": 1008})
            return
        body = b'{"detail":"forbidden: foreign host or origin"}'
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


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else None)
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--db", default=None, help="KanBot DB yo'li (default: KanBot tanlaydi)")
    parser.add_argument("--log-level", default="warning")
    parser.add_argument(
        "--allow-origin",
        action="append",
        default=[],
        help="qo'shimcha ruxsat etilgan Origin (takrorlanadi)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    import uvicorn

    kanbot_app = importlib.import_module("kanbot.server.app")
    version = getattr(importlib.import_module("kanbot"), "__version__", "?")
    app = HostOriginGuard(kanbot_app.create_app(db_path=args.db), args.port, args.allow_origin)
    print(f"KanBot v{version} (himoyalangan) → http://{LOOPBACK_HOST}:{args.port}", flush=True)
    uvicorn.run(
        app,
        host=LOOPBACK_HOST,
        port=args.port,
        log_level=args.log_level,
        access_log=False,
        proxy_headers=False,
        server_header=False,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
