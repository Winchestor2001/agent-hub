"""Yagona xato formati: `{code, params, detail}`.

`code` va `params` UI'da i18n matniga aylantiriladi, `detail` — faqat diagnostika uchun (inglizcha
yoki CLI chiqishi). Domen xatolari HTTP statusga shu yerda moslanadi.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from agent_hub.backlog_client import BacklogError
from agent_hub.kanbot_client import KanbotError
from agent_hub.registry import RegistryError
from agent_hub.services.sessions import SessionError
from agent_hub.services.updates import UpdateError
from agent_hub.services.uploads import UploadError

logger = logging.getLogger(__name__)


class ApiError(Exception):
    def __init__(
        self, http_status: int, code: str, /, *, detail: str | None = None, **params: Any
    ) -> None:
        super().__init__(f"{code}: {params}")
        self.status = http_status
        self.code = code
        self.detail = detail
        self.params = params


_REGISTRY_STATUS = {"project_not_found": 404, "project_exists": 409, "registry_invalid": 500}
_SESSION_STATUS = {"runner_offline": 409, "agent_unavailable": 409, "runner_unsafe": 409}
_BACKLOG_STATUS = {
    "backlog_not_found": 503,
    "backlog_cli_missing": 503,
    "task_not_found": 404,
    "backlog_locked": 409,
    "backlog_timeout": 504,
    "backlog_exists": 409,
}
_UPLOAD_STATUS = {
    "upload_type_invalid": 415,
    "upload_not_found": 404,
}
_UPDATE_STATUS = {
    "brew_missing": 503,
    "update_agent_unknown": 404,
    "update_cask_missing": 409,
    "update_running": 409,
}
_KANBOT_STATUS = {
    "kanbot_unavailable": 503,
    "kanbot_no_runner": 409,
    "pane_not_found": 404,
}


def error_body(code: str, params: dict[str, Any] | None = None, detail: str | None = None) -> Any:
    return {"code": code, "params": params or {}, "detail": detail}


def error_response(
    status: int, code: str, params: dict[str, Any] | None = None, detail: str | None = None
) -> JSONResponse:
    return JSONResponse(status_code=status, content=error_body(code, params, detail))


def _describe(exc: Exception) -> tuple[int, str, dict[str, Any], str | None]:
    if isinstance(exc, ApiError):
        return exc.status, exc.code, exc.params, exc.detail
    if isinstance(exc, RegistryError):
        return _REGISTRY_STATUS.get(exc.code, 422), exc.code, exc.params, None
    if isinstance(exc, SessionError):
        return _SESSION_STATUS.get(exc.code, 422), exc.code, exc.params, None
    if isinstance(exc, UpdateError):
        return _UPDATE_STATUS.get(exc.code, 422), exc.code, exc.params, None
    if isinstance(exc, UploadError):
        return _UPLOAD_STATUS.get(exc.code, 422), exc.code, exc.params, None
    if isinstance(exc, BacklogError):
        return _BACKLOG_STATUS.get(exc.code, 502), exc.code, exc.params, str(exc)
    if isinstance(exc, KanbotError):
        return _KANBOT_STATUS.get(exc.code, 502), exc.code, {}, str(exc)
    if isinstance(exc, RequestValidationError):
        errors = [
            {"loc": list(err.get("loc", ())), "msg": err.get("msg", ""), "type": err.get("type")}
            for err in exc.errors()
        ]
        return 422, "validation_error", {"errors": errors}, None
    return 500, "internal_error", {}, None


def install_error_handlers(app: FastAPI) -> None:
    async def handle(request: Request, exc: Exception) -> JSONResponse:
        status, code, params, detail = _describe(exc)
        if status >= 500:
            logger.warning("%s %s: %s %s", request.method, request.url.path, code, detail or exc)
        return error_response(status, code, params, detail)

    async def handle_unexpected(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("%s %s: kutilmagan xato", request.method, request.url.path)
        return error_response(500, "internal_error")

    exc_types = (
        ApiError,
        RegistryError,
        SessionError,
        UpdateError,
        UploadError,
        BacklogError,
        KanbotError,
    )
    for exc_type in exc_types:
        app.add_exception_handler(exc_type, handle)
    app.add_exception_handler(RequestValidationError, handle)
    app.add_exception_handler(Exception, handle_unexpected)
