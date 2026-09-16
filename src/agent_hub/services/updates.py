"""Agent CLI'larini (claude, codex) Homebrew cask'lari orqali yangilash.

Holat (`status`) arzon buyruqlardan yig'iladi: `brew list --cask --versions` — o'rnatilgan versiya,
`brew outdated --cask --json=v2` — so'nggi versiya. Natija qisqa vaqt keshlanadi, chunki UI uni
davomiy so'rab turadi; yangilash tugagach kesh bekor qilinadi.

Yangilashning o'zi uzoq davom etadi (yuklab olish), shuning uchun u fon vazifasida ishlaydi:
`start()` darhol qaytadi, natija esa `status()` da `running` va `last` bo'lib ko'rinadi. Bir agent
uchun bir vaqtda bitta yangilash.

Buyruqlar ro'yxati qat'iy: foydalanuvchi matni argumentga tushmaydi, faqat shu yerdagi cask nomlari.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import os
import shutil
import time
from collections.abc import Awaitable, Callable, Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

# Agent → cask nomzodlari (birinchi topilgani ishlatiladi).
AGENT_CASKS: dict[str, tuple[str, ...]] = {
    "claude": ("claude-code@latest", "claude-code"),
    "codex": ("codex",),
}
# PATH'da brew bo'lmasa (launchd muhiti) — odatdagi joylar.
BREW_CANDIDATES = ("/opt/homebrew/bin/brew", "/usr/local/bin/brew")

STATUS_TIMEOUT = 60.0
UPDATE_TIMEOUT = 900.0
STATUS_TTL = 60.0
# Xato sababini ko'rsatish uchun brew chiqishining oxiri (UI'da title'da).
OUTPUT_TAIL_LINES = 20
OUTPUT_TAIL_CHARS = 2000


class UpdateError(Exception):
    def __init__(self, code: str, **params: Any) -> None:
        super().__init__(f"{code}: {params}")
        self.code = code
        self.params = params


@dataclass(frozen=True)
class BrewResult:
    returncode: int
    stdout: str
    stderr: str

    @property
    def ok(self) -> bool:
        return self.returncode == 0

    @property
    def output(self) -> str:
        return f"{self.stdout}{self.stderr}"


BrewRunner = Callable[[Sequence[str], float], Awaitable[BrewResult]]


@dataclass(frozen=True)
class LastRun:
    """Oxirgi yangilash natijasi (jarayon tugagandan keyin)."""

    ok: bool
    exit_code: int
    finished_at: float
    output: str


@dataclass(frozen=True)
class AgentUpdate:
    agent: str
    cask: str | None
    installed: str | None
    latest: str | None
    running: bool = False
    last: LastRun | None = None

    @property
    def outdated(self) -> bool:
        return self.latest is not None and self.latest != self.installed


async def run_brew(argv: Sequence[str], time_limit: float) -> BrewResult:
    """brew'ni interaktivsiz ishga tushiradi.

    Topilmasa yoki muddat o'tsa — xato kodli `BrewResult` qaytadi.
    """
    env = {
        **os.environ,
        "NO_COLOR": "1",
        "HOMEBREW_NO_COLOR": "1",
        "HOMEBREW_NO_EMOJI": "1",
        "HOMEBREW_NO_ENV_HINTS": "1",
        # Yangilanish `brew update` bilan alohida qadamda bajariladi.
        "HOMEBREW_NO_AUTO_UPDATE": "1",
    }
    try:
        proc = await asyncio.create_subprocess_exec(
            *argv,
            cwd=Path.home(),
            env=env,
            stdin=asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
    except OSError as exc:
        return BrewResult(-1, "", f"{argv[0]}: {exc}")
    try:
        async with asyncio.timeout(time_limit):
            stdout, stderr = await proc.communicate()
    except TimeoutError:
        proc.kill()
        await proc.wait()
        return BrewResult(-1, "", f"{' '.join(argv)}: {time_limit:.0f} s ichida tugamadi")
    return BrewResult(
        proc.returncode if proc.returncode is not None else -1,
        stdout.decode(errors="replace"),
        stderr.decode(errors="replace"),
    )


def find_brew() -> str | None:
    return shutil.which("brew") or next((path for path in BREW_CANDIDATES if _is_exe(path)), None)


def _is_exe(path: str) -> bool:
    return os.path.isfile(path) and os.access(path, os.X_OK)


def tail(text: str) -> str:
    """Chiqishning oxirgi qatorlari (bo'sh qatorlarsiz)."""
    lines = [line.rstrip() for line in text.splitlines() if line.strip()]
    return "\n".join(lines[-OUTPUT_TAIL_LINES:])[-OUTPUT_TAIL_CHARS:]


def parse_installed(stdout: str) -> dict[str, str]:
    """`brew list --cask --versions`: «token 1.2 1.3» → oxirgi (eng yangi o'rnatilgan) versiya."""
    versions: dict[str, str] = {}
    for line in stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            versions[parts[0]] = parts[-1]
    return versions


def parse_outdated(stdout: str) -> dict[str, str] | None:
    """`brew outdated --cask --json=v2`: cask nomi → mavjud so'nggi versiya.

    JSON o'qilmasa None — buyruq haqiqatan xato ketgan (masalan, tarmoq yo'q).
    Bo'sh lug'at esa «hammasi eng so'nggi versiyada» degani.
    """
    try:
        data = json.loads(stdout)
    except ValueError:
        return None
    casks = data.get("casks") if isinstance(data, dict) else None
    if not isinstance(casks, list):
        return None
    latest: dict[str, str] = {}
    for item in casks:
        if not isinstance(item, dict):
            continue
        name, version = item.get("name"), item.get("current_version")
        if isinstance(name, str) and isinstance(version, str):
            latest[name] = version
    return latest


class UpdateService:
    """Agent CLI'lari versiyalari va `brew upgrade` fon vazifalari."""

    def __init__(
        self,
        runner: BrewRunner = run_brew,
        *,
        brew: str | None,
        agents: dict[str, tuple[str, ...]] | None = None,
        ttl: float = STATUS_TTL,
    ) -> None:
        self._runner = runner
        self._brew = brew
        self._agents = agents if agents is not None else AGENT_CASKS
        self._ttl = ttl
        self._lock = asyncio.Lock()
        self._cache: tuple[float, dict[str, tuple[str | None, str | None]]] | None = None
        self._tasks: dict[str, asyncio.Task[None]] = {}
        self._last: dict[str, LastRun] = {}

    @classmethod
    def detect(cls) -> UpdateService:
        """Haqiqiy brew bilan (topilmasa — yangilash o'chiq)."""
        return cls(brew=find_brew())

    @property
    def brew_available(self) -> bool:
        return self._brew is not None

    @property
    def agents(self) -> tuple[str, ...]:
        return tuple(self._agents)

    def running(self, agent: str) -> bool:
        task = self._tasks.get(agent)
        return task is not None and not task.done()

    async def status(self) -> list[AgentUpdate]:
        versions = await self._versions()
        return [
            AgentUpdate(
                agent=agent,
                cask=cask,
                installed=installed,
                latest=latest,
                running=self.running(agent),
                last=self._last.get(agent),
            )
            for agent, (cask, installed, latest) in (
                (agent, self._entry(agent, versions)) for agent in self._agents
            )
        ]

    async def agent_status(self, agent: str) -> AgentUpdate:
        self._check_agent(agent)
        return next(item for item in await self.status() if item.agent == agent)

    async def start(self, agent: str) -> None:
        """Fon yangilashini boshlaydi. Jarayon tugashini kutmaydi."""
        self._check_agent(agent)
        brew = self._brew
        if brew is None:
            raise UpdateError("brew_missing")
        if self.running(agent):
            raise UpdateError("update_running", agent=agent)
        cask, installed, _ = self._entry(agent, await self._versions())
        if cask is None or installed is None:
            raise UpdateError("update_cask_missing", agent=agent)
        self._last.pop(agent, None)
        self._tasks[agent] = asyncio.create_task(self._upgrade(agent, brew, cask))

    async def wait(self, agent: str) -> None:
        """Agentning fon yangilashi tugashini kutadi (yo'q bo'lsa — darhol qaytadi)."""
        task = self._tasks.get(agent)
        if task is not None:
            await asyncio.shield(task)

    async def close(self) -> None:
        tasks = list(self._tasks.values())
        self._tasks.clear()
        for task in tasks:
            task.cancel()
        for task in tasks:
            with contextlib.suppress(asyncio.CancelledError):
                await task

    # --- ichki ---------------------------------------------------------------------------

    def _check_agent(self, agent: str) -> None:
        if agent not in self._agents:
            raise UpdateError("update_agent_unknown", agent=agent)

    def _entry(
        self, agent: str, versions: dict[str, tuple[str | None, str | None]]
    ) -> tuple[str | None, str | None, str | None]:
        cask, installed, latest = None, None, None
        for candidate in self._agents[agent]:
            found = versions.get(candidate)
            if found is not None:
                cask, (installed, latest) = candidate, found
                break
        # Hech biri o'rnatilmagan bo'lsa ham UI qaysi cask kutilishini ko'rsatsin.
        known = self._agents[agent]
        return (cask or (known[0] if known else None), installed, latest)

    async def _versions(self) -> dict[str, tuple[str | None, str | None]]:
        """Cask → (o'rnatilgan, so'nggi). Kesh eskirgan bo'lsa brew'dan qayta o'qiydi."""
        cached = self._cache
        if cached is not None and time.monotonic() - cached[0] < self._ttl:
            return cached[1]
        async with self._lock:
            # Kutish paytida boshqa so'rov yangilagan bo'lishi mumkin.
            cached = self._cache
            if cached is not None and time.monotonic() - cached[0] < self._ttl:
                return cached[1]
            versions = await self._read_versions()
            self._cache = (time.monotonic(), versions)
            return versions

    async def _read_versions(self) -> dict[str, tuple[str | None, str | None]]:
        brew = self._brew
        if brew is None:
            return {}
        listed = await self._runner([brew, "list", "--cask", "--versions"], STATUS_TIMEOUT)
        if not listed.ok:
            logger.warning("brew list xato (%s): %s", listed.returncode, tail(listed.output))
            return {}
        installed = parse_installed(listed.stdout)
        wanted = [cask for cask in self._all_casks() if cask in installed]
        # None — so'nggi versiya noma'lum (tarmoq yo'q);
        # ro'yxatga tushmagan cask esa eng so'nggi versiyada.
        latest: dict[str, str] | None = None
        if wanted:
            outdated = await self._runner(
                [brew, "outdated", "--cask", "--json=v2", *wanted], STATUS_TIMEOUT
            )
            # Eskirgan paket bo'lsa `brew outdated` 1 qaytaradi, shuning uchun
            # muvaffaqiyat chiqish kodidan emas, JSON o'qilganidan bilinadi.
            latest = parse_outdated(outdated.stdout)
            if latest is None:
                logger.warning(
                    "brew outdated xato (%s): %s", outdated.returncode, tail(outdated.output)
                )
        return {
            cask: (
                installed[cask],
                None if latest is None else latest.get(cask, installed[cask]),
            )
            for cask in wanted
        }

    def _all_casks(self) -> Iterable[str]:
        return (cask for casks in self._agents.values() for cask in casks)

    async def _upgrade(self, agent: str, brew: str, cask: str) -> None:
        output = ""
        try:
            # Cask ta'riflari eskirgan bo'lsa upgrade «yangilanish yo'q» deb qaytadi.
            updated = await self._runner([brew, "update", "--quiet"], UPDATE_TIMEOUT)
            if not updated.ok:
                output += f"brew update ({updated.returncode}):\n{tail(updated.output)}\n"
            result = await self._runner([brew, "upgrade", "--cask", cask], UPDATE_TIMEOUT)
            output += tail(result.output)
            self._last[agent] = LastRun(result.ok, result.returncode, time.time(), tail(output))
            if not result.ok:
                logger.warning("brew upgrade --cask %s xato: %s", cask, tail(result.output))
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # kutilmagan xato natijasiz qolmasin
            logger.exception("%s yangilanmadi", agent)
            self._last[agent] = LastRun(False, -1, time.time(), f"{output}\n{exc}".strip())
        finally:
            self._cache = None
