"""Agent CLI'larini brew orqali yangilash: servis va `/api/updates`."""

from __future__ import annotations

import asyncio
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from agent_hub.app import create_app
from agent_hub.services.updates import (
    BrewResult,
    UpdateError,
    UpdateService,
    parse_installed,
    parse_outdated,
    tail,
)
from agent_hub.settings import Settings

BREW = "/opt/homebrew/bin/brew"
LIST_OUTPUT = "claude-code@latest 2.1.272\ncodex 0.154.0\nfirefox 146.0.1\n"
OUTDATED_JSON = """
{
  "formulae": [],
  "casks": [
    {"name": "claude-code@latest", "installed_versions": ["2.1.272"], "current_version": "2.1.273"}
  ]
}
"""


class FakeBrew:
    """brew o'rniga: buyruqlarni yozib oladi, javobni ichki buyruq nomi bo'yicha beradi."""

    def __init__(self, **replies: BrewResult) -> None:
        self.calls: list[list[str]] = []
        self.replies: dict[str, BrewResult] = {
            "list": BrewResult(0, LIST_OUTPUT, ""),
            "outdated": BrewResult(0, OUTDATED_JSON, ""),
            "update": BrewResult(0, "Already up-to-date.\n", ""),
            "upgrade": BrewResult(0, "==> Upgrading 1 outdated package\n", ""),
            **replies,
        }
        # O'rnatilsa `upgrade` shu hodisagacha kutadi (uzoq yangilashni taqlid qiladi).
        self.gate: asyncio.Event | None = None

    async def __call__(self, argv: Sequence[str], time_limit: float) -> BrewResult:
        self.calls.append(list(argv))
        if self.gate is not None and argv[1] == "upgrade":
            await self.gate.wait()
        return self.replies[argv[1]]

    @property
    def commands(self) -> list[str]:
        return [" ".join(call[1:]) for call in self.calls]


def service(brew: FakeBrew) -> UpdateService:
    return UpdateService(brew, brew=BREW)


# --- parslash ------------------------------------------------------------------------------


def test_parse_installed_takes_last_version() -> None:
    versions = parse_installed("codex 0.153.0 0.154.0\nbroken\nfirefox 146.0.1\n")
    assert versions == {"codex": "0.154.0", "firefox": "146.0.1"}


def test_parse_outdated_reads_current_version() -> None:
    assert parse_outdated(OUTDATED_JSON) == {"claude-code@latest": "2.1.273"}


def test_parse_outdated_survives_bad_json() -> None:
    assert parse_outdated("Error: no such cask") is None
    assert parse_outdated('{"casks": "nope"}') is None
    assert parse_outdated('{"casks": []}') == {}


def test_tail_keeps_last_lines() -> None:
    lines = tail("\n".join(f"line {i}" for i in range(40))).splitlines()
    assert (lines[0], lines[-1]) == ("line 20", "line 39")


# --- holat ---------------------------------------------------------------------------------


async def test_status_reports_versions_and_outdated() -> None:
    brew = FakeBrew()
    items = {item.agent: item for item in await service(brew).status()}
    claude, codex = items["claude"], items["codex"]
    assert (claude.cask, claude.installed, claude.latest) == (
        "claude-code@latest",
        "2.1.272",
        "2.1.273",
    )
    assert claude.outdated
    assert (codex.installed, codex.latest, codex.outdated) == ("0.154.0", "0.154.0", False)
    # `brew outdated` faqat o'rnatilgan cask'lar uchun so'raladi.
    assert brew.commands == [
        "list --cask --versions",
        "outdated --cask --json=v2 claude-code@latest codex",
    ]


async def test_status_is_cached_and_shared() -> None:
    brew = FakeBrew()
    updates = service(brew)
    await asyncio.gather(updates.status(), updates.status())
    await updates.status()
    assert len(brew.calls) == 2  # bitta list + bitta outdated


async def test_status_without_brew() -> None:
    updates = UpdateService(FakeBrew(), brew=None)
    assert not updates.brew_available
    claude = await updates.agent_status("claude")
    assert (claude.cask, claude.installed, claude.latest) == ("claude-code@latest", None, None)


async def test_outdated_exit_code_one_is_not_an_error() -> None:
    """`brew outdated` eskirgan paket topsa 1 qaytaradi — JSON o'qilsa bu xato emas."""
    brew = FakeBrew(outdated=BrewResult(1, OUTDATED_JSON, ""))
    claude = await service(brew).agent_status("claude")
    assert (claude.latest, claude.outdated) == ("2.1.273", True)


async def test_status_without_network_keeps_installed_version() -> None:
    brew = FakeBrew(outdated=BrewResult(1, "", "curl: (6) Could not resolve host\n"))
    claude = await service(brew).agent_status("claude")
    assert (claude.installed, claude.latest, claude.outdated) == ("2.1.272", None, False)


async def test_status_when_cask_not_installed() -> None:
    brew = FakeBrew(list=BrewResult(0, "firefox 146.0.1\n", ""))
    items = {item.agent: item for item in await service(brew).status()}
    assert items["claude"].installed is None
    assert items["codex"].installed is None


# --- yangilash -----------------------------------------------------------------------------


