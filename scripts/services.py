"""Agent Hub launchd servislari: `install`, `uninstall`, `status`.

`install` idempotent: `launchd/*.plist.in` render qilinadi va `~/Library/LaunchAgents` dagisi bilan
solishtiriladi — o'zgarmagan va yuklangan job'ga tegilmaydi, yangi yoki o'zgargani qayta yuklanadi.
launchd'dan tashqarida ishlayotgan KanBot (masalan `kanbot up` yoki `make dev-kanbot`), qo'lda
runner yoki qayta ishga tushirish o'ldiradigan tirik pane'lar bo'lsa, `--force` siz to'xtaydi.

`uninstall` job'larni to'xtatib plist'larni o'chiradi, loglar qoladi. `status` job holati, Agent Hub
health, onlayn runner'lar soni va `auto_approve` ni ko'rsatadi; biror narsa noto'g'ri bo'lsa exit 1.

Faqat stdlib: skript loyiha `.venv` python'ida ishlaydi (`scripts/install-services.sh`).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from render_launchd import (
    DEFAULT_AGENT_HUB_PORT,
    DEFAULT_KANBOT_PORT,
    DEFAULT_LABEL_PREFIX,
    SERVICES,
    RenderError,
    check_context,
    discover,
    render_all,
)

LAUNCHCTL = "/bin/launchctl"
LSOF = "/usr/sbin/lsof"
PGREP = "/usr/bin/pgrep"
HTTP_TIMEOUT = 3.0
BOOTOUT_TIMEOUT = 15.0
HEALTH_TIMEOUT = 30.0
EXIT_BLOCKED = 2

_STATE = re.compile(r"^\tstate = (.+)$", re.MULTILINE)
_PID = re.compile(r"^\tpid = (\d+)$", re.MULTILINE)
_NO_PROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class ServiceError(RuntimeError):
    """launchctl buyrug'i bajarilmadi."""


@dataclass(frozen=True)
class Target:
    label_prefix: str = DEFAULT_LABEL_PREFIX
    agent_hub_port: int = DEFAULT_AGENT_HUB_PORT
    kanbot_port: int = DEFAULT_KANBOT_PORT

    def label(self, service: str) -> str:
        return f"{self.label_prefix}.{service}"

    @property
    def kanbot_url(self) -> str:
        return f"http://127.0.0.1:{self.kanbot_port}"

    @property
    def agent_hub_url(self) -> str:
        return f"http://127.0.0.1:{self.agent_hub_port}"


@dataclass(frozen=True)
class Job:
    label: str
    state: str
    pid: int | None


@dataclass(frozen=True)
class Change:
    service: str
    label: str
    path: Path
    text: str
    # unchanged: tegilmaydi; load: fayl bir xil, faqat yuklanadi; install/update: yoziladi.
    action: str
    loaded: bool


class System:
    """launchctl, jarayonlar va loopback HTTP. Testlarda soxtasi bilan almashtiriladi."""

    def __init__(self, home: Path, uid: int) -> None:
        self.home = home
        self.uid = uid

    @property
    def agents_dir(self) -> Path:
        return self.home / "Library" / "LaunchAgents"

    @property
    def log_dir(self) -> Path:
        return self.home / "Library" / "Logs" / "agent-hub"

    @property
    def kanbot_config(self) -> Path:
        base = os.environ.get("KANBOT_HOME")
        return (Path(base) if base else self.home / ".kanbot") / "config.json"

    def _run(self, *args: str) -> subprocess.CompletedProcess[str]:
        # Argumentlar ro'yxat, shell yo'q; buyruqlar absolyut yo'l bilan.
        return subprocess.run(args, capture_output=True, text=True, check=False)  # noqa: S603

    def _launchctl(self, *args: str) -> None:
        result = self._run(LAUNCHCTL, *args)
        if result.returncode != 0:
            output = (result.stderr or result.stdout).strip()
            raise ServiceError(f"launchctl {' '.join(args)}: {output or result.returncode}")

    def job(self, label: str) -> Job | None:
        result = self._run(LAUNCHCTL, "print", f"gui/{self.uid}/{label}")
        if result.returncode != 0:
            return None
        state = _STATE.search(result.stdout)
        pid = _PID.search(result.stdout)
        return Job(
            label, state.group(1) if state else "unknown", int(pid.group(1)) if pid else None
        )

    def bootstrap(self, plist: Path) -> None:
        self._launchctl("bootstrap", f"gui/{self.uid}", str(plist))

    def bootout(self, label: str) -> None:
        self._launchctl("bootout", f"gui/{self.uid}/{label}")

    def enable(self, label: str) -> None:
        self._launchctl("enable", f"gui/{self.uid}/{label}")

    def listener_pids(self, port: int) -> set[int]:
        result = self._run(LSOF, "-nP", f"-tiTCP:{port}", "-sTCP:LISTEN")
        return {int(line) for line in result.stdout.split() if line.isdigit()}

    def runner_pids(self) -> set[int]:
        result = self._run(PGREP, "-f", r"kanbot (runner|up)( |$)")
        return {int(line) for line in result.stdout.split() if line.isdigit()}

    def get_json(self, url: str) -> Any | None:
        """JSON javob yoki ulanib/o'qib bo'lmasa None. Faqat 127.0.0.1 manzillari beriladi."""
        try:
            with _NO_PROXY.open(url, timeout=HTTP_TIMEOUT) as resp:
                return json.loads(resp.read())
        except (OSError, ValueError):
            return None

    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)


