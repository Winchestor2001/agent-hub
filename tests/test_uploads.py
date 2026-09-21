"""`services/uploads.py`: nom tozalash, limitlar va yo'l chegaralari."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

import pytest

from agent_hub.registry import Project
from agent_hub.services import uploads
from agent_hub.services.uploads import UploadError

NOW = datetime(2026, 9, 16, 5, 55, 0)


@pytest.fixture
def project(tmp_path: Path) -> Project:
    backlog = tmp_path / "leveling"
    (backlog / ".backlog").mkdir(parents=True)
    (tmp_path / "leveling-web").mkdir()
    return Project(
        id="leveling", name="Leveling", backlog_dir=backlog, repos=(tmp_path / "leveling-web",)
    )


def store(project: Project, name: str, data: bytes = b"x", task_id: str | None = None) -> str:
    directory = uploads.uploads_dir(project, None, task_id)
    stored = uploads.store(directory, project.dirs[0], name, uploads.chunked(data), now=NOW)
    return stored.path


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("shot.png", "20260916-055500-shot.png"),
        # Yo'l qismlari tashlanadi — traversal ham, Windows ajratuvchisi ham.
        ("../../etc/passwd.txt", "20260916-055500-passwd.txt"),
        # Kengaytma kichik harfga keltiriladi.
        (r"C:\Users\me\My Photo.PNG", "20260916-055500-My-Photo.png"),
        ("a b//c.md", "20260916-055500-c.md"),
        # Boshqaruv belgilari va bo'shliqlar chiziqchaga, takror chiziqchalar qisqaradi.
        ("bad\nname\t\t!!.pdf", "20260916-055500-bad-name.pdf"),
        (".hidden.log", "20260916-055500-hidden.log"),
        # Faqat belgilardan iborat nom ham bo'sh qolmaydi.
        ("!!!.json", "20260916-055500-file.json"),
    ],
)
def test_safe_names(project: Project, raw: str, expected: str) -> None:
    assert store(project, raw).endswith(expected)


@pytest.mark.parametrize("name", ["virus.exe", "script.svg", "noext", "archive.tar.gz", ".png"])
def test_rejects_unknown_extension(project: Project, name: str) -> None:
    with pytest.raises(UploadError) as err:
        store(project, name)
    assert err.value.code == "upload_type_invalid"


def test_long_name_is_truncated_with_extension(project: Project) -> None:
    path = Path(store(project, "a" * 300 + ".png"))
    assert path.suffix == ".png"
    assert len(path.name) == len("20260916-055500-") + uploads.MAX_NAME_LENGTH


def test_saves_under_project_uploads_dir(project: Project) -> None:
    path = store(project, "shot.png", task_id="TASK-29")
    assert path.startswith(".agent-hub/uploads/task-29/")
    assert (project.dirs[0] / path).is_file()


def test_no_task_goes_to_inbox(project: Project) -> None:
    assert store(project, "notes.md").startswith(".agent-hub/uploads/inbox/")


def test_uploads_dir_is_self_ignoring(project: Project) -> None:
    uploads.uploads_dir(project)
    assert (project.dirs[0] / uploads.UPLOAD_ROOT / ".gitignore").read_text() == "*\n"


def test_same_name_does_not_overwrite(project: Project) -> None:
    first = store(project, "shot.png", b"aaa")
    second = store(project, "shot.png", b"bbb")
    assert first != second
    assert second.endswith("-1.png")
    assert (project.dirs[0] / first).read_bytes() == b"aaa"


def test_too_large_file_is_not_left_behind(project: Project) -> None:
    directory = uploads.uploads_dir(project)
    data = b"x" * (uploads.MAX_FILE_BYTES + 1)
    with pytest.raises(UploadError) as err:
        uploads.store(directory, project.dirs[0], "big.png", uploads.chunked(data), now=NOW)
    assert err.value.code == "upload_too_large"
    assert err.value.params["limit"] == uploads.MAX_FILE_BYTES
    assert err.value.params["limit_mb"] == 10
    assert list(directory.iterdir()) == []


def test_check_name_rejects_video_and_accepts_image() -> None:
    uploads.check_name("shot.PNG")
    with pytest.raises(UploadError) as err:
        uploads.check_name("clip.mp4")
    assert err.value.code == "upload_type_invalid"


def test_empty_file_is_rejected(project: Project) -> None:
    with pytest.raises(UploadError) as err:
        store(project, "empty.png", b"")
    assert err.value.code == "upload_empty"


@pytest.mark.parametrize("task_id", ["../evil", "a/b", "TASK 29", "", " "])
def test_invalid_task_dir(project: Project, task_id: str) -> None:
    # Bo'sh qiymat — `inbox`, qolganlari xato.
    if not task_id.strip():
        assert uploads.uploads_dir(project, None, task_id).name == uploads.INBOX_DIR
        return
    with pytest.raises(UploadError) as err:
        uploads.uploads_dir(project, None, task_id)
    assert err.value.code == "upload_name_invalid"


def test_second_repo_is_allowed_cwd(project: Project) -> None:
    web = project.dirs[1]
    assert uploads.project_dir(project, str(web)) == web


def test_cwd_outside_project(project: Project, tmp_path: Path) -> None:
    with pytest.raises(UploadError) as err:
        uploads.project_dir(project, str(tmp_path))
    assert err.value.code == "cwd_outside_project"


def test_count_limits() -> None:
    with pytest.raises(UploadError) as empty:
        uploads.check_count(0)
    assert empty.value.code == "upload_empty"
    with pytest.raises(UploadError) as many:
        uploads.check_count(uploads.MAX_FILES + 1)
    assert many.value.code == "upload_too_many"
    uploads.check_count(uploads.MAX_FILES)


def test_resolve_accepts_stored_paths(project: Project) -> None:
    path = store(project, "shot.png", task_id="TASK-29")
    assert uploads.resolve(project, [path, path]) == [path]


@pytest.mark.parametrize(
    "path",
    [
        "../../../etc/passwd",
        ".agent-hub/uploads/../../secret.txt",
        ".agent-hub/uploads/inbox/yo-q.png",
        "/etc/hosts",
        "README.md",
    ],
)
def test_resolve_rejects_paths_outside_uploads(project: Project, path: str) -> None:
    (project.dirs[0] / "README.md").write_text("hi")
    with pytest.raises(UploadError) as err:
        uploads.resolve(project, [path])
    assert err.value.code == "upload_not_found"


async def test_read_upload_stops_at_limit() -> None:
    async def reader(size: int) -> bytes:
        return b"x" * size

    with pytest.raises(UploadError) as err:
        await uploads.read_upload(reader, "big.png")
    assert err.value.code == "upload_too_large"


async def test_read_upload_collects_chunks() -> None:
    remaining = [b"ab", b"cd", b""]

    async def reader(size: int) -> bytes:
        return remaining.pop(0)

    assert await uploads.read_upload(reader, "a.png") == [b"ab", b"cd"]
