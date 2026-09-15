"""`python -m agent_hub` — serverni faqat 127.0.0.1 da ishga tushiradi."""

from __future__ import annotations

import sys

import uvicorn

from agent_hub.app import create_asgi_app
from agent_hub.settings import Settings, SettingsError


def main() -> None:
    try:
        settings = Settings.load()
    except SettingsError as exc:
        sys.exit(f"agent-hub: {exc}")
    uvicorn.run(
        create_asgi_app(settings),
        host=settings.host,
        port=settings.port,
        access_log=False,
        log_level="info",
        proxy_headers=False,
        server_header=False,
    )


if __name__ == "__main__":
    main()