Out = Callable[[str], None]


def _wait(system: System, done: Callable[[], bool], timeout: float, step: float = 0.5) -> bool:
    waited = 0.0
    while not done():
        if waited >= timeout:
            return False
        system.sleep(step)
        waited += step
    return True


def _bootout(system: System, label: str) -> None:
    system.bootout(label)
    if not _wait(system, lambda: system.job(label) is None, BOOTOUT_TIMEOUT):
        raise ServiceError(f"{label}: {BOOTOUT_TIMEOUT:.0f} s da to'xtamadi")


def _alive_panes(system: System, target: Target) -> int | None:
    data = system.get_json(f"{target.kanbot_url}/api/panes")
    panes = data.get("panes") if isinstance(data, dict) else None
    if not isinstance(panes, list):
        return None
    return sum(1 for pane in panes if isinstance(pane, dict) and pane.get("alive"))


def plan_changes(system: System, target: Target, rendered: dict[str, str]) -> list[Change]:
    changes: list[Change] = []
    for service in SERVICES:
        label = target.label(service)
        path = system.agents_dir / f"{label}.plist"
        text = rendered[path.name]
        current = path.read_text(encoding="utf-8") if path.exists() else None
        loaded = system.job(label) is not None
        if current == text:
            action = "unchanged" if loaded else "load"
        else:
            action = "update" if current is not None or loaded else "install"
        changes.append(Change(service, label, path, text, action, loaded))
    return changes


def preflight(system: System, target: Target, changes: Sequence[Change]) -> list[str]:
    """`--force` siz o'rnatishni to'xtatadigan holatlar."""
    jobs = {c.service: system.job(c.label) for c in changes}

    def job_pid(service: str) -> int | None:
        job = jobs.get(service)
        return job.pid if job else None

    warnings: list[str] = []
    ports = (
        (target.kanbot_port, "kanbot-server", "KanBot server"),
        (target.agent_hub_port, "backend", "Agent Hub"),
    )
    for port, service, name in ports:
        own = job_pid(service)
        foreign = {pid for pid in system.listener_pids(port) if pid != own}
        if foreign:
            pids = ", ".join(map(str, sorted(foreign)))
            warnings.append(
                f"{port} portini launchd'dan tashqari jarayon egallagan ({name}?): pid {pids}"
            )
    own_runner = job_pid("kanbot-runner")
    manual_runners = {pid for pid in system.runner_pids() if pid != own_runner}
    if manual_runners:
        pids = ", ".join(map(str, sorted(manual_runners)))
        warnings.append(f"qo'lda ishga tushirilgan KanBot runner bor: pid {pids}")

    kanbot_restart = any(
        c.service in ("kanbot-server", "kanbot-runner") and c.action == "update" and c.loaded
        for c in changes
    )
    if kanbot_restart or warnings:
        alive = _alive_panes(system, target)
        if alive:
            warnings.append(
                f"{alive} ta tirik pane bor: KanBot server/runner almashsa ular to'xtaydi"
            )
    return warnings


def install(
    system: System,
    target: Target,
    rendered: dict[str, str],
    *,
    force: bool = False,
    out: Out = print,
) -> int:
    changes = plan_changes(system, target, rendered)
    warnings = preflight(system, target, changes)
    for warning in warnings:
        out(f"OGOHLANTIRISH: {warning}")
    if warnings and not force:
        out("O'rnatish to'xtatildi. Jarayonlarni to'xtating yoki --force bilan davom eting.")
        return EXIT_BLOCKED

    system.log_dir.mkdir(parents=True, exist_ok=True)
    system.agents_dir.mkdir(parents=True, exist_ok=True)
    for change in changes:
        if change.action == "unchanged":
            out(f"{change.label}: o'zgarmagan")
            continue
        if change.loaded:
            _bootout(system, change.label)
        if change.action != "load":
            tmp = change.path.with_name(change.path.name + ".tmp")
            tmp.write_text(change.text, encoding="utf-8")
            tmp.replace(change.path)
        system.enable(change.label)
        system.bootstrap(change.path)
        verb = {"load": "yuklandi", "install": "o'rnatildi", "update": "yangilandi"}[change.action]
        out(f"{change.label}: {verb}")

    if all(c.action == "unchanged" for c in changes):
        out("Hammasi o'rnatilgan, hech narsa qayta ishga tushirilmadi.")
        return 0
    health_url = f"{target.agent_hub_url}/api/health"
    if _wait(system, lambda: system.get_json(health_url) is not None, HEALTH_TIMEOUT):
        out(f"Agent Hub: {target.agent_hub_url}")
        return 0
    out(f"Agent Hub {HEALTH_TIMEOUT:.0f} s ichida javob bermadi: loglar {system.log_dir}")
    return 1


