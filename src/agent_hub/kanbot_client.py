"""KanBot HTTP API'ga yagona kirish nuqtasi (KanBot 0.8.x).

Javoblar pydantic modellarga o'giriladi, noma'lum maydonlar e'tiborsiz qoldiriladi. HTTP xatolari
aniq turlarga ajratiladi: ulanib bo'lmadi, runner yo'q (409), runner xatosi (502), pane yo'q (404).
"""

from __future__ import annotations

import logging
import re
from collections.abc import Sequence
from typing import Any, Literal

import httpx
from pydantic import BaseModel, ConfigDict, Field, field_validator

logger = logging.getLogger(__name__)

DEFAULT_KANBOT_URL = "http://127.0.0.1:8787"
DEFAULT_TIMEOUT = httpx.Timeout(5.0, connect=1.0)
# Server runner javobini 15 s kutadi; biz undan biroz ko'proq.
RUNNER_CALL_TIMEOUT = httpx.Timeout(20.0, connect=1.0)
SUPPORTED_VERSION_PREFIX = "0.8."

SESSION_AGENTS: tuple[str, ...] = ("claude", "codex")
AgentName = Literal["claude", "codex"]
MAX_READ_LINES = 500
HOOKS_PLACEHOLDER = "{hooks}"

# KanBot runner'idagi `KEYS` nomlari; yakka belgi (y/n) va C-<belgi> ham ruxsat.
NAMED_KEYS = frozenset(
    {
        "Enter", "Return", "Tab", "Escape", "Esc", "Space", "BSpace", "Backspace",
        "Up", "Down", "Right", "Left", "Home", "End",
    }
)  # fmt: skip
_CTRL_KEY_RE = re.compile(r"^C-[a-z\]\[\\]$")


# --- xatolar -------------------------------------------------------------------------------


class KanbotError(Exception):
    """KanBot kutilmagan javob qaytardi."""

    code = "kanbot_error"

    def __init__(self, message: str, status: int | None = None, detail: str = "") -> None:
        super().__init__(message)
        self.status = status
        self.detail = detail


class KanbotUnavailable(KanbotError):
    """KanBot serveriga ulanib bo'lmadi yoki javob kelmadi."""

    code = "kanbot_unavailable"


class KanbotNoRunner(KanbotError):
    """Kerakli agentga ega onlayn runner yo'q (HTTP 409)."""

    code = "kanbot_no_runner"


class KanbotRunnerError(KanbotError):
    """Runner xato qaytardi, oflayn yoki javob bermadi (HTTP 502)."""

    code = "kanbot_runner_error"


class KanbotPaneNotFound(KanbotError):
    """Pane topilmadi (HTTP 404)."""

    code = "pane_not_found"


_STATUS_ERRORS: dict[int, type[KanbotError]] = {
    404: KanbotPaneNotFound,
    409: KanbotNoRunner,
    502: KanbotRunnerError,
}


# --- modellar ------------------------------------------------------------------------------


class _Model(BaseModel):
    model_config = ConfigDict(extra="ignore")


class KanbotHealth(_Model):
    ok: bool
    version: str
    runners: int = 0

    @property
    def version_supported(self) -> bool:
        return is_supported_version(self.version)


class Runner(_Model):
    id: str
    name: str = ""
    host: str = ""
    status: str = "offline"
    capabilities: list[str] = Field(default_factory=list)
    auto_approve: bool = False
    max_concurrency: int | None = None
    active: int | None = None

    @field_validator("auto_approve", mode="before")
    @classmethod
    def _int_to_bool(cls, value: Any) -> bool:
        return bool(value)

    @property
    def online(self) -> bool:
        return self.status != "offline"


