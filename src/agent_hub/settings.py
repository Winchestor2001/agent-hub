"""Ilova sozlamalari: env > ~/.config/agent-hub/config.yaml > default.

`projects_root` — "Loyiha qo'shish" oynasi papka takliflarini qidiradigan joy (~/my-projects).

Host doim `127.0.0.1` — sozlab bo'lmaydi. KanBot manzili ham faqat loopback bo'lishi mumkin.
"""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import yaml

from agent_hub.kanbot_client import DEFAULT_KANBOT_URL
from agent_hub.kanbot_safety import kanbot_config_path

HOST = "127.0.0.1"
DEFAULT_PORT = 8700
LOOPBACK_HOSTNAMES = frozenset({"127.0.0.1", "localhost", "::1"})


class SettingsError(ValueError):
    """Sozlamalarda noto'g'ri qiymat."""


@dataclass(frozen=True)
class Settings:
    config_dir: Path
    port: int = DEFAULT_PORT
    kanbot_url: str = DEFAULT_KANBOT_URL
    kanbot_config: Path = field(default_factory=kanbot_config_path)
    extra_origins: tuple[str, ...] = ()
    home: Path = field(default_factory=Path.home)
    projects_root: Path = field(default_factory=lambda: Path.home() / "my-projects")
    host: str = field(default=HOST, init=False)

    @property
    def projects_file(self) -> Path:
        return self.config_dir / "projects.yaml"

    @classmethod
    def load(cls, env: Mapping[str, str] | None = None) -> Settings:
        environ = dict(os.environ if env is None else env)
        config_dir = Path(
            environ.get("AGENT_HUB_CONFIG_DIR") or Path.home() / ".config" / "agent-hub"
        ).expanduser()
        file_values = _read_config_file(config_dir / "config.yaml")

        port_raw = environ.get("AGENT_HUB_PORT") or file_values.get("port") or DEFAULT_PORT
        url_raw = environ.get("AGENT_HUB_KANBOT_URL") or file_values.get("kanbot_url")
        kanbot_url = str(url_raw or DEFAULT_KANBOT_URL)
        origins = environ.get("AGENT_HUB_EXTRA_ORIGINS", "")
        root_raw = environ.get("AGENT_HUB_PROJECTS_ROOT") or file_values.get("projects_root")
        home = Path.home()
        return cls(
            config_dir=config_dir,
            port=_parse_port(port_raw),
            kanbot_url=_parse_loopback_url(kanbot_url),
            kanbot_config=kanbot_config_path(environ),
            extra_origins=tuple(o.strip() for o in origins.split(",") if o.strip()),
            home=home,
            projects_root=Path(str(root_raw)).expanduser() if root_raw else home / "my-projects",
        )


def _read_config_file(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return {}
    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        raise SettingsError(f"{path}: YAML xato: {exc}") from exc
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise SettingsError(f"{path}: obyekt (mapping) kutilgan")
    return data


def _parse_port(value: object) -> int:
    try:
        port = int(str(value))
    except ValueError as exc:
        raise SettingsError(f"port noto'g'ri: {value!r}") from exc
    if not 1 <= port <= 65535:
        raise SettingsError(f"port noto'g'ri: {value!r}")
    return port


def _parse_loopback_url(url: str) -> str:
    parts = urlsplit(url)
    if parts.scheme != "http" or parts.hostname not in LOOPBACK_HOSTNAMES:
        raise SettingsError(f"kanbot_url faqat loopback http manzil bo'lishi mumkin: {url}")
    return url.rstrip("/")
