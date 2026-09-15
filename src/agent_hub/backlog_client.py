"""Backlog.md CLI'ga yagona kirish nuqtasi.

Barcha o'qish va yozish `backlog` buyrug'i orqali (cwd = loyiha papkasi). Faqat `task_prefix` ni CLI
bermaydi — u config faylidan o'qiladi (yozilmaydi). Natijalar fayllar fingerprint'i bo'yicha
keshlanadi: fayllar o'zgarmasa subprocess chaqirilmaydi.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import os
import re
from collections.abc import Awaitable, Callable, Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from pydantic.alias_generators import to_camel

from agent_hub.registry import BACKLOG_CONFIG_CANDIDATES

DEFAULT_TIMEOUT = 15.0
LOCK_RETRY_DELAY = 0.3
VIEW_CONCURRENCY = 4
_BACKLOG_DIRS = (".backlog", "backlog")
_WATCHED_SUBDIRS = ("tasks", "drafts", "completed", "milestones")

_CREATED_RE = re.compile(r"^Created task (\S+)\s*$", re.MULTILINE)
_MILESTONE_RE = re.compile(r"^\s+(\S+): (.*) \((\d+)/(\d+) done\)\s*$")


# --- xatolar -------------------------------------------------------------------------------


class BacklogError(Exception):
    code = "backlog_error"

    def __init__(self, message: str, **params: Any) -> None:
        super().__init__(message)
        self.params = params


class BacklogNotFound(BacklogError):
    code = "backlog_not_found"


class BacklogTaskNotFound(BacklogError):
    code = "task_not_found"


class BacklogLocked(BacklogError):
    code = "backlog_locked"


class BacklogCliError(BacklogError):
    def __init__(self, message: str, code: str = "backlog_cli_error", **params: Any) -> None:
        super().__init__(message, **params)
        self.code = code


# --- modellar ------------------------------------------------------------------------------


class _Model(BaseModel):
    model_config = ConfigDict(
        extra="ignore", frozen=True, alias_generator=to_camel, populate_by_name=True
    )


class ChecklistItem(_Model):
    index: int
    text: str
    checked: bool


class TaskRef(_Model):
    id: str
    title: str = ""


class TaskSummary(_Model):
    id: str
    title: str
    status: str
    type: str | None = None
    priority: str | None = None
    assignees: tuple[str, ...] = ()
    labels: tuple[str, ...] = ()
    milestone: str | None = None
    parent_task_id: str | None = None
    acceptance_criteria_completed: int = 0
    acceptance_criteria_count: int = 0
    ordinal: float | None = None
    created_at: str | None = None
    updated_at: str | None = None
    is_ready: bool = True


class TaskDetail(TaskSummary):
    description: str | None = None
    dependencies: tuple[str, ...] = ()
    subtasks: tuple[TaskRef, ...] = ()
    references: tuple[str, ...] = ()
    documentation: tuple[str, ...] = ()
    acceptance_criteria: tuple[ChecklistItem, ...] = ()
    definition_of_done: tuple[ChecklistItem, ...] = ()
    implementation_plan: str | None = None
    implementation_notes: str | None = None
    final_summary: str | None = None
    comments: tuple[dict[str, Any], ...] = Field(default_factory=tuple)

    @property
    def dod_progress(self) -> tuple[int, int]:
        items = self.definition_of_done
        return sum(1 for item in items if item.checked), len(items)


@dataclass(frozen=True)
class Milestone:
    id: str
    title: str
    done: int
    total: int
    completed: bool


# --- subprocess ----------------------------------------------------------------------------


@dataclass(frozen=True)
class CliResult:
    returncode: int
    stdout: str
    stderr: str


Runner = Callable[[Sequence[str], Path, float], Awaitable[CliResult]]


async def run_subprocess(argv: Sequence[str], cwd: Path, time_limit: float) -> CliResult:
    env = {**os.environ, "NO_COLOR": "1", "FORCE_COLOR": "0", "BACKLOG_CWD": str(cwd)}
    try:
        proc = await asyncio.create_subprocess_exec(
            *argv,
            cwd=cwd,
            env=env,
            stdin=asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
    except FileNotFoundError as exc:
        raise BacklogCliError(
            f"{argv[0]} topilmadi", code="backlog_cli_missing", executable=argv[0]
        ) from exc
    try:
        async with asyncio.timeout(time_limit):
            stdout, stderr = await proc.communicate()
    except TimeoutError as exc:
        proc.kill()
        await proc.wait()
        raise BacklogCliError(
            "backlog javob bermadi", code="backlog_timeout", command=" ".join(argv[1:3])
        ) from exc
    return CliResult(
        proc.returncode if proc.returncode is not None else -1,
        stdout.decode(errors="replace"),
        stderr.decode(errors="replace"),
    )


# --- fingerprint ---------------------------------------------------------------------------


def _stat_entry(path: Path) -> str:
    try:
        st = path.stat()
    except OSError:
        return f"{path}:-"
    return f"{path}:{st.st_mtime_ns}:{st.st_size}"


@dataclass(frozen=True)
class Fingerprint:
    digest: str
    task_files: dict[str, str]  # vazifa id (kichik harf) -> fayl stat yozuvi


def compute_fingerprint(root: Path) -> Fingerprint:
    entries = [_stat_entry(root / candidate) for candidate in BACKLOG_CONFIG_CANDIDATES]
    task_files: dict[str, str] = {}
    for name in _BACKLOG_DIRS:
        base = root / name
        if not base.is_dir():
            continue
        for sub in _WATCHED_SUBDIRS:
            directory = base / sub
            entries.append(_stat_entry(directory))
            try:
                files = sorted(directory.glob("*.md"))
            except OSError:
                continue
            for file in files:
                entry = _stat_entry(file)
                entries.append(entry)
                if sub in ("tasks", "completed"):
                    task_files[file.name.split(" - ", 1)[0].lower()] = entry
    digest = hashlib.sha256("\n".join(entries).encode()).hexdigest()
    return Fingerprint(digest, task_files)


# --- client --------------------------------------------------------------------------------


def _split_csv(text: str) -> list[str]:
    return [item.strip() for item in text.strip().split(",") if item.strip()]


def _json_payload(stdout: str, kind: str) -> dict[str, Any]:
    try:
        data = json.loads(stdout)
    except ValueError as exc:
        raise BacklogCliError("JSON emas", code="backlog_bad_output", kind=kind) from exc
    if not isinstance(data, dict) or data.get("kind") != kind:
        raise BacklogCliError("kutilmagan JSON", code="backlog_bad_output", kind=kind)
    return data


def parse_task_list(stdout: str) -> list[TaskSummary]:
    data = _json_payload(stdout, "task-list")
    try:
        return [TaskSummary.model_validate(item) for item in data.get("tasks", [])]
    except ValidationError as exc:
        raise BacklogCliError(str(exc), code="backlog_bad_output", kind="task-list") from exc


def parse_task_view(stdout: str) -> TaskDetail:
    data = _json_payload(stdout, "task-view")
    try:
        return TaskDetail.model_validate(data.get("task"))
    except ValidationError as exc:
        raise BacklogCliError(str(exc), code="backlog_bad_output", kind="task-view") from exc


def parse_milestones(stdout: str) -> list[Milestone]:
    milestones: list[Milestone] = []
    completed = False
    for line in stdout.splitlines():
        if line.startswith("Completed milestones"):
            completed = True
        elif line.startswith("Active milestones"):
            completed = False
        elif match := _MILESTONE_RE.match(line):
            mid, title, done, total = match.groups()
            milestones.append(Milestone(mid, title, int(done), int(total), completed))
    return milestones


def parse_created_id(stdout: str) -> str:
    match = _CREATED_RE.search(stdout)
    if match is None:
        raise BacklogCliError("vazifa ID topilmadi", code="backlog_bad_output", kind="task-create")
    return match.group(1)


INIT_BACKLOG_DIR = ".backlog"
INIT_TIMEOUT = 60.0


class BacklogClient:
    def __init__(
        self,
        root: Path,
        executable: str = "backlog",
        timeout: float = DEFAULT_TIMEOUT,
        runner: Runner = run_subprocess,
        lock_retry_delay: float = LOCK_RETRY_DELAY,
    ) -> None:
        self.root = root
        self.executable = executable
        self.timeout = timeout
        self._runner = runner
        self._lock_retry_delay = lock_retry_delay
        self._cache: dict[str, tuple[str, Any]] = {}
        self._inflight: dict[str, tuple[str, asyncio.Future[Any]]] = {}
        self._view_semaphore = asyncio.Semaphore(VIEW_CONCURRENCY)

    # -- ichki --------------------------------------------------------------------------

    def _ensure_project(self) -> None:
        if not any((self.root / candidate).is_file() for candidate in BACKLOG_CONFIG_CANDIDATES):
            raise BacklogNotFound("bekloq topilmadi", path=str(self.root))

    async def _run(self, *args: str) -> str:
        self._ensure_project()
        argv = [self.executable, *args]
        result = await self._runner(argv, self.root, self.timeout)
        if result.returncode != 0 and _is_locked(result.stderr):
            await asyncio.sleep(self._lock_retry_delay)
            result = await self._runner(argv, self.root, self.timeout)
        if result.returncode == 0:
            return result.stdout
        message = (result.stderr.strip() or result.stdout.strip())[:500]
        if _is_locked(message):
            raise BacklogLocked(message, path=str(self.root))
        if "No Backlog.md project found" in message:
            raise BacklogNotFound(message, path=str(self.root))
        if re.search(r"^Task \S+ not found", message, re.MULTILINE):
            raise BacklogTaskNotFound(message, path=str(self.root))
        raise BacklogCliError(
            message, command=" ".join(args[:2]), returncode=result.returncode, detail=message
        )

    async def init(self, project_name: str, *, git: bool) -> None:
        """`root`da `.backlog/` yaratadi: agent yo'riqnoma fayllarisiz va commit'siz.

        Git bo'lmagan papkada `--no-git` shart: aks holda CLI savol berib, hech narsa yaratmasdan
        0 kod bilan chiqadi. Shu sabab natija config.yml borligi bilan tekshiriladi.
        """
        if any((self.root / candidate).is_file() for candidate in BACKLOG_CONFIG_CANDIDATES):
            raise BacklogCliError("bekloq bor", code="backlog_exists", path=str(self.root))
        argv = [
            self.executable, "init", project_name, "--defaults",
            "--backlog-dir", INIT_BACKLOG_DIR, "--integration-mode", "none",
        ]  # fmt: skip
        if not git:
            argv.append("--no-git")
        result = await self._runner(argv, self.root, INIT_TIMEOUT)
        if result.returncode != 0 or not (self.root / INIT_BACKLOG_DIR / "config.yml").is_file():
            message = (result.stderr.strip() or result.stdout.strip())[:500]
            raise BacklogCliError(
                message or "config.yml yaratilmadi",
                code="backlog_init_failed",
                path=str(self.root),
                detail=message,
            )
        self.invalidate()

    async def _cached(self, key: str, loader: Callable[[], Awaitable[Any]]) -> Any:
        fingerprint = compute_fingerprint(self.root).digest
        cached = self._cache.get(key)
        if cached is not None and cached[0] == fingerprint:
            return cached[1]
        inflight = self._inflight.get(key)
        if inflight is not None and inflight[0] == fingerprint:
            return await asyncio.shield(inflight[1])
        future: asyncio.Future[Any] = asyncio.get_running_loop().create_future()
        self._inflight[key] = (fingerprint, future)
        try:
            value = await loader()
        except BaseException as exc:
            future.set_exception(exc)
            future.exception()  # kutuvchi bo'lmasa ogohlantirish chiqmasin
            raise
        else:
            future.set_result(value)
            self._cache[key] = (fingerprint, value)
            return value
        finally:
            if self._inflight.get(key, (None, None))[1] is future:
                del self._inflight[key]

    def invalidate(self) -> None:
        self._cache.clear()

    # -- o'qish -------------------------------------------------------------------------

    async def list_tasks(self) -> list[TaskSummary]:
        async def load() -> list[TaskSummary]:
            return parse_task_list(await self._run("task", "list", "--json"))

        result: list[TaskSummary] = await self._cached("list_tasks", load)
        return result

    async def view_task(self, task_id: str) -> TaskDetail:
        fingerprint = compute_fingerprint(self.root)
        file_entry = fingerprint.task_files.get(task_id.lower(), fingerprint.digest)
        key = f"view:{task_id.lower()}"
        cached = self._cache.get(key)
        if cached is not None and cached[0] == file_entry:
            detail: TaskDetail = cached[1]
            return detail
        async with self._view_semaphore:
            detail = parse_task_view(await self._run("task", "view", "--json", "--", task_id))
        self._cache[key] = (file_entry, detail)
        return detail

    async def dod_progress(self, task_ids: Iterable[str]) -> dict[str, tuple[int, int]]:
        ids = list(task_ids)
        details = await asyncio.gather(*(self.view_task(task_id) for task_id in ids))
        return {task_id: detail.dod_progress for task_id, detail in zip(ids, details, strict=True)}

    async def statuses(self) -> list[str]:
        async def load() -> list[str]:
            return _split_csv(await self._run("config", "get", "statuses"))

        result: list[str] = await self._cached("statuses", load)
        return result

    async def labels(self) -> list[str]:
        async def load() -> list[str]:
            return _split_csv(await self._run("config", "get", "labels"))

        result: list[str] = await self._cached("labels", load)
        return result

    async def milestones(self) -> list[Milestone]:
        async def load() -> list[Milestone]:
            stdout = await self._run("milestone", "list", "--plain", "--show-completed")
            return parse_milestones(stdout)

        result: list[Milestone] = await self._cached("milestones", load)
        return result

    def task_prefix(self) -> str:
        """`task_prefix` CLI'da yo'q — config faylidan faqat o'qiladi."""
        self._ensure_project()
        for candidate in BACKLOG_CONFIG_CANDIDATES:
            path = self.root / candidate
            if not path.is_file():
                continue
            try:
                data = yaml.safe_load(path.read_text(encoding="utf-8"))
            except (OSError, yaml.YAMLError):
                break
            if isinstance(data, dict):
                prefix = data.get("task_prefix") or data.get("taskPrefix")
                if isinstance(prefix, str) and prefix.strip():
                    return prefix.strip()
            break
        return "task"

    # -- yozish -------------------------------------------------------------------------

    async def create_task(
        self,
        title: str,
        *,
        description: str | None = None,
        status: str | None = None,
        labels: Sequence[str] = (),
        assignees: Sequence[str] = (),
        milestone: str | None = None,
        acceptance_criteria: Sequence[str] = (),
    ) -> str:
        # `--opt=qiymat` va `--`: "-" bilan boshlanadigan matn opsiya deb talqin qilinmaydi.
        args = ["task", "create"]
        if description:
            args.append(f"--description={description}")
        if status:
            args.append(f"--status={status}")
        if labels:
            args.append(f"--labels={','.join(labels)}")
        # Bo'sh --assignee= — defaultAssignee qo'llanmasin, faqat aniq berilganlar.
        args.append(f"--assignee={','.join(assignees)}")
        if milestone:
            args.append(f"--milestone={milestone}")
        args += [f"--ac={criterion}" for criterion in acceptance_criteria]
        args += ["--", title]
        try:
            return parse_created_id(await self._run(*args))
        finally:
            self.invalidate()

    async def set_status(self, task_id: str, status: str) -> None:
        try:
            await self._run("task", "edit", f"--status={status}", "--", task_id)
        finally:
            self.invalidate()

    async def add_label(self, task_id: str, labels: Sequence[str]) -> None:
        try:
            await self._run("task", "edit", f"--add-label={','.join(labels)}", "--", task_id)
        finally:
            self.invalidate()


def _is_locked(message: str) -> bool:
    return "being modified by another process" in message
