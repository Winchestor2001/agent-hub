"""FastAPI ilovasi: API va build qilingan frontend bitta jarayonda."""

from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse, Response

from agent_hub import __version__

STATIC_DIR = Path(__file__).parent / "static"

# SPA fallback'ga tushmasligi kerak bo'lgan yo'l prefikslari.
_RESERVED_PREFIXES = ("api/", "ws/")


def create_app(static_dir: Path = STATIC_DIR) -> FastAPI:
    app = FastAPI(title="Agent Hub", version=__version__, docs_url=None, redoc_url=None)

    @app.get("/api/health")
    async def health() -> dict[str, object]:
        return {"ok": True, "version": __version__}

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
