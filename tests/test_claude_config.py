"""Claude konfiguratsiya servisi: yo'l xavfsizligi, atomar yozish, etag, zaxira va validatsiya."""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

from agent_hub.registry import Project
from agent_hub.services import claude_config
from agent_hub.services.claude_config import ClaudeConfigService, ConfigError, etag_of

SKILL = "---\nname: deploy\ndescription: Deploy qilish\n---\n\nQadamlar.\n"
AGENT = "---\nname: reviewer\ndescription: Kod ko'rib chiquvchi\n---\n\nSen reviewer'san.\n"


@pytest.fixture
def home(tmp_path: Path) -> Path:
    return tmp_path / "claude-home"


@pytest.fixture
def project(tmp_path: Path) -> Project:
    root = tmp_path / "proj"
    extra = tmp_path / "proj-web"
    root.mkdir()
    extra.mkdir()
    return Project(id="proj", name="Proj", backlog_dir=root, repos=(extra,))


@pytest.fixture
def service(tmp_path: Path, home: Path, project: Project) -> ClaudeConfigService:
    return ClaudeConfigService(home, tmp_path / "backups", lambda: [project])


def code_of(exc: pytest.ExceptionInfo[ConfigError]) -> str:
    return exc.value.code


# --- Qamrovlar va yo'llar -----------------------------------------------------------------


def test_scopes_cover_global_and_every_project_dir(
    service: ClaudeConfigService, project: Project
) -> None:
    scopes = {scope.id: scope for scope in service.scopes()}
    assert list(scopes) == ["global", "project:proj", "project:proj:1"]
    assert scopes["project:proj:1"].root == project.repos[0]
    with pytest.raises(ConfigError) as exc:
        service.scope("project:nope")
    assert code_of(exc) == "config_scope_unknown"
    with pytest.raises(ConfigError):
        service.scope("/etc")


@pytest.mark.parametrize(
    ("scope", "kind", "name", "expected"),
    [
        ("global", "claude_md", "claude-md", "CLAUDE.md"),
        ("global", "settings", "settings", "settings.json"),
        ("global", "skills", "deploy", "skills/deploy/SKILL.md"),
        ("global", "hooks", "guard.sh", "hooks/guard.sh"),
        ("project:proj", "claude_md", "claude-md", "CLAUDE.md"),
        ("project:proj", "claude_local_md", "claude-local-md", "CLAUDE.local.md"),
        ("project:proj", "mcp", "mcp", ".mcp.json"),
        ("project:proj", "settings", "settings-local", ".claude/settings.local.json"),
        ("project:proj", "rules", "style", ".claude/rules/style.md"),
        ("project:proj", "commands", "ship", ".claude/commands/ship.md"),
        ("project:proj", "agents", "reviewer", ".claude/agents/reviewer.md"),
        ("project:proj", "hooks", "check.py", ".claude/hooks/check.py"),
    ],
)
def test_paths_come_from_catalog(
    service: ClaudeConfigService, scope: str, kind: str, name: str, expected: str
) -> None:
    assert service.read(scope, kind, name)["path"] == expected


@pytest.mark.parametrize(
    "name",
    ["../x", "..", "a/b", "/etc/passwd", "Upper", "-dash", "a.md", "x" * 65, "", "a b", "a\x00"],
)
def test_name_outside_regex_is_rejected(service: ClaudeConfigService, name: str) -> None:
    with pytest.raises(ConfigError) as exc:
        service.write("project:proj", "rules", name, "# r\n", None)
    assert code_of(exc) == "config_name_invalid"


@pytest.mark.parametrize("name", ["guard", "guard.exe", "../guard.sh", "guard.sh.sh"])
def test_hook_needs_known_extension(service: ClaudeConfigService, name: str) -> None:
    with pytest.raises(ConfigError) as exc:
        service.write("project:proj", "hooks", name, "#!/bin/sh\n", None)
    assert code_of(exc) == "config_name_invalid"


def test_kind_not_available_in_scope(service: ClaudeConfigService) -> None:
    for kind, name in (("mcp", "mcp"), ("claude_local_md", "claude-local-md")):
        with pytest.raises(ConfigError) as exc:
            service.read("global", kind, name)
        assert code_of(exc) == "config_kind_scope"
    with pytest.raises(ConfigError) as exc:
        service.read("project:proj", "settings", "other")
    assert code_of(exc) == "config_name_invalid"


