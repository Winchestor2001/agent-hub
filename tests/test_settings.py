from __future__ import annotations

from pathlib import Path

import pytest

from agent_hub.settings import DEFAULT_PORT, HOST, Settings, SettingsError


def _env(tmp_path: Path, **extra: str) -> dict[str, str]:
    return {"AGENT_HUB_CONFIG_DIR": str(tmp_path), "KANBOT_HOME": str(tmp_path / "kb"), **extra}


def test_defaults(tmp_path: Path) -> None:
    settings = Settings.load(_env(tmp_path))
    assert settings.host == HOST == "127.0.0.1"
    assert settings.port == DEFAULT_PORT == 8700
    assert settings.kanbot_url == "http://127.0.0.1:8787"
    assert settings.projects_file == tmp_path / "projects.yaml"
    assert settings.kanbot_config == tmp_path / "kb" / "config.json"
    assert settings.extra_origins == ()


def test_default_config_dir() -> None:
    settings = Settings.load({})
    assert settings.config_dir == Path.home() / ".config" / "agent-hub"


def test_config_file_and_env_precedence(tmp_path: Path) -> None:
    (tmp_path / "config.yaml").write_text("port: 8711\nkanbot_url: http://localhost:8788/\n")
    settings = Settings.load(_env(tmp_path))
    assert settings.port == 8711
    assert settings.kanbot_url == "http://localhost:8788"
    settings = Settings.load(_env(tmp_path, AGENT_HUB_PORT="8712"))
    assert settings.port == 8712


def test_extra_origins(tmp_path: Path) -> None:
    env = _env(tmp_path, AGENT_HUB_EXTRA_ORIGINS=" http://127.0.0.1:5173, ,http://localhost:5173")
    settings = Settings.load(env)
    assert settings.extra_origins == ("http://127.0.0.1:5173", "http://localhost:5173")


@pytest.mark.parametrize("port", ["0", "70000", "abc"])
def test_invalid_port(tmp_path: Path, port: str) -> None:
    with pytest.raises(SettingsError):
        Settings.load(_env(tmp_path, AGENT_HUB_PORT=port))


@pytest.mark.parametrize(
    "url", ["http://example.com:8787", "https://127.0.0.1:8787", "http://192.168.1.5:8787"]
)
def test_kanbot_url_must_be_loopback(tmp_path: Path, url: str) -> None:
    with pytest.raises(SettingsError):
        Settings.load(_env(tmp_path, AGENT_HUB_KANBOT_URL=url))


@pytest.mark.parametrize("content", ["port: [", "- 1\n- 2\n"])
def test_invalid_config_file(tmp_path: Path, content: str) -> None:
    (tmp_path / "config.yaml").write_text(content)
    with pytest.raises(SettingsError):
        Settings.load(_env(tmp_path))


def test_projects_root(tmp_path: Path) -> None:
    assert Settings.load(_env(tmp_path)).projects_root == Path.home() / "my-projects"
    (tmp_path / "config.yaml").write_text("projects_root: ~/code\n")
    assert Settings.load(_env(tmp_path)).projects_root == Path.home() / "code"
    env = _env(tmp_path, AGENT_HUB_PROJECTS_ROOT=str(tmp_path / "src"))
    assert Settings.load(env).projects_root == tmp_path / "src"