def uninstall(system: System, target: Target, *, force: bool = False, out: Out = print) -> int:
    labels = [target.label(service) for service in reversed(SERVICES)]
    loaded = [label for label in labels if system.job(label) is not None]
    if loaded and not force:
        alive = _alive_panes(system, target)
        if alive:
            out(f"OGOHLANTIRISH: {alive} ta tirik pane bor: servislar to'xtasa ular ham to'xtaydi")
            out("O'chirish to'xtatildi. --force bilan davom eting.")
            return EXIT_BLOCKED
    for label in labels:
        path = system.agents_dir / f"{label}.plist"
        if label in loaded:
            _bootout(system, label)
        removed = path.exists()
        path.unlink(missing_ok=True)
        if label in loaded or removed:
            out(f"{label}: o'chirildi")
        else:
            out(f"{label}: o'rnatilmagan")
    out(f"Loglar qoldi: {system.log_dir}")
    return 0


def _config_auto_approve(path: Path) -> bool | None:
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return bool(config.get("auto_approve", False)) if isinstance(config, dict) else None


def status(system: System, target: Target, *, out: Out = print) -> int:
    ok = True
    out("Servislar:")
    for service in SERVICES:
        label = target.label(service)
        job = system.job(label)
        if job is None:
            ok = False
            installed = (system.agents_dir / f"{label}.plist").exists()
            out(f"  {label}: " + ("yuklanmagan" if installed else "o'rnatilmagan"))
            continue
        running = job.state == "running" and job.pid is not None
        ok &= running
        pid = f" (pid {job.pid})" if job.pid else ""
        out(f"  {label}: {job.state}{pid}")

    health = system.get_json(f"{target.agent_hub_url}/api/health")
    if not isinstance(health, dict):
        ok = False
        out(f"Agent Hub health: javob yo'q ({target.agent_hub_url})")
    else:
        ok &= bool(health.get("ok"))
        out(f"Agent Hub health: {'ok' if health.get('ok') else 'XATO'}")
        for problem in health.get("problems") or []:
            if isinstance(problem, dict):
                params = problem.get("params") or ""
                out(f"  - {problem.get('severity')}: {problem.get('code')} {params}".rstrip())

    runners_data = system.get_json(f"{target.kanbot_url}/api/runners")
    runners = runners_data.get("runners") if isinstance(runners_data, dict) else None
    if not isinstance(runners, list):
        ok = False
        out(f"KanBot runner'lari: KanBot javob bermadi ({target.kanbot_url})")
        runner_auto = False
    else:
        online = [
            r for r in runners if isinstance(r, dict) and r.get("status", "offline") != "offline"
        ]
        ok &= len(online) == 1
        names = ", ".join(str(r.get("name") or r.get("id")) for r in online)
        verdict = "to'g'ri" if len(online) == 1 else "XATO: aynan 1 ta bo'lishi kerak"
        out(f"KanBot runner'lari: {len(online)} onlayn{f' ({names})' if names else ''} — {verdict}")
        runner_auto = any(bool(r.get("auto_approve")) for r in online)

    config_auto = _config_auto_approve(system.kanbot_config)
    auto_ok = config_auto is False and not runner_auto
    ok &= auto_ok
    config_text = "noma'lum (config o'qilmadi)" if config_auto is None else str(config_auto).lower()
    out(
        f"auto_approve: config={config_text}, runner={str(runner_auto).lower()}"
        f"{'' if auto_ok else ' — XATO'}"
    )
    out(f"Loglar: {system.log_dir}")
    return 0 if ok else 1


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Agent Hub launchd servislari")
    parser.add_argument("command", choices=("install", "uninstall", "status"))
    parser.add_argument(
        "--force", action="store_true", help="ogohlantirishlarga qaramay davom etish"
    )
    parser.add_argument("--agent-hub-port", type=int, default=DEFAULT_AGENT_HUB_PORT)
    parser.add_argument("--kanbot-port", type=int, default=DEFAULT_KANBOT_PORT)
    parser.add_argument("--label-prefix", default=DEFAULT_LABEL_PREFIX)
    args = parser.parse_args(argv)
    target = Target(args.label_prefix, args.agent_hub_port, args.kanbot_port)
    system = System(Path.home(), os.getuid())
    try:
        if args.command == "status":
            return status(system, target)
        if args.command == "uninstall":
            return uninstall(system, target, force=args.force)
        ctx = discover(
            agent_hub_port=target.agent_hub_port,
            kanbot_port=target.kanbot_port,
            label_prefix=target.label_prefix,
        )
        check_context(ctx)
        return install(system, target, render_all(ctx), force=args.force)
    except (RenderError, ServiceError) as exc:
        print(f"services {args.command}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
