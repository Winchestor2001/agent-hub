"""FastAPI ilovasi: API va build qilingan frontend bitta jarayonda."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse, Response

from agent_hub import __version__
from agent_hub.api import events, health, projects, sessions, tasks, terminal
from agent_hub.api.deps import BacklogFactory, Hub
from agent_hub.api.errors import error_response, install_error_handlers
from agent_hub.backlog_client import BacklogClient
from agent_hub.kanbot_client import KanbotClient
from agent_hub.registry import Registry
from agent_hub.security import HostOriginGuard
from agent_hub.settings import Settings

STATIC_DIR = Path(__file__).parent / "static"

# SPA fallback'ga tushmasligi kerak bo'lgan yo'l prefikslari.
_RESERVED_PREFIXES = ("api/", "ws/")


def create_app(
    settings: Settings,
    static_dir: Path = STATIC_DIR,
    kanbot: KanbotClient | None = None,
    backlog_factory: BacklogFactory = BacklogClient,
) -> FastAPI:
    """FastAPI ilovasi (testlar uchun). Serverga `create_asgi_app` beriladi."""
    client = kanbot or KanbotClient(settings.kanbot_url)
    registry = Registry(settings.projects_file)
    event_hub = events.EventHub.for_url(client.web_socket_url)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        registry.load()  # projects.yaml yo'q bo'lsa shu yerda yaratiladi
        try:
            yield
        finally:
            await event_hub.close()
            await client.aclose()

    app = FastAPI(
        title="Agent Hub", version=__version__, docs_url=None, redoc_url=None, lifespan=lifespan
    )
    app.state.settings = settings
    app.state.registry = registry
    app.state.hub = Hub(settings, registry, client, backlog_factory)
    app.state.events = event_hub
    install_error_handlers(app)
    routers = (health, projects, tasks, sessions, terminal, events)
    for module in routers:
        app.include_router(module.router)

    @app.api_route("/api/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
    async def api_not_found(path: str) -> JSONResponse:
        return error_response(404, "not_found", {"path": f"/api/{path}"})

    @app.get("/{path:path}", include_in_schema=False)
    def spa(path: str) -> Response:
        if path.startswith(_RESERVED_PREFIXES):
            raise HTTPException(status_code=404)
        root = static_dir.resolve()
        if path:
            candidate = (root / path).resolve()
            if candidate.is_relative_to(root) and candidate.is_file():
                return FileResponse(candidate)
        index = root / "index.html"
        if not index.is_file():
            return error_response(503, "frontend_not_built")
        return FileResponse(index, headers={"Cache-Control": "no-cache"})

    return app


def create_asgi_app(settings: Settings, static_dir: Path = STATIC_DIR) -> HostOriginGuard:
    """Host/Origin himoyasi bilan o'ralgan ilova."""
    return HostOriginGuard(create_app(settings, static_dir), settings.port, settings.extra_origins)
