"""Shablonlar o'z turi validatsiyasidan o'tadi, qo'llanmalar kerakli qoidalarni tushuntiradi."""

from __future__ import annotations

import json
import subprocess
import zipfile
from pathlib import Path

import pytest

from agent_hub.services import claude_templates
from agent_hub.services.claude_config import (
    KINDS,
    ConfigError,
    kind_for,
    parse_frontmatter,
    validate,
)

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("template_id", list(claude_templates.TEMPLATES))
def test_every_template_passes_its_kind_validation(template_id: str) -> None:
    rendered = claude_templates.render(template_id)
    validate(kind_for(rendered["kind"]), rendered["content"])
    assert claude_templates.PLACEHOLDER not in rendered["content"]


def test_every_kind_has_a_template() -> None:
    assert {t.kind for t in claude_templates.TEMPLATES.values()} == set(KINDS)


def test_render_substitutes_name() -> None:
    rendered = claude_templates.render("skill", "deploy")
    meta = parse_frontmatter(rendered["content"])
    assert meta is not None and meta["name"] == "deploy"
    assert rendered["name"] == "deploy"
    agent = parse_frontmatter(claude_templates.render("agent", "reviewer")["content"])
    assert agent is not None and agent["name"] == "reviewer"


@pytest.mark.parametrize(
    ("template_id", "name"), [("skill", "../x"), ("skill", "Bad"), ("hook", "x.exe"), ("mcp", "x")]
)
def test_render_rejects_bad_names(template_id: str, name: str) -> None:
    with pytest.raises(ConfigError) as exc:
        claude_templates.render(template_id, name)
    assert exc.value.code == "config_name_invalid"


def test_settings_template_can_target_local_file() -> None:
    assert claude_templates.render("settings", "settings-local")["name"] == "settings-local"


def test_unknown_template_and_guide() -> None:
    with pytest.raises(ConfigError) as exc:
        claude_templates.render("nope")
    assert exc.value.code == "config_template_unknown"
    with pytest.raises(ConfigError) as exc:
        claude_templates.guide("../etc")
    assert exc.value.code == "config_guide_unknown"


def test_hook_template_blocks_with_exit_code_2(tmp_path: Path) -> None:
    script = claude_templates.TEMPLATES_DIR / "hook.sh"

    def run(command: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["sh", str(script)],
            input=json.dumps({"tool_input": {"command": command}}),
            capture_output=True,
            text=True,
            check=False,
        )

    assert run("ls -la").returncode == 0
    blocked = run("git push --force origin main")
    assert blocked.returncode == 2
    assert "Bloklandi" in blocked.stderr


def test_guides_cover_every_kind_and_render() -> None:
    covered = {kind for guide in claude_templates.GUIDES.values() for kind in guide.kinds}
    assert covered == set(KINDS)
    for item in claude_templates.guides():
        assert item["title"] != item["id"]
        assert claude_templates.guide(item["id"])["content"].startswith("# ")


def test_guides_explain_scopes_precedence_and_gitignore() -> None:
    skills = claude_templates.guide("skills")["content"]
    for phrase in ("Global skill", "Bitta loyiha", "Bir nechta loyiha", "Personal (global) ustun"):
        assert phrase in skills
    assert "Project (loyiha) ustun" in claude_templates.guide("agents")["content"]
    assert "local > project > user" in claude_templates.guide("settings")["content"]
    claude_md = claude_templates.guide("claude-md")["content"]
    assert "gitignore" in claude_md and "CLAUDE.local.md" in claude_md
    overview = claude_templates.guide("overview")["content"]
    assert "local > project > user" in overview and "Personal (global) ustun" in overview


@pytest.mark.integration
def test_templates_are_in_wheel(tmp_path: Path) -> None:
    subprocess.run(["uv", "build", "--wheel", "-o", str(tmp_path)], cwd=ROOT, check=True)
    [wheel] = tmp_path.glob("*.whl")
    names = set(zipfile.ZipFile(wheel).namelist())
    for template in claude_templates.TEMPLATES.values():
        assert f"agent_hub/templates/claude/{template.file}" in names
    for guide in claude_templates.GUIDES:
        assert f"agent_hub/templates/claude/guides/{guide}.md" in names
