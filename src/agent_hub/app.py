"""FastAPI ilovasi: API va build qilingan frontend bitta jarayonda."""

from __future__ import annotations

import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse, Response

from agent_hub import __version__
from agent_hub.kanbot_client import DEFAULT_KANBOT_URL, KanbotClient, KanbotError
from agent_hub.kanbot_safety import Problem, check_config, check_runners, kanbot_config_path

STATIC_DIR = Path(__file__).parent / "static"

# SPA fallback'ga tushmasligi kerak bo'lgan yo'l prefikslari.
_RESERVED_PREFIXES = ("api/", "ws/")


def create_app(
    static_dir: Path = STATIC_DIR,
    kanbot: KanbotClient | None = None,
    kanbot_config: Path | None = None,
) -> FastAPI:
    client = kanbot or KanbotClient(os.environ.get("AGENT_HUB_KANBOT_URL", DEFAULT_KANBOT_URL))

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        try:
            yield
        finally:
            await client.aclose()

    app = FastAPI(
        title="Agent Hub", version=__version__, docs_url=None, redoc_url=None, lifespan=lifespan
    )

    @app.get("/api/health")
    async def health() -> dict[str, Any]:
        problems: list[Problem] = list(check_config(kanbot_config or kanbot_config_path()))
        kanbot_info: dict[str, Any] = {"url": client.base_url, "reachable": False}
        try:
            kb_health = await client.health()
            runners = await client.runners()
        except KanbotError as exc:
            problems.append(Problem("kanbot_unavailable", "error", {"error": str(exc)}))
        else:
            kanbot_info.update(
                reachable=True,
                version=kb_health.version,
                runners_online=sum(1 for r in runners if r.online),
                agents=sorted({a for r in runners if r.online for a in r.capabilities}),
            )
            problems.extend(check_runners(runners))
        return {
            "ok": not any(p.severity == "error" for p in problems),
            "version": __version__,
            "kanbot": kanbot_info,
            "problems": [p.as_dict() for p in problems],
        }

    @app.api_route("/api/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
    async def api_not_found(path: str) -> JSONResponse:
        return JSONResponse(
            status_code=404, content={"code": "not_found", "params": {"path": f"/api/{path}"}}
        )

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
            return JSONResponse(
                status_code=503,
                content={"code": "frontend_not_built", "params": {}},
            )
        return FileResponse(index, headers={"Cache-Control": "no-cache"})

    return app