class Pane(_Model):
    id: str
    agent: str = ""
    title: str = ""
    cwd: str = ""
    argv: list[str] = Field(default_factory=list)
    interactive: bool = True
    session_id: str = ""
    card_id: str = ""
    state: str = "unknown"
    state_source: str = ""
    pid: int = 0
    rows: int | None = None
    cols: int | None = None
    started_at: float | None = None
    last_output_at: float | None = None
    ended_at: float | None = None
    exit_code: int | None = None
    alive: bool = False
    runner_id: str = ""
    runner_name: str = ""

    @field_validator("argv", mode="before")
    @classmethod
    def _strip_settings(cls, value: Any) -> Any:
        if isinstance(value, list):
            return strip_settings_arg([str(item) for item in value])
        return value

    @field_validator("session_id", "card_id", "title", "cwd", "state_source", mode="before")
    @classmethod
    def _none_to_empty(cls, value: Any) -> Any:
        return "" if value is None else value


class PaneRead(_Model):
    text: str = ""
    pane: Pane | None = None


class AgentSession(_Model):
    agent: str
    session_id: str
    cwd: str = ""
    name: str = ""
    title: str | None = None
    recap: str | None = None
    recap_role: str | None = None
    turns: int = 0
    started_at: float | None = None
    mtime: float = 0.0
    active: bool = False
    runner_id: str = ""
    # Transkript fayli runner mashinasida (o'chirish uchun; brauzerga chiqarilmaydi).
    path: str = ""


# --- yordamchilar --------------------------------------------------------------------------


def strip_settings_arg(argv: Sequence[str]) -> list[str]:
    """`--settings <json>` (hook'lar va buyruq yo'llari) qiymatini brauzerga chiqarmaslik uchun."""
    out: list[str] = []
    skip_next = False
    for arg in argv:
        if skip_next:
            out.append(HOOKS_PLACEHOLDER)
            skip_next = False
        elif arg == "--settings":
            out.append(arg)
            skip_next = True
        elif arg.startswith("--settings="):
            out.append(f"--settings={HOOKS_PLACEHOLDER}")
        else:
            out.append(arg)
    return out


def is_supported_version(version: str) -> bool:
    return version.startswith(SUPPORTED_VERSION_PREFIX)


def validate_keys(keys: Sequence[str]) -> list[str]:
    if not keys:
        raise ValueError("keys bo'sh")
    for key in keys:
        if key in NAMED_KEYS or _CTRL_KEY_RE.match(key) or (len(key) == 1 and key.isprintable()):
            continue
        raise ValueError(f"ruxsat etilmagan tugma: {key!r}")
    return list(keys)


def _detail(resp: httpx.Response) -> str:
    try:
        data = resp.json()
    except ValueError:
        return resp.text[:200]
    if isinstance(data, dict) and isinstance(data.get("detail"), str):
        return str(data["detail"])
    return ""


# --- client --------------------------------------------------------------------------------


