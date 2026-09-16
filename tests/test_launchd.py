from __future__ import annotations

import importlib.util
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "render_launchd.py"
TOKEN = "kb-secret-token-4f1d"  # noqa: S105 — soxta qiymat


def _load_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("render_launchd", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


rl = _load_module()


def _executable(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/sh\n", encoding="utf-8")
    path.chmod(0o755)
    return path


@pytest.fixture
def machine(tmp_path: Path) -> dict[str, Path]:
    """uv tool kanbot, homebrew CLI'lar va loyiha venv'i bor soxta mashina."""
    home = tmp_path / "home & co"
    venv_bin = home / ".local" / "share" / "uv" / "tools" / "kanbot" / "bin"
    _executable(venv_bin / "kanbot")
    _executable(venv_bin / "python")
    local_bin = home / ".local" / "bin"
    local_bin.mkdir(parents=True)
    (local_bin / "kanbot").symlink_to(venv_bin / "kanbot")
    brew = _executable(tmp_path / "brew" / "bin" / "claude").parent
    repo = tmp_path / "repo"
    _executable(repo / ".venv" / "bin" / "python")
    kanbot_dir = home / ".kanbot"
    kanbot_dir.mkdir()
    (kanbot_dir / "config.json").write_text(f'{{"token": "{TOKEN}"}}', encoding="utf-8")
    return {"home": home, "local_bin": local_bin, "brew": brew, "repo": repo, "venv_bin": venv_bin}


def _context(machine: dict[str, Path], **overrides: Any) -> Any:
    tools = {
        "kanbot": machine["local_bin"] / "kanbot",
        "claude": machine["brew"] / "claude",
        "codex": machine["brew"] / "codex",
    }

    def which(name: str) -> str | None:
        found = tools.get(name)
        return str(found) if found else None

    return rl.discover(home=machine["home"], repo=machine["repo"], which=which, **overrides)


def _plists(ctx: Any) -> dict[str, dict[str, Any]]:
    return {name: plistlib.loads(text.encode()) for name, text in rl.render_all(ctx).items()}


def test_discover_finds_real_paths(machine: dict[str, Path]) -> None:
    ctx = _context(machine)
    rl.check_context(ctx)
    assert ctx.kanbot == machine["local_bin"] / "kanbot"
    assert ctx.kanbot_python == machine["venv_bin"].resolve() / "python"
    assert ctx.backend_python == machine["repo"] / ".venv" / "bin" / "python"
    path = ctx.path.split(":")
    # Topilgan CLI papkalari birinchi, tizim papkalari oxirida; takror yo'q.
    assert path[:2] == [str(machine["local_bin"]), str(machine["brew"])]
    assert path[-4:] == ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    assert len(path) == len(set(path))


def test_path_includes_brew_dir(machine: dict[str, Path], tmp_path: Path) -> None:
    """Backend agent CLI'larini `brew upgrade --cask` bilan yangilaydi — brew PATH'da bo'lsin."""
    brew_dir = _executable(tmp_path / "homebrew" / "bin" / "brew").parent
    tools = {"kanbot": machine["local_bin"] / "kanbot", "brew": brew_dir / "brew"}

    def which(name: str) -> str | None:
        found = tools.get(name)
        return str(found) if found else None

    ctx = rl.discover(home=machine["home"], repo=machine["repo"], which=which)
    assert str(brew_dir) in ctx.path.split(":")


def test_build_path_skips_missing_dirs(tmp_path: Path) -> None:
    path = rl.build_path(
        tmp_path, ["/nope/bin", "/usr/bin"], is_dir=lambda d: d == "/opt/homebrew/bin"
    )
    assert path == "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"


def test_rendered_plists_have_launchd_keys(machine: dict[str, Path]) -> None:
    ctx = _context(machine)
    plists = _plists(ctx)
    assert set(plists) == {
        "local.agent-hub.kanbot-server.plist",
        "local.agent-hub.kanbot-runner.plist",
        "local.agent-hub.backend.plist",
    }
    log_dir = machine["home"] / "Library" / "Logs" / "agent-hub"
    for name, data in plists.items():
        service = name.removeprefix("local.agent-hub.").removesuffix(".plist")
        assert data["Label"] == f"local.agent-hub.{service}"
        assert data["RunAtLoad"] is True
        assert data["KeepAlive"] is True
        assert data["ThrottleInterval"] >= 5
        assert data["ProcessType"] == "Standard"
        assert data["EnvironmentVariables"]["PATH"] == ctx.path
        assert data["StandardOutPath"] == str(log_dir / f"{service}.log")
        assert data["StandardErrorPath"] == str(log_dir / f"{service}.log")
        assert Path(data["WorkingDirectory"]).is_absolute()
        assert Path(data["ProgramArguments"][0]).is_absolute()


def test_service_commands(machine: dict[str, Path]) -> None:
    plists = _plists(_context(machine, agent_hub_port=8701, kanbot_port=8788))
    server = plists["local.agent-hub.kanbot-server.plist"]
    assert server["ProgramArguments"] == [
        str(machine["venv_bin"].resolve() / "python"),
        str(machine["repo"] / "scripts" / "kanbot_guarded_server.py"),
        "--port",
        "8788",
    ]
    runner = plists["local.agent-hub.kanbot-runner.plist"]
    assert runner["ProgramArguments"] == [
        str(machine["local_bin"] / "kanbot"),
        "runner",
        "--safe",
        "--server",
        "http://127.0.0.1:8788",
    ]
    backend = plists["local.agent-hub.backend.plist"]
    assert backend["ProgramArguments"] == [
        str(machine["repo"] / ".venv" / "bin" / "python"),
        "-m",
        "agent_hub",
    ]
    assert backend["WorkingDirectory"] == str(machine["repo"])
    env = backend["EnvironmentVariables"]
    assert env["AGENT_HUB_PORT"] == "8701"
    assert env["AGENT_HUB_KANBOT_URL"] == "http://127.0.0.1:8788"


def test_no_secrets_in_plists(machine: dict[str, Path]) -> None:
    for text in rl.render_all(_context(machine)).values():
        assert TOKEN not in text
        data = plistlib.loads(text.encode())
        for key in data["EnvironmentVariables"]:
            assert not any(word in key.upper() for word in ("TOKEN", "KEY", "SECRET", "PASSWORD"))
        assert "--dangerously" not in text
        assert "auto-approve" not in text.lower()


def test_values_are_xml_escaped(machine: dict[str, Path]) -> None:
    text = rl.render_all(_context(machine))["local.agent-hub.kanbot-runner.plist"]
    assert "home &amp; co" in text
    assert "@" not in text


@pytest.mark.skipif(shutil.which("plutil") is None, reason="plutil faqat macOS'da")
def test_plutil_lint(machine: dict[str, Path], tmp_path: Path) -> None:
    out = tmp_path / "out"
    out.mkdir()
    for name, text in rl.render_all(_context(machine)).items():
        (out / name).write_text(text, encoding="utf-8")
    result = subprocess.run(
        ["plutil", "-lint", *sorted(str(p) for p in out.iterdir())],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.count(": OK") == 3


def test_check_context_rejects_bad_setup(machine: dict[str, Path]) -> None:
    with pytest.raises(rl.RenderError, match="bir xil"):
        rl.check_context(_context(machine, agent_hub_port=8787))
    with pytest.raises(rl.RenderError, match="label"):
        rl.check_context(_context(machine, label_prefix="bad prefix"))
    (machine["repo"] / ".venv" / "bin" / "python").unlink()
    with pytest.raises(rl.RenderError, match="make sync"):
        rl.check_context(_context(machine))


def test_discover_requires_kanbot(machine: dict[str, Path]) -> None:
    with pytest.raises(rl.RenderError, match="kanbot"):
        rl.discover(home=machine["home"], repo=machine["repo"], which=lambda _: None)


def test_unknown_placeholder_fails() -> None:
    with pytest.raises(rl.RenderError, match="@NOPE@"):
        rl.render_template("<plist><string>@NOPE@</string></plist>", {})
