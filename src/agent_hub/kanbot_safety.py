"""KanBot xavfsiz sozlanganini tekshirish (faqat o'qish).

* `~/.kanbot/config.json` da `shell`, `glm`, `kimi` o'chirilgan va `auto_approve` o'chiq.
* Ulangan runner'lar bu agentlarni e'lon qilmaydi va auto-approve rejimida emas.
"""

from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Literal

from agent_hub.kanbot_client import SUPPORTED_VERSION_PREFIX, Runner, is_supported_version

FORBIDDEN_AGENTS: tuple[str, ...] = ("shell", "glm", "kimi")

Severity = Literal["error", "warning"]


@dataclass(frozen=True)
class Problem:
    code: str
    severity: Severity
    params: dict[str, Any] = field(default_factory=dict)

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


def kanbot_config_path(env: dict[str, str] | None = None) -> Path:
    environ = env if env is not None else os.environ
    base = environ.get("KANBOT_HOME")
    return (Path(base) if base else Path.home() / ".kanbot") / "config.json"


def _agent_problem(agent: str, **params: Any) -> Problem:
    code = "shell_enabled" if agent == "shell" else "agent_enabled"
    return Problem(code, "error", {"agent": agent, **params})


def check_config(path: Path) -> list[Problem]:
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return [Problem("kanbot_config_missing", "warning", {"path": str(path)})]
    except OSError as exc:
        params = {"path": str(path), "error": str(exc)}
        return [Problem("kanbot_config_unreadable", "error", params)]
    try:
        config = json.loads(raw)
    except ValueError:
        return [Problem("kanbot_config_unreadable", "error", {"path": str(path)})]
    if not isinstance(config, dict):
        return [Problem("kanbot_config_unreadable", "error", {"path": str(path)})]

    problems: list[Problem] = []
    disabled = config.get("disabled_agents") or []
    for agent in FORBIDDEN_AGENTS:
        if agent not in disabled:
            problems.append(_agent_problem(agent, source="config"))
    if config.get("auto_approve", False):
        problems.append(Problem("auto_approve_enabled", "error", {"source": "config"}))
    return problems


def check_version(version: str) -> list[Problem]:
    if is_supported_version(version):
        return []
    params = {"version": version, "supported": f"{SUPPORTED_VERSION_PREFIX}x"}
    return [Problem("kanbot_version_unsupported", "warning", params)]


def check_runners(runners: list[Runner]) -> list[Problem]:
    online = [r for r in runners if r.online]
    if not online:
        return [Problem("no_runner", "warning")]
    problems: list[Problem] = []
    for runner in online:
        for agent in FORBIDDEN_AGENTS:
            if agent in runner.capabilities:
                problems.append(_agent_problem(agent, source="runner", runner=runner.name))
        if runner.auto_approve:
            params = {"source": "runner", "runner": runner.name}
            problems.append(Problem("auto_approve_enabled", "error", params))
    if len(online) > 1:
        problems.append(
            Problem("multiple_runners", "warning", {"runners": [r.name for r in online]})
        )
    return problems
