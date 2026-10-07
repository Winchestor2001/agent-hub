"""Claude konfiguratsiyasi uchun tayyor shablonlar va o'zbekcha qo'llanmalar (paket ichida).

Shablondagi `{{name}}` foydalanuvchi tanlagan nom bilan almashtiriladi; nom avval tur katalogi
qoidasidan o'tadi, shuning uchun render qilingan matn ham, yo'l ham xavfsiz.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from agent_hub.services.claude_config import ConfigError, kind_for

TEMPLATES_DIR = Path(__file__).resolve().parents[1] / "templates" / "claude"
GUIDES_DIR = TEMPLATES_DIR / "guides"
PLACEHOLDER = "{{name}}"


@dataclass(frozen=True)
class Template:
    id: str
    kind: str
    # Fixed turlar uchun — fayl nomi; to'plam turlari uchun — taklif qilinadigan nom.
    name: str
    file: str

    def as_dict(self) -> dict[str, Any]:
        return {"id": self.id, "kind": self.kind, "name": self.name}


@dataclass(frozen=True)
class Guide:
    id: str
    kinds: tuple[str, ...]

    @property
    def path(self) -> Path:
        return GUIDES_DIR / f"{self.id}.md"

    def title(self) -> str:
        for line in self.path.read_text(encoding="utf-8").splitlines():
            if line.startswith("# "):
                return line[2:].strip()
        return self.id

    def as_dict(self) -> dict[str, Any]:
        return {"id": self.id, "title": self.title(), "kinds": list(self.kinds)}


TEMPLATES: dict[str, Template] = {
    template.id: template
    for template in (
        Template("skill", "skills", "my-skill", "skill.md"),
        Template("command", "commands", "my-command", "command.md"),
        Template("agent", "agents", "my-agent", "agent.md"),
        Template("rule", "rules", "my-rule", "rule.md"),
        Template("claude-md", "claude_md", "claude-md", "claude-md.md"),
        Template("claude-local-md", "claude_local_md", "claude-local-md", "claude-local-md.md"),
        Template("settings", "settings", "settings", "settings.json"),
        Template("settings-local", "settings", "settings-local", "settings-local.json"),
        Template("settings-hook", "settings", "settings", "settings-hook.json"),
        Template("mcp", "mcp", "mcp", "mcp.json"),
        Template("hook", "hooks", "guard-bash.sh", "hook.sh"),
    )
}

GUIDES: dict[str, Guide] = {
    guide.id: guide
    for guide in (
        Guide("overview", ()),
        Guide("skills", ("skills",)),
        Guide("agents", ("agents",)),
        Guide("commands", ("commands",)),
        Guide("rules", ("rules",)),
        Guide("claude-md", ("claude_md", "claude_local_md")),
        Guide("settings", ("settings",)),
        Guide("hooks", ("hooks",)),
        Guide("mcp", ("mcp",)),
    )
}


def templates() -> list[dict[str, Any]]:
    return [template.as_dict() for template in TEMPLATES.values()]


def render(template_id: str, name: str | None = None) -> dict[str, Any]:
    """Shablon matni; `name` tur qoidasidan o'tib `{{name}}` o'rniga qo'yiladi."""
    template = TEMPLATES.get(template_id)
    if template is None:
        raise ConfigError("config_template_unknown", template=template_id)
    kind = kind_for(template.kind)
    target = name or template.name
    if kind.collection:
        kind.relative("project", target)  # config_name_invalid
    elif target not in kind.fixed:
        raise ConfigError("config_name_invalid", kind=kind.id, name=target)
    content = (TEMPLATES_DIR / template.file).read_text(encoding="utf-8")
    return {**template.as_dict(), "name": target, "content": content.replace(PLACEHOLDER, target)}


def guides() -> list[dict[str, Any]]:
    return [guide.as_dict() for guide in GUIDES.values()]


def guide(guide_id: str) -> dict[str, Any]:
    found = GUIDES.get(guide_id)
    if found is None:
        raise ConfigError("config_guide_unknown", guide=guide_id)
    return {**found.as_dict(), "content": found.path.read_text(encoding="utf-8")}
