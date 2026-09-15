from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


def _load_module() -> ModuleType:
    # services.py `render_launchd` ni skript papkasidan import qiladi.
    if str(SCRIPTS) not in sys.path:
        sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location("services", SCRIPTS / "services.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


svc = _load_module()
TARGET = svc.Target()
LABELS = [TARGET.label(s) for s in ("kanbot-server", "kanbot-runner", "backend")]
HEALTH_URL = "http://127.0.0.1:8700/api/health"
PANES_URL = "http://127.0.0.1:8787/api/panes"
RUNNERS_URL = "http://127.0.0.1:8787/api/runners"


class FakeSystem(svc.System):  # type: ignore[misc,name-defined]
    def __init__(self, home: Path) -> None:
        super().__init__(home, 501)
        self.jobs: dict[str, Any] = {}
        self.calls: list[tuple[str, str]] = []
        self.listeners: dict[int, set[int]] = {}
        self.runners: set[int] = set()
        self.responses: dict[str, Any] = {HEALTH_URL: {"ok": True, "problems": []}}
        self.stuck: set[str] = set()
        self.next_pid = 1000

    def job(self, label: str) -> Any:
        return self.jobs.get(label)

    def bootstrap(self, plist: Path) -> None:
        label = plist.name.removesuffix(".plist")
        assert plist.exists()
        self.calls.append(("bootstrap", label))
        self.next_pid += 1
        self.jobs[label] = svc.Job(label, "running", self.next_pid)

    def bootout(self, label: str) -> None:
        self.calls.append(("bootout", label))
        if label not in self.stuck:
            self.jobs.pop(label)

    def enable(self, label: str) -> None:
        self.calls.append(("enable", label))

    def listener_pids(self, port: int) -> set[int]:
        return self.listeners.get(port, set())

    def runner_pids(self) -> set[int]:
        return self.runners

    def get_json(self, url: str) -> Any:
        return self.responses.get(url)

    def sleep(self, seconds: float) -> None:
        pass

    def launchd_calls(self) -> list[tuple[str, str]]:
        return [c for c in self.calls if c[0] != "enable"]


def _rendered(**texts: str) -> dict[str, str]:
    base = {f"{label}.plist": f"<plist>{label}</plist>" for label in LABELS}
    for service, text in texts.items():
        base[f"{TARGET.label(service.replace('_', '-'))}.plist"] = text
    return base


@pytest.fixture
def system(tmp_path: Path) -> FakeSystem:
    return FakeSystem(tmp_path / "home")


def _install(system: FakeSystem, rendered: dict[str, str], **kwargs: Any) -> tuple[int, list[str]]:
    lines: list[str] = []
    code = svc.install(system, TARGET, rendered, out=lines.append, **kwargs)
    return code, lines


def test_fresh_install_writes_and_loads_in_order(system: FakeSystem) -> None:
    rendered = _rendered()
    code, lines = _install(system, rendered)
    assert code == 0
    assert system.launchd_calls() == [("bootstrap", label) for label in LABELS]
    assert ("enable", LABELS[0]) in system.calls
    for name, text in rendered.items():
        assert (system.agents_dir / name).read_text(encoding="utf-8") == text
    assert system.log_dir.is_dir()
    assert not list(system.agents_dir.glob("*.tmp"))
    assert lines[-1] == "Agent Hub: http://127.0.0.1:8700"


def test_second_install_restarts_nothing(system: FakeSystem) -> None:
    _install(system, _rendered())
    pids = {label: job.pid for label, job in system.jobs.items()}
    system.calls.clear()
    code, lines = _install(system, _rendered())
    assert code == 0
    assert system.calls == []
    assert {label: job.pid for label, job in system.jobs.items()} == pids
    assert lines[-1] == "Hammasi o'rnatilgan, hech narsa qayta ishga tushirilmadi."


def test_only_changed_service_is_reloaded(system: FakeSystem) -> None:
    _install(system, _rendered())
    system.calls.clear()
    code, _ = _install(system, _rendered(backend="<plist>new</plist>"))
    assert code == 0
    backend = TARGET.label("backend")
    assert system.launchd_calls() == [("bootout", backend), ("bootstrap", backend)]
    assert (system.agents_dir / f"{backend}.plist").read_text(
        encoding="utf-8"
    ) == "<plist>new</plist>"


def test_unloaded_but_current_plist_is_only_loaded(system: FakeSystem) -> None:
    _install(system, _rendered())
    runner = TARGET.label("kanbot-runner")
    system.jobs.pop(runner)
    system.calls.clear()
    assert _install(system, _rendered())[0] == 0
    assert system.launchd_calls() == [("bootstrap", runner)]


def test_manual_kanbot_blocks_until_force(system: FakeSystem) -> None:
    system.listeners[8787] = {4242}
    code, lines = _install(system, _rendered())
    assert code == svc.EXIT_BLOCKED
    assert any("8787" in line and "4242" in line for line in lines)
    assert system.calls == []
    assert not system.agents_dir.exists()

    code, _ = _install(system, _rendered(), force=True)
    assert code == 0
    assert len(system.launchd_calls()) == 3


def test_manual_runner_and_foreign_backend_port_block(system: FakeSystem) -> None:
    system.runners = {777}
    system.listeners[8700] = {778}
    code, lines = _install(system, _rendered())
    assert code == svc.EXIT_BLOCKED
    assert any("runner" in line and "777" in line for line in lines)
    assert any("8700" in line and "778" in line for line in lines)


def test_own_launchd_processes_are_not_foreign(system: FakeSystem) -> None:
    _install(system, _rendered())
    system.listeners[8787] = {system.jobs[TARGET.label("kanbot-server")].pid}
    system.listeners[8700] = {system.jobs[TARGET.label("backend")].pid}
    system.runners = {system.jobs[TARGET.label("kanbot-runner")].pid}
    system.responses[PANES_URL] = {"panes": [{"id": "p1", "alive": True}]}
    code, lines = _install(system, _rendered())
    assert code == 0
    assert not any(line.startswith("OGOHLANTIRISH") for line in lines)


def test_live_panes_block_kanbot_restart(system: FakeSystem) -> None:
    _install(system, _rendered())
    system.responses[PANES_URL] = {
        "panes": [{"id": "p1", "alive": True}, {"id": "p2", "alive": False}]
    }
    system.calls.clear()
    code, lines = _install(system, _rendered(kanbot_runner="<plist>v2</plist>"))
    assert code == svc.EXIT_BLOCKED
    assert any("1 ta tirik pane" in line for line in lines)
    assert system.calls == []
    # Faqat backend o'zgarsa pane'lar o'lmaydi.
    assert _install(system, _rendered(backend="<plist>v2</plist>"))[0] == 0


def test_bootout_timeout_raises(system: FakeSystem) -> None:
    _install(system, _rendered())
    system.stuck.add(TARGET.label("backend"))
    with pytest.raises(svc.ServiceError, match="to'xtamadi"):
        _install(system, _rendered(backend="<plist>v2</plist>"))


def test_install_reports_unhealthy_backend(system: FakeSystem) -> None:
    system.responses.clear()
    code, lines = _install(system, _rendered())
    assert code == 1
    assert "javob bermadi" in lines[-1]


def test_uninstall_removes_plists_and_keeps_logs(system: FakeSystem) -> None:
    _install(system, _rendered())
    log = system.log_dir / "backend.log"
    log.write_text("log\n", encoding="utf-8")
    system.calls.clear()
    lines: list[str] = []
    assert svc.uninstall(system, TARGET, out=lines.append) == 0
    assert system.launchd_calls() == [("bootout", label) for label in reversed(LABELS)]
    assert system.jobs == {}
    assert list(system.agents_dir.iterdir()) == []
    assert log.exists()

    lines.clear()
    assert svc.uninstall(system, TARGET, out=lines.append) == 0
    assert lines[:3] == [f"{label}: o'rnatilmagan" for label in reversed(LABELS)]


def test_uninstall_with_live_panes_needs_force(system: FakeSystem) -> None:
    _install(system, _rendered())
    system.responses[PANES_URL] = {"panes": [{"id": "p1", "alive": True}]}
    assert svc.uninstall(system, TARGET, out=lambda _: None) == svc.EXIT_BLOCKED
    assert len(system.jobs) == 3
    assert svc.uninstall(system, TARGET, force=True, out=lambda _: None) == 0
    assert system.jobs == {}


def _healthy(system: FakeSystem, auto_approve: bool = False) -> None:
    _install(system, _rendered())
    system.responses[RUNNERS_URL] = {
        "runners": [
            {"id": "r1", "name": "mac", "status": "online", "auto_approve": 0},
            {"id": "r0", "name": "old", "status": "offline", "auto_approve": 1},
        ]
    }
    system.kanbot_config.parent.mkdir(parents=True, exist_ok=True)
    system.kanbot_config.write_text(json.dumps({"auto_approve": auto_approve}), encoding="utf-8")


def _status(system: FakeSystem) -> tuple[int, str]:
    lines: list[str] = []
    code = svc.status(system, TARGET, out=lines.append)
    return code, "\n".join(lines)


def test_status_all_good(system: FakeSystem, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("KANBOT_HOME", raising=False)
    _healthy(system)
    code, text = _status(system)
    assert code == 0, text
    assert "local.agent-hub.backend: running (pid" in text
    assert "Agent Hub health: ok" in text
    assert "1 onlayn (mac)" in text
    assert "auto_approve: config=false, runner=false" in text


def test_status_detects_problems(system: FakeSystem, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("KANBOT_HOME", raising=False)
    _healthy(system, auto_approve=True)
    code, text = _status(system)
    assert code == 1
    assert "config=true" in text and "XATO" in text

    _healthy(system)
    system.responses[RUNNERS_URL]["runners"][1]["status"] = "online"
    code, text = _status(system)
    assert code == 1
    assert "2 onlayn" in text
    assert "runner=true" in text

    _healthy(system)
    system.jobs.pop(TARGET.label("kanbot-runner"))
    system.responses[HEALTH_URL] = {
        "ok": False,
        "problems": [{"severity": "warning", "code": "no_runner"}],
    }
    code, text = _status(system)
    assert code == 1
    assert "local.agent-hub.kanbot-runner: yuklanmagan" in text
    assert "- warning: no_runner" in text

    system.responses.clear()
    code, text = _status(system)
    assert code == 1
    assert "Agent Hub health: javob yo'q" in text
    assert "KanBot javob bermadi" in text


def test_real_system_parses_launchctl_print(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    system = svc.System(tmp_path, 501)
    output = (
        "gui/501/local.agent-hub.backend = {\n\tactive count = 1\n\tstate = running\n\n"
        "\tprogram = /x/python\n\tpid = 4321\n\tendpoints = {\n\t\tstate = active\n\t}\n}\n"
    )

    def fake_run(*args: str) -> subprocess.CompletedProcess[str]:
        assert args[:2] == ("/bin/launchctl", "print")
        if args[2].endswith("missing"):
            return subprocess.CompletedProcess(args, 113, "", "Could not find service")
        return subprocess.CompletedProcess(args, 0, output, "")

    monkeypatch.setattr(system, "_run", fake_run)
    assert system.job("local.agent-hub.backend") == svc.Job(
        "local.agent-hub.backend", "running", 4321
    )
    assert system.job("missing") is None


def test_shell_wrappers_are_valid() -> None:
    for name in ("install-services.sh", "uninstall-services.sh"):
        script = SCRIPTS / name
        assert script.stat().st_mode & 0o111
        subprocess.run(["sh", "-n", str(script)], check=True)


def test_logs_truncate_in_place(system: FakeSystem, tmp_path: Path) -> None:
    lines: list[str] = []
    assert svc.logs_truncate(system, out=lines.append) == 0
    assert lines == [f"Loglar yo'q: {system.log_dir}"]

    system.log_dir.mkdir(parents=True)
    backend = system.log_dir / "backend.log"
    backend.write_bytes(b"x" * 2048)
    (system.log_dir / "kanbot-runner.log").write_text("", encoding="utf-8")
    other = system.log_dir / "notes.txt"
    other.write_text("keep", encoding="utf-8")
    outside = tmp_path / "outside.log"
    outside.write_text("keep", encoding="utf-8")
    (system.log_dir / "link.log").symlink_to(outside)

    # Servis faylni O_APPEND bilan ochiq ushlab turadi: qisqartirishdan keyin ham shu faylga yozadi.
    with backend.open("ab") as service:
        inode = backend.stat().st_ino
        lines.clear()
        assert svc.logs_truncate(system, out=lines.append) == 0
        service.write(b"new\n")
        service.flush()

    assert lines == [
        "backend.log: 2.0 KB → 0",
        "kanbot-runner.log: 0 B → 0",
        "Jami bo'shatildi: 2.0 KB",
    ]
    assert backend.read_bytes() == b"new\n"
    assert backend.stat().st_ino == inode
    assert other.read_text(encoding="utf-8") == "keep"
    assert outside.read_text(encoding="utf-8") == "keep"


def test_logs_truncate_command_is_wired() -> None:
    makefile = (SCRIPTS.parent / "Makefile").read_text(encoding="utf-8")
    assert "\nlogs-truncate:" in makefile
    assert "scripts/services.py logs-truncate" in makefile
