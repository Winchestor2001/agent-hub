from __future__ import annotations

from pathlib import Path

from agent_hub.kanbot_safety import kanbot_config_path


def test_config_path_honors_kanbot_home() -> None:
    assert kanbot_config_path({"KANBOT_HOME": "/x/kb"}) == Path("/x/kb/config.json")


def test_config_path_default() -> None:
    assert kanbot_config_path({}) == Path.home() / ".kanbot" / "config.json"
