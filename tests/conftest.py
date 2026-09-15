from __future__ import annotations

from pathlib import Path

import pytest

from agent_hub.settings import Settings


@pytest.fixture
def settings(tmp_path: Path) -> Settings:
    """Haqiqiy ~/.config va ~/.kanbot ga tegmaydigan sozlamalar."""
    return Settings(
        config_dir=tmp_path / "config",
        kanbot_url="http://127.0.0.1:9",
        kanbot_config=tmp_path / "kanbot" / "config.json",
    )
