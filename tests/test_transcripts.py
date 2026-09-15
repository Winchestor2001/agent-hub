from __future__ import annotations

from pathlib import Path

import pytest

from agent_hub.kanbot_client import AgentSession
from agent_hub.services.transcripts import TranscriptError, delete, locate

CLAUDE_ID = "e17cba2b-4d8f-4966-8d50-7a561c0a44ec"
CODEX_ID = "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b"


def _roots(tmp_path: Path) -> dict[str, Path]:
    return {"claude": tmp_path / "claude", "codex": tmp_path / "codex"}


def _file(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("{}\n")
    return path


def _session(agent: str, session_id: str, path: Path | str) -> AgentSession:
    return AgentSession(agent=agent, session_id=session_id, path=str(path))


def test_claude_transcript_with_extra_dir(tmp_path: Path) -> None:
    roots = _roots(tmp_path)
    file = _file(roots["claude"] / "-proj" / f"{CLAUDE_ID}.jsonl")
    _file(roots["claude"] / "-proj" / CLAUDE_ID / "subagents" / "a.jsonl")
    other = _file(roots["claude"] / "-proj" / "other.jsonl")

    transcript = locate(_session("claude", CLAUDE_ID, file), roots)
    assert transcript.file == file.resolve()
    assert transcript.extra_dir == (roots["claude"] / "-proj" / CLAUDE_ID).resolve()

    delete([transcript])
    assert not file.exists()
    assert not (roots["claude"] / "-proj" / CLAUDE_ID).exists()
    assert other.exists()


def test_codex_transcript(tmp_path: Path) -> None:
    roots = _roots(tmp_path)
    file = _file(
        roots["codex"] / "2026" / "05" / "01" / f"rollout-2026-05-01T10-00-00-{CODEX_ID}.jsonl"
    )
    # Codex'da yondosh papka o'chirilmaydi (u sana papkasi).
    _file(roots["codex"] / "2026" / "05" / "01" / CODEX_ID / "x")
    transcript = locate(_session("codex", CODEX_ID, file), roots)
    assert transcript.extra_dir is None
    delete([transcript])
    assert not file.exists()
    assert (roots["codex"] / "2026" / "05" / "01" / CODEX_ID / "x").exists()


def test_rejects_unsafe_paths(tmp_path: Path) -> None:
    roots = _roots(tmp_path)
    good = _file(roots["claude"] / "-proj" / f"{CLAUDE_ID}.jsonl")
    outside = _file(tmp_path / "elsewhere" / f"{CLAUDE_ID}.jsonl")
    link = roots["claude"] / "-proj" / "link"
    link.mkdir()
    (link / f"{CLAUDE_ID}.jsonl").symlink_to(outside)
    wrong_suffix = _file(roots["claude"] / "-proj" / f"{CLAUDE_ID}.txt")
    codex = _file(roots["codex"] / f"rollout-{CODEX_ID}.jsonl")
    cases = [
        _session("claude", CLAUDE_ID, outside),  # ildizdan tashqarida
        _session("claude", CLAUDE_ID, link / f"{CLAUDE_ID}.jsonl"),  # symlink tashqariga
        _session("claude", CLAUDE_ID, wrong_suffix),
        _session("claude", "other-id", good),  # nom ID'ga mos emas
        _session("codex", CLAUDE_ID, good),  # boshqa agent ildizi
        _session("claude", CODEX_ID, codex),
        _session("claude", CLAUDE_ID, roots["claude"] / "-proj" / "missing.jsonl"),
        _session("claude", CLAUDE_ID, ""),
        _session("gemini", CLAUDE_ID, good),
        _session("claude", "../x", good),
    ]
    for session in cases:
        with pytest.raises(TranscriptError) as caught:
            locate(session, roots)
        assert caught.value.code == "session_file_not_found"
    assert good.exists() and outside.exists()