def test_symlinked_folder_is_not_followed(
    service: ClaudeConfigService, project: Project, tmp_path: Path
) -> None:
    outside = tmp_path / "outside"
    outside.mkdir()
    (project.backlog_dir / ".claude").symlink_to(outside)
    with pytest.raises(ConfigError) as exc:
        service.write("project:proj", "rules", "style", "# r\n", None)
    assert code_of(exc) == "config_symlink"
    assert list(outside.iterdir()) == []


def test_symlinked_file_is_not_overwritten(
    service: ClaudeConfigService, project: Project, tmp_path: Path
) -> None:
    secret = tmp_path / "secret.md"
    secret.write_text("sir")
    (project.backlog_dir / "CLAUDE.md").symlink_to(secret)
    with pytest.raises(ConfigError) as exc:
        service.read("project:proj", "claude_md", "claude-md")
    assert code_of(exc) == "config_symlink"
    with pytest.raises(ConfigError):
        service.write("project:proj", "claude_md", "claude-md", "yangi", etag_of(b"sir"))
    assert secret.read_text() == "sir"
    items = service.list_items("project:proj", "claude_md")["items"]
    assert items[0]["symlink"] is True


# --- Yozish, etag, rejim, zaxira ------------------------------------------------------------


def test_create_read_update_delete_roundtrip(service: ClaudeConfigService, tmp_path: Path) -> None:
    created = service.write("project:proj", "agents", "reviewer", AGENT, None)
    assert created["created"] is True and created["backup"] is None
    read = service.read("project:proj", "agents", "reviewer")
    assert read["content"] == AGENT
    assert read["etag"] == created["etag"] == etag_of(AGENT.encode())

    updated = service.write("project:proj", "agents", "reviewer", AGENT + "Yana.\n", read["etag"])
    assert updated["created"] is False
    backup = Path(updated["backup"])
    assert backup.parent == tmp_path / "backups"
    assert backup.read_text() == AGENT
    assert stat.S_IMODE(backup.stat().st_mode) == 0o600

    deleted = service.delete("project:proj", "agents", "reviewer", updated["etag"])
    assert Path(deleted["backup"]).read_text() == AGENT + "Yana.\n"
    assert service.read("project:proj", "agents", "reviewer")["exists"] is False


def test_create_refuses_existing_file(service: ClaudeConfigService) -> None:
    service.write("project:proj", "rules", "style", "# a\n", None)
    with pytest.raises(ConfigError) as exc:
        service.write("project:proj", "rules", "style", "# b\n", None)
    assert code_of(exc) == "config_exists"
    assert service.read("project:proj", "rules", "style")["content"] == "# a\n"


def test_stale_etag_conflicts(service: ClaudeConfigService, project: Project) -> None:
    first = service.write("project:proj", "rules", "style", "# a\n", None)
    # Boshqa joyda (masalan, muharrirda) o'zgartirildi.
    (project.backlog_dir / ".claude" / "rules" / "style.md").write_text("# tashqi\n")
    with pytest.raises(ConfigError) as exc:
        service.write("project:proj", "rules", "style", "# b\n", first["etag"])
    assert code_of(exc) == "config_conflict"
    with pytest.raises(ConfigError) as exc:
        service.delete("project:proj", "rules", "style", first["etag"])
    assert code_of(exc) == "config_conflict"
    assert service.read("project:proj", "rules", "style")["content"] == "# tashqi\n"


def test_update_of_missing_file_is_not_found(service: ClaudeConfigService) -> None:
    with pytest.raises(ConfigError) as exc:
        service.write("project:proj", "rules", "style", "# b\n", "0" * 64)
    assert code_of(exc) == "config_not_found"


def test_new_file_modes(service: ClaudeConfigService, home: Path, project: Project) -> None:
    service.write("global", "settings", "settings", "{}", None)
    service.write("project:proj", "hooks", "guard.sh", "#!/bin/sh\nexit 0\n", None)
    service.write("project:proj", "rules", "style", "# r\n", None)
    assert stat.S_IMODE((home / "settings.json").stat().st_mode) == 0o600
    hook = project.backlog_dir / ".claude" / "hooks" / "guard.sh"
    assert stat.S_IMODE(hook.stat().st_mode) == 0o755
    rule = project.backlog_dir / ".claude" / "rules" / "style.md"
    assert stat.S_IMODE(rule.stat().st_mode) == 0o644


