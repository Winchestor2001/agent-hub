from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from agent_hub.registry import Project, Registry, RegistryError, validate_project


def _backlog_project(root: Path, name: str, layout: str = ".backlog/config.yml") -> Path:
    directory = root / name
    (directory / layout).parent.mkdir(parents=True, exist_ok=True)
    (directory / layout).write_text("project_name: x\n")
    return directory


def test_creates_default_leveling(tmp_path: Path) -> None:
    path = tmp_path / "cfg" / "projects.yaml"
    projects = Registry(path).load()
    assert [p.id for p in projects] == ["leveling"]
    leveling = projects[0]
    assert leveling.name == "Leveling"
    assert leveling.backlog_dir == Path.home() / "my-projects" / "leveling-backend"
    assert leveling.repos == ()
    assert leveling.dirs == (leveling.backlog_dir,)
    saved = yaml.safe_load(path.read_text())
    assert saved["projects"][0]["backlog_dir"] == str(leveling.backlog_dir)
    assert not list(path.parent.glob(".projects-*"))


def test_existing_file_not_overwritten(tmp_path: Path) -> None:
    path = tmp_path / "projects.yaml"
    path.write_text("projects: []\n")
    assert Registry(path).load() == []
    assert path.read_text() == "projects: []\n"


@pytest.mark.parametrize(
    "layout", [".backlog/config.yml", "backlog/config.yml", "backlog.config.yml"]
)
def test_validate_backlog_layouts(tmp_path: Path, layout: str) -> None:
    directory = _backlog_project(tmp_path, "proj", layout)
    project = validate_project("proj", " Proj ", directory)
    assert project.name == "Proj"
    assert project.repos == ()
    assert project.dirs == (directory,)


def test_validate_path_invalid(tmp_path: Path) -> None:
    with pytest.raises(RegistryError) as exc:
        validate_project("x", "X", tmp_path / "missing")
    assert exc.value.code == "path_invalid"
    (tmp_path / "file").write_text("")
    with pytest.raises(RegistryError) as exc:
        validate_project("x", "X", tmp_path / "file")
    assert exc.value.code == "path_invalid"


def test_validate_backlog_not_found(tmp_path: Path) -> None:
    (tmp_path / "plain").mkdir()
    with pytest.raises(RegistryError) as exc:
        validate_project("x", "X", tmp_path / "plain")
    assert exc.value.code == "backlog_not_found"
    assert exc.value.params == {"path": str(tmp_path / "plain")}


def test_validate_repo_path_invalid(tmp_path: Path) -> None:
    directory = _backlog_project(tmp_path, "proj")
    with pytest.raises(RegistryError) as exc:
        validate_project("proj", "P", directory, [tmp_path / "nope"])
    assert exc.value.code == "path_invalid"


@pytest.mark.parametrize("project_id", ["", "Bad", "a b", "-x", "a" * 41])
def test_validate_project_id(tmp_path: Path, project_id: str) -> None:
    directory = _backlog_project(tmp_path, "proj")
    with pytest.raises(RegistryError) as exc:
        validate_project(project_id, "P", directory)
    assert exc.value.code == "project_id_invalid"


def test_add_get_remove_roundtrip(tmp_path: Path) -> None:
    path = tmp_path / "projects.yaml"
    path.write_text("projects: []\n")
    reg = Registry(path)
    backend = _backlog_project(tmp_path, "proj")
    (tmp_path / "web").mkdir()
    reg.add(validate_project("proj", "Proj", backend, [backend, tmp_path / "web"]))
    saved = Registry(path).get("proj")
    assert saved.repos == (tmp_path / "web",)
    assert saved.dirs == (backend, tmp_path / "web")
    with pytest.raises(RegistryError) as exc:
        reg.add(validate_project("proj", "Proj", backend))
    assert exc.value.code == "project_exists"
    reg.remove("proj")
    assert reg.load() == []
    with pytest.raises(RegistryError) as exc:
        reg.remove("proj")
    assert exc.value.code == "project_not_found"
    with pytest.raises(RegistryError) as exc:
        reg.get("proj")
    assert exc.value.code == "project_not_found"