async def test_start_runs_update_then_upgrade() -> None:
    brew = FakeBrew()
    updates = service(brew)
    await updates.start("claude")
    await updates.wait("claude")
    # Holatni so'rash keshni qayta o'qiydi, shuning uchun buyruqlar avval tekshiriladi.
    assert brew.commands[-2:] == ["update --quiet", "upgrade --cask claude-code@latest"]
    claude = await updates.agent_status("claude")
    assert claude.last is not None
    assert (claude.last.ok, claude.last.exit_code) == (True, 0)
    assert "Upgrading" in claude.last.output
    assert not claude.running


async def test_failed_upgrade_is_reported_with_output() -> None:
    brew = FakeBrew(upgrade=BrewResult(1, "", "Error: cask 'codex' is not installed\n"))
    updates = service(brew)
    await updates.start("codex")
    await updates.wait("codex")
    last = (await updates.agent_status("codex")).last
    assert last is not None
    assert (last.ok, last.exit_code) == (False, 1)
    assert "not installed" in last.output


async def test_failed_update_step_does_not_stop_upgrade() -> None:
    brew = FakeBrew(update=BrewResult(1, "", "fatal: unable to access github.com\n"))
    updates = service(brew)
    await updates.start("codex")
    await updates.wait("codex")
    assert brew.commands[-1] == "upgrade --cask codex"
    last = (await updates.agent_status("codex")).last
    assert last is not None and last.ok
    assert "unable to access" in last.output


async def test_second_update_is_rejected_while_running() -> None:
    brew = FakeBrew()
    brew.gate = asyncio.Event()
    updates = service(brew)
    await updates.start("claude")
    await asyncio.sleep(0)  # fon vazifasi boshlansin
    assert (await updates.agent_status("claude")).running
    with pytest.raises(UpdateError) as exc:
        await updates.start("claude")
    assert exc.value.code == "update_running"
    brew.gate.set()
    await updates.wait("claude")


async def test_close_cancels_running_update() -> None:
    brew = FakeBrew()
    brew.gate = asyncio.Event()
    updates = service(brew)
    await updates.start("claude")
    await asyncio.sleep(0)
    await updates.close()
    assert not updates.running("claude")


async def test_start_checks_agent_brew_and_cask() -> None:
    with pytest.raises(UpdateError) as unknown:
        await service(FakeBrew()).start("gemini")
    with pytest.raises(UpdateError) as missing_brew:
        await UpdateService(FakeBrew(), brew=None).start("claude")
    with pytest.raises(UpdateError) as missing_cask:
        await service(FakeBrew(list=BrewResult(0, "firefox 146.0.1\n", ""))).start("claude")
    assert unknown.value.code == "update_agent_unknown"
    assert missing_brew.value.code == "brew_missing"
    assert missing_cask.value.code == "update_cask_missing"


async def test_cache_is_refreshed_after_upgrade() -> None:
    brew = FakeBrew()
    updates = service(brew)
    await updates.status()
    await updates.start("claude")
    await updates.wait("claude")
    brew.replies["list"] = BrewResult(0, "claude-code@latest 2.1.273\ncodex 0.154.0\n", "")
    brew.replies["outdated"] = BrewResult(0, '{"casks": []}', "")
    claude = await updates.agent_status("claude")
    assert (claude.installed, claude.latest, claude.outdated) == ("2.1.273", "2.1.273", False)


# --- API -----------------------------------------------------------------------------------


@dataclass(frozen=True)
class Api:
    client: TestClient
    app: FastAPI
    brew: FakeBrew

    def updates(self) -> dict[str, dict[str, Any]]:
        resp = self.client.get("/api/updates")
        assert resp.status_code == 200
        data: dict[str, Any] = resp.json()
        return {item["agent"]: item for item in data["agents"]}

    def wait(self, agent: str) -> dict[str, Any]:
        """Fon vazifasi TestClient siklida tugashini kutadi."""
        for _ in range(50):
            item = self.updates()[agent]
            if not item["running"] and item["last"] is not None:
                return item
        raise AssertionError(f"{agent}: yangilash tugamadi")


@pytest.fixture
def api(settings: Settings, tmp_path: Path) -> Iterator[Api]:
    app = create_app(settings, tmp_path / "static")
    brew = FakeBrew()
    with TestClient(app) as client:
        app.state.hub.updates = service(brew)
        yield Api(client, app, brew)


def test_get_updates_lists_agents(api: Api) -> None:
    assert api.client.get("/api/updates").json()["brew"] is True
    agents = api.updates()
    assert agents["claude"] == {
        "agent": "claude",
        "cask": "claude-code@latest",
        "installed_version": "2.1.272",
        "latest_version": "2.1.273",
        "outdated": True,
        "running": False,
        "last": None,
    }
    assert agents["codex"]["outdated"] is False


def test_post_update_starts_upgrade(api: Api) -> None:
    resp = api.client.post("/api/updates/codex")
    assert resp.status_code == 202
    assert resp.json()["cask"] == "codex"
    assert api.wait("codex")["last"]["ok"] is True
    assert "upgrade --cask codex" in api.brew.commands


def test_post_unknown_agent_is_404(api: Api) -> None:
    resp = api.client.post("/api/updates/gemini")
    assert resp.status_code == 404
    assert resp.json()["code"] == "update_agent_unknown"


def test_post_without_brew_is_503(api: Api) -> None:
    api.app.state.hub.updates = UpdateService(FakeBrew(), brew=None)
    resp = api.client.post("/api/updates/claude")
    assert resp.status_code == 503
    assert resp.json()["code"] == "brew_missing"