def test_existing_mode_is_preserved(service: ClaudeConfigService, project: Project) -> None:
    hook = project.backlog_dir / ".claude" / "hooks" / "guard.sh"
    hook.parent.mkdir(parents=True)
    hook.write_text("#!/bin/sh\n")
    os.chmod(hook, 0o700)
    service.write(
        "project:proj", "hooks", "guard.sh", "#!/bin/sh\nexit 1\n", etag_of(b"#!/bin/sh\n")
    )
    assert stat.S_IMODE(hook.stat().st_mode) == 0o700
    assert hook.read_text() == "#!/bin/sh\nexit 1\n"


def test_failed_write_keeps_old_file_and_leaves_no_temp(
    service: ClaudeConfigService, project: Project, monkeypatch: pytest.MonkeyPatch
) -> None:
    first = service.write("project:proj", "rules", "style", "# a\n", None)

    def boom(src: object, dst: object) -> None:
        raise OSError("disk full")

    monkeypatch.setattr(os, "replace", boom)
    with pytest.raises(OSError, match="disk full"):
        service.write("project:proj", "rules", "style", "# b\n", first["etag"])
    folder = project.backlog_dir / ".claude" / "rules"
    assert [p.name for p in folder.iterdir()] == ["style.md"]
    assert (folder / "style.md").read_text() == "# a\n"


def test_skill_delete_keeps_folder_with_other_files(
    service: ClaudeConfigService, home: Path
) -> None:
    created = service.write("global", "skills", "deploy", SKILL, None)
    (home / "skills" / "deploy" / "run.sh").write_text("echo\n")
    service.delete("global", "skills", "deploy", created["etag"])
    assert (home / "skills" / "deploy" / "run.sh").exists()
    again = service.write("global", "skills", "deploy", SKILL, None)
    (home / "skills" / "deploy" / "run.sh").unlink()
    service.delete("global", "skills", "deploy", again["etag"])
    assert not (home / "skills" / "deploy").exists()


# --- Validatsiya ----------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("kind", "name", "content", "code"),
    [
        ("settings", "settings", "{oops", "config_json_invalid"),
        ("settings", "settings", "[]", "config_json_not_object"),
        ("settings", "settings", '{"hooks": []}', "config_settings_hooks_invalid"),
        ("mcp", "mcp", '{"mcpServers": []}', "config_mcp_invalid"),
        ("skills", "deploy", "Faqat matn", "config_frontmatter_missing"),
        ("skills", "deploy", "---\nname: deploy\n---\n", "config_frontmatter_field"),
        ("agents", "reviewer", "---\ndescription: x\n---\n", "config_frontmatter_field"),
        ("commands", "ship", "---\n: [\n---\n", "config_frontmatter_invalid"),
        ("commands", "ship", "---\n- a\n---\n", "config_frontmatter_invalid"),
        ("rules", "style", "---\npaths: x\n", "config_frontmatter_invalid"),
        ("rules", "style", "x" * (claude_config.MAX_SIZE + 1), "config_too_large"),
        ("rules", "style", "a\x00b", "config_not_text"),
    ],
)
def test_validation_codes(
    service: ClaudeConfigService, kind: str, name: str, content: str, code: str
) -> None:
    with pytest.raises(ConfigError) as exc:
        service.write("project:proj", kind, name, content, None)
    assert code_of(exc) == code


def test_valid_contents_pass(service: ClaudeConfigService) -> None:
    service.write("project:proj", "mcp", "mcp", '{"mcpServers": {}}', None)
    service.write("project:proj", "commands", "ship", "Frontmatter'siz buyruq\n", None)
    service.write("project:proj", "rules", "api", "---\npaths:\n  - src/**\n---\n# API\n", None)
    service.write("project:proj", "skills", "deploy", SKILL, None)


def test_json_error_has_position(service: ClaudeConfigService) -> None:
    with pytest.raises(ConfigError) as exc:
        service.write("project:proj", "settings", "settings", '{\n  "a": 1,\n}', None)
    assert exc.value.params["line"] == 3


# --- Ro'yxat, shadowing, apply --------------------------------------------------------------


def test_list_collection_skips_bad_names(service: ClaudeConfigService, home: Path) -> None:
    service.write("global", "skills", "deploy", SKILL, None)
    (home / "skills" / "Bad_Name").mkdir()
    (home / "skills" / "Bad_Name" / "SKILL.md").write_text(SKILL)
    (home / "skills" / "no-skill-file").mkdir()
    listing = service.list_items("global", "skills")
    assert [item["name"] for item in listing["items"]] == ["deploy"]
    assert listing["skipped"] == ["Bad_Name"]
    assert listing["items"][0]["exists"] is True