def test_update_keeps_order(tmp_path: Path) -> None:
    path = tmp_path / "projects.yaml"
    path.write_text("projects: []\n")
    reg = Registry(path)
    first = _backlog_project(tmp_path, "first")
    second = _backlog_project(tmp_path, "second")
    reg.add(validate_project("a", "A", first))
    reg.add(validate_project("b", "B", second))
    reg.update(validate_project("a", "A2", second))
    assert [(p.id, p.name, p.backlog_dir) for p in Registry(path).load()] == [
        ("a", "A2", second),
        ("b", "B", second),
    ]
    with pytest.raises(RegistryError) as exc:
        reg.update(validate_project("c", "C", first))
    assert exc.value.code == "project_not_found"


def test_empty_repos_in_file_default_to_backlog_dir(tmp_path: Path) -> None:
    path = tmp_path / "projects.yaml"
    path.write_text("projects:\n- id: a\n  name: A\n  backlog_dir: ~/somewhere\n  repos: []\n")
    project = Registry(path).get("a")
    assert project.backlog_dir == Path.home() / "somewhere"
    assert project.repos == ()
    assert project.dirs == (project.backlog_dir,)


def test_backlog_dir_always_first_in_dirs(tmp_path: Path) -> None:
    """Eski fayl: repos bekloq papkasisiz (NamSoft holati) yoki uni takror bilan saqlagan."""
    path = tmp_path / "projects.yaml"
    path.write_text(
        "projects:\n"
        "- id: a\n  name: A\n  backlog_dir: /b\n  repos: [/admin, /web]\n"
        "- id: c\n  name: C\n  backlog_dir: /c\n  repos: [/web, /c, /web/]\n"
    )
    a, c = Registry(path).load()
    assert a.repos == (Path("/admin"), Path("/web"))
    assert a.dirs == (Path("/b"), Path("/admin"), Path("/web"))
    assert c.repos == (Path("/web"),)
    assert c.dirs == (Path("/c"), Path("/web"))


def test_validate_strips_backlog_dir_from_repos(tmp_path: Path) -> None:
    backend = _backlog_project(tmp_path, "backend")
    (tmp_path / "web").mkdir()
    project = validate_project(
        "p", "P", backend, [tmp_path / "web", backend, str(tmp_path / "web")]
    )
    assert project.repos == (tmp_path / "web",)
    assert project.dirs == (backend, tmp_path / "web")


@pytest.mark.parametrize(
    "content", ["projects: [", "projects: 3\n", "projects:\n- 1\n", "projects:\n- id: a\n"]
)
def test_invalid_registry_file(tmp_path: Path, content: str) -> None:
    path = tmp_path / "projects.yaml"
    path.write_text(content)
    with pytest.raises(RegistryError) as exc:
        Registry(path).load()
    assert exc.value.code == "registry_invalid"


def test_save_is_atomic_on_failure(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    path = tmp_path / "projects.yaml"
    path.write_text("projects: []\n")
    reg = Registry(path)
    project = validate_project("proj", "Proj", _backlog_project(tmp_path, "proj"))

    def boom(src: str, dst: str) -> None:
        raise OSError("disk full")

    monkeypatch.setattr("os.replace", boom)
    with pytest.raises(OSError):
        reg.add(project)
    assert path.read_text() == "projects: []\n"
    assert not list(tmp_path.glob(".projects-*"))
    monkeypatch.undo()
    reg.add(project)
    assert [p.id for p in reg.load()] == ["proj"]


def test_project_model_is_frozen() -> None:
    project = Project(id="a", name="A", backlog_dir=Path("/x"))
    assert project.dirs == (Path("/x"),)
