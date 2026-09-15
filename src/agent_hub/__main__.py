"""`python -m agent_hub` — serverni faqat 127.0.0.1 da ishga tushiradi."""

from __future__ import annotations

import os

import uvicorn

from agent_hub.app import create_app

HOST = "127.0.0.1"
DEFAULT_PORT = 8700


def resolve_port(env: dict[str, str] | None = None) -> int:
    raw = (env if env is not None else os.environ).get("AGENT_HUB_PORT", "")
    if not raw:
        return DEFAULT_PORT
    port = int(raw)
    if not 1 <= port <= 65535:
        raise ValueError(f"AGENT_HUB_PORT noto'g'ri: {raw}")
    return port


def main() -> None:
    uvicorn.run(
        create_app(),
        host=HOST,
        port=resolve_port(),
        access_log=False,
        log_level="info",
        proxy_headers=False,
        server_header=False,
    )


if __name__ == "__main__":
    main()