class KanbotClient:
    def __init__(
        self, base_url: str = DEFAULT_KANBOT_URL, http: httpx.AsyncClient | None = None
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self._http = http or httpx.AsyncClient(timeout=DEFAULT_TIMEOUT, trust_env=False)
        self._warned_version: str | None = None

    @property
    def web_socket_url(self) -> str:
        """KanBot'ning brauzer oqimi (`/ws/web`): pane terminallari shu orqali keladi."""
        return "ws" + self.base_url.removeprefix("http") + "/ws/web"

    async def aclose(self) -> None:
        await self._http.aclose()

    async def _request(
        self,
        method: str,
        path: str,
        *,
        json: dict[str, Any] | None = None,
        params: dict[str, Any] | None = None,
        time_limit: httpx.Timeout | None = None,
    ) -> Any:
        label = f"{method} {path}"
        try:
            resp = await self._http.request(
                method,
                f"{self.base_url}{path}",
                json=json,
                params=params,
                timeout=time_limit if time_limit is not None else httpx.USE_CLIENT_DEFAULT,
            )
        except httpx.TransportError as exc:
            raise KanbotUnavailable(f"{label}: {exc or type(exc).__name__}") from exc
        if resp.status_code != 200:
            detail = _detail(resp)
            error = _STATUS_ERRORS.get(resp.status_code, KanbotError)
            raise error(
                f"{label}: HTTP {resp.status_code} {detail}".rstrip(), resp.status_code, detail
            )
        try:
            return resp.json()
        except ValueError as exc:
            raise KanbotError(f"{label}: JSON emas", resp.status_code) from exc

    @staticmethod
    def _items(data: Any, key: str) -> list[Any]:
        items = data.get(key) if isinstance(data, dict) else None
        if not isinstance(items, list):
            raise KanbotError(f"kutilmagan javob: '{key}' ro'yxati yo'q")
        return items

    # -- meta ---------------------------------------------------------------------------

    async def health(self) -> KanbotHealth:
        health = KanbotHealth.model_validate(await self._request("GET", "/api/health"))
        if not health.version_supported and self._warned_version != health.version:
            self._warned_version = health.version
            logger.warning(
                "KanBot %s qo'llab-quvvatlanmaydi (kutilgan %sx)",
                health.version,
                SUPPORTED_VERSION_PREFIX,
            )
        return health

    async def runners(self) -> list[Runner]:
        data = await self._request("GET", "/api/runners")
        return [Runner.model_validate(item) for item in self._items(data, "runners")]

    # -- panes --------------------------------------------------------------------------

    async def list_panes(self) -> list[Pane]:
        data = await self._request("GET", "/api/panes")
        return [Pane.model_validate(item) for item in self._items(data, "panes")]

    async def get_pane(self, pane_id: str) -> Pane:
        return Pane.model_validate(await self._request("GET", f"/api/panes/{_seg(pane_id)}"))

    async def start_pane(
        self,
        agent: AgentName,
        *,
        prompt: str = "",
        cwd: str,
        title: str = "",
        resume: str = "",
        runner_id: str = "",
    ) -> Pane:
        if agent not in SESSION_AGENTS:
            raise ValueError(f"agent faqat {', '.join(SESSION_AGENTS)} bo'lishi mumkin: {agent!r}")
        if not cwd:
            raise ValueError("cwd majburiy")
        body = {
            "agent": agent,
            "prompt": prompt,
            "cwd": cwd,
            "interactive": True,
            "resume": resume,
            "title": title,
            "runner_id": runner_id,
        }
        data = await self._request(
            "POST", "/api/panes/start", json=body, time_limit=RUNNER_CALL_TIMEOUT
        )
        return Pane.model_validate(data)

    async def read_pane(self, pane_id: str, lines: int = 60) -> PaneRead:
        lines = max(1, min(lines, MAX_READ_LINES))
        data = await self._request(
            "GET",
            f"/api/panes/{_seg(pane_id)}/read",
            params={"lines": lines},
            time_limit=RUNNER_CALL_TIMEOUT,
        )
        return PaneRead.model_validate(data)

    async def send_text(self, pane_id: str, text: str, *, enter: bool = True) -> None:
        await self._request(
            "POST", f"/api/panes/{_seg(pane_id)}/input", json={"text": text, "enter": enter}
        )

    async def send_keys(self, pane_id: str, keys: Sequence[str]) -> None:
        body = {"keys": validate_keys(keys)}
        await self._request("POST", f"/api/panes/{_seg(pane_id)}/input", json=body)

    async def kill_pane(self, pane_id: str) -> None:
        await self._request("POST", f"/api/panes/{_seg(pane_id)}/kill")

    async def remove_pane(self, pane_id: str) -> None:
        await self._request("DELETE", f"/api/panes/{_seg(pane_id)}")

    # -- o'tgan sessiyalar --------------------------------------------------------------

    async def list_agent_sessions(self) -> list[AgentSession]:
        data = await self._request("GET", "/api/agent-sessions")
        return [AgentSession.model_validate(item) for item in self._items(data, "sessions")]


_PANE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


def is_valid_pane_id(pane_id: str) -> bool:
    return _PANE_ID_RE.match(pane_id) is not None


def _seg(pane_id: str) -> str:
    """Pane ID URL yo'liga qo'yiladi — faqat xavfsiz belgilar (path traversal yo'q)."""
    if not is_valid_pane_id(pane_id):
        raise ValueError(f"noto'g'ri pane ID: {pane_id!r}")
    return pane_id
