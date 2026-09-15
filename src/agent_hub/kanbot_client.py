"""KanBot HTTP API'ga yagona kirish nuqtasi.

Hozircha faqat health va runner'lar; qolgan metodlar TASK-5 da qo'shiladi.
"""

from __future__ import annotations

from typing import Any

import httpx
from pydantic import BaseModel, ConfigDict, Field, field_validator

DEFAULT_KANBOT_URL = "http://127.0.0.1:8787"
DEFAULT_TIMEOUT = httpx.Timeout(5.0, connect=1.0)


class KanbotError(Exception):
    """KanBot kutilmagan javob qaytardi."""


class KanbotUnavailable(KanbotError):
    """KanBot serveriga ulanib bo'lmadi."""


class _Model(BaseModel):
    model_config = ConfigDict(extra="ignore")


class KanbotHealth(_Model):
    ok: bool
    version: str
    runners: int = 0


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


class KanbotClient:
    def __init__(
        self, base_url: str = DEFAULT_KANBOT_URL, http: httpx.AsyncClient | None = None
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self._http = http or httpx.AsyncClient(timeout=DEFAULT_TIMEOUT, trust_env=False)

    async def aclose(self) -> None:
        await self._http.aclose()

    async def _get(self, path: str) -> Any:
        try:
            resp = await self._http.get(f"{self.base_url}{path}")
        except httpx.TransportError as exc:
            raise KanbotUnavailable(str(exc) or type(exc).__name__) from exc
        if resp.status_code != 200:
            raise KanbotError(f"GET {path}: HTTP {resp.status_code}")
        try:
            return resp.json()
        except ValueError as exc:
            raise KanbotError(f"GET {path}: JSON emas") from exc

    async def health(self) -> KanbotHealth:
        return KanbotHealth.model_validate(await self._get("/api/health"))

    async def runners(self) -> list[Runner]:
        data = await self._get("/api/runners")
        return [Runner.model_validate(item) for item in data.get("runners", [])]
