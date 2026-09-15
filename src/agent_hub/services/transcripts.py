"""O'tgan agent sessiyalarining transkript fayllarini diskdan o'chirish.

KanBot runner Claude (`<claude_home>/projects/*/<id>.jsonl`) va Codex
(`~/.codex/sessions/**/rollout-…-<id>.jsonl`) fayllarini o'qiydi va sessiya yozuviga fayl yo'lini
qo'shadi. Yo'l KanBot'dan kelgani uchun ishonilmaydi: fayl shu agentning sessiya papkasi ichida,
`.jsonl` va nomi sessiya ID'siga mos bo'lishi shart. Aks holda hech narsa o'chirilmaydi.
"""

from __future__ import annotations

import os
import re
import shutil
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path

from agent_hub.kanbot_client import AgentSession

_SESSION_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")


class TranscriptError(Exception):
    def __init__(self, code: str, session: AgentSession) -> None:
        super().__init__(f"{code}: {session.agent}:{session.session_id}")
        self.code = code
        self.session = session


@dataclass(frozen=True)
class Transcript:
    """Bitta sessiyaning o'chiriladigan yo'llari."""

    file: Path
    # Claude'ning shu ID'li yordamchi papkasi (subagent'lar, katta tool natijalari).
    extra_dir: Path | None


def locate(session: AgentSession, roots: Mapping[str, Path]) -> Transcript:
    """Sessiya fayli; mos fayl bo'lmasa `TranscriptError("session_file_not_found")`."""
    root = roots.get(session.agent)
    sid = session.session_id
    if root is None or not session.path or not _SESSION_ID_RE.match(sid):
        raise TranscriptError("session_file_not_found", session)
    real_root = Path(os.path.realpath(root))
    file = Path(os.path.realpath(session.path))
    matches_id = file.stem == sid if session.agent == "claude" else file.stem.endswith(f"-{sid}")
    if (
        not file.is_relative_to(real_root)
        or file.suffix != ".jsonl"
        or not matches_id
        or not file.is_file()
    ):
        raise TranscriptError("session_file_not_found", session)
    extra = file.parent / sid
    has_extra = session.agent == "claude" and extra.is_dir() and not extra.is_symlink()
    return Transcript(file, extra if has_extra else None)


def delete(transcripts: Iterable[Transcript]) -> None:
    for transcript in transcripts:
        transcript.file.unlink(missing_ok=True)
        if transcript.extra_dir is not None:
            shutil.rmtree(transcript.extra_dir, ignore_errors=True)