def test_list_fixed_kind_shows_missing_files(service: ClaudeConfigService) -> None:
    items = service.list_items("project:proj", "settings")["items"]
    assert [(i["name"], i["exists"]) for i in items] == [
        ("settings", False),
        ("settings-local", False),
    ]
    hooks = service.list_items("project:proj", "hooks")
    assert hooks == {"items": [], "skipped": []}


def test_shadowing_skill_global_wins_agent_project_wins(service: ClaudeConfigService) -> None:
    service.write("global", "skills", "deploy", SKILL, None)
    service.write("project:proj", "skills", "deploy", SKILL, None)
    service.write("global", "agents", "reviewer", AGENT, None)
    service.write("project:proj", "agents", "reviewer", AGENT, None)
    service.write("project:proj", "agents", "solo", AGENT.replace("reviewer", "solo"), None)

    [project_skill] = service.list_items("project:proj", "skills")["items"]
    assert project_skill["shadow"] == [{"scope": "global", "winner": "other"}]
    [global_skill] = service.list_items("global", "skills")["items"]
    assert global_skill["shadow"] == [{"scope": "project:proj", "winner": "this"}]

    agents = {i["name"]: i for i in service.list_items("project:proj", "agents")["items"]}
    assert agents["reviewer"]["shadow"] == [{"scope": "global", "winner": "this"}]
    assert agents["solo"]["shadow"] == []
    [global_agent] = service.list_items("global", "agents")["items"]
    assert global_agent["shadow"] == [{"scope": "project:proj", "winner": "other"}]


def test_apply_to_many_scopes_reports_each(service: ClaudeConfigService, project: Project) -> None:
    service.write("project:proj:1", "skills", "deploy", SKILL.replace("Qadamlar", "Eski"), None)
    results = service.apply(
        "skills",
        "deploy",
        SKILL,
        ["global", "project:proj", "project:proj:1", "project:x"],
        overwrite=False,
    )
    by_scope = {r["scope"]: r for r in results}
    assert by_scope["global"]["status"] == "created"
    assert by_scope["project:proj"]["status"] == "created"
    assert by_scope["project:proj:1"]["error"]["code"] == "config_exists"
    assert by_scope["project:x"]["error"]["code"] == "config_scope_unknown"
    assert (project.backlog_dir / ".claude" / "skills" / "deploy" / "SKILL.md").read_text() == SKILL

    again = service.apply("skills", "deploy", SKILL, ["global", "project:proj:1"], overwrite=True)
    assert [r["status"] for r in again] == ["unchanged", "updated"]
    assert again[1]["backup"]


def test_apply_validates_once(service: ClaudeConfigService) -> None:
    with pytest.raises(ConfigError) as exc:
        service.apply("skills", "deploy", "matn", ["global"], overwrite=False)
    assert code_of(exc) == "config_frontmatter_missing"
    with pytest.raises(ConfigError):
        service.apply("skills", "../x", SKILL, ["global"], overwrite=False)


def test_global_home_is_created_on_first_write(service: ClaudeConfigService, home: Path) -> None:
    assert not home.exists()
    assert service.list_items("global", "skills") == {"items": [], "skipped": []}
    service.write("global", "claude_md", "claude-md", "# Global\n", None)
    assert (home / "CLAUDE.md").read_text() == "# Global\n"


def test_local_md_gitignore_warning(service: ClaudeConfigService, project: Project) -> None:
    git = shutil.which("git")
    if git is None:
        pytest.skip("git yo'q")
    service.write("project:proj", "claude_local_md", "claude-local-md", "# local\n", None)
    # Repo emas — ogohlantirish yo'q (aniqlab bo'lmaydi).
    assert service.read("project:proj", "claude_local_md", "claude-local-md")["warnings"] == []
    subprocess.run([git, "init", "-q", str(project.backlog_dir)], check=True)
    read = service.read("project:proj", "claude_local_md", "claude-local-md")
    assert read["warnings"] == ["local_not_ignored"]
    (project.backlog_dir / ".gitignore").write_text("CLAUDE.local.md\n")
    assert service.read("project:proj", "claude_local_md", "claude-local-md")["warnings"] == []
