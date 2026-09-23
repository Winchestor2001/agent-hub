"""Claude/Codex rate-limit foizi: `services/limits.py`."""

from __future__ import annotations

import json
from pathlib import Path

from agent_hub.kanbot_client import AgentSession
from agent_hub.services.limits import (
    STALE_AFTER,
    LimitsService,
    read_claude_limits,
    read_codex_limits,
)

NOW = 2_000_000.0
CODEX_ID = "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b"


def _codex_root(tmp_path: Path) -> Path:
    return tmp_path / "codex"


def _codex_file(tmp_path: Path, session_id: str = CODEX_ID) -> Path:
    path = (
        _codex_root(tmp_path)
        / "2026"
        / "09"
        / "20"
        / f"rollout-2026-09-20T10-00-00-{session_id}.jsonl"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def _write_lines(path: Path, lines: list[dict[str, object]]) -> None:
    path.write_text("\n".join(json.dumps(line) for line in lines) + "\n")


def _token_count_line(
    timestamp: str,
    *,
    primary: dict[str, object] | None = None,
    secondary: dict[str, object] | None = None,
) -> dict[str, object]:
    return {
        "timestamp": timestamp,
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "rate_limits": {
                "limit_id": "codex",
                "primary": primary,
                "secondary": secondary,
            },
        },
    }


# --- Claude: kesh fayli ------------------------------------------------------------------------


def test_claude_limits_missing_cache(tmp_path: Path) -> None:
    limits = read_claude_limits(tmp_path / "missing.json", now=NOW)
    assert limits.available is False


def test_claude_limits_reads_cache(tmp_path: Path) -> None:
    cache = tmp_path / "cache.json"
    cache.write_text(
        json.dumps(
            {
                "captured_at": NOW - 60,
                "rate_limits": {
                    "five_hour": {"used_percentage": 42.0, "resets_at": NOW + 3600},
                    "seven_day": {"used_percentage": 10.0, "resets_at": NOW + 86400},
                },
            }
        )
    )
    limits = read_claude_limits(cache, now=NOW)
    assert limits.available is True
    assert limits.stale is False
    assert limits.five_hour is not None and limits.five_hour.used_percent == 42.0
    assert limits.weekly is not None and limits.weekly.used_percent == 10.0
    assert limits.weekly.resets_at == NOW + 86400


def test_claude_limits_marks_stale_when_old(tmp_path: Path) -> None:
    cache = tmp_path / "cache.json"
    cache.write_text(
        json.dumps(
            {
                "captured_at": NOW - STALE_AFTER - 1,
                "rate_limits": {"five_hour": {"used_percentage": 5.0, "resets_at": None}},
            }
        )
    )
    limits = read_claude_limits(cache, now=NOW)
    assert limits.available is True
    assert limits.stale is True


def test_claude_limits_survives_bad_json(tmp_path: Path) -> None:
    cache = tmp_path / "cache.json"
    cache.write_text("{not json")
    assert read_claude_limits(cache, now=NOW).available is False


def test_claude_limits_without_captured_at_is_stale(tmp_path: Path) -> None:
    """`captured_at` bo'lmasa ham foiz ko'rsatiladi, faqat eskirgan deb belgilanadi."""
    cache = tmp_path / "cache.json"
    cache.write_text(json.dumps({"rate_limits": {"five_hour": {"used_percentage": 5.0}}}))
    limits = read_claude_limits(cache, now=NOW)
    assert (limits.available, limits.stale, limits.updated_at) == (True, True, None)


# --- Codex: rollout fayli ------------------------------------------------------------------------


def test_codex_limits_reads_last_matching_line(tmp_path: Path) -> None:
    path = _codex_file(tmp_path)
    _write_lines(
        path,
        [
            _token_count_line("2026-09-20T10:00:00.000Z", primary=None, secondary=None),
            _token_count_line(
                "2026-09-20T10:05:00.000Z",
                primary={"used_percent": 15.0, "window_minutes": 300, "resets_at": 2_100_000},
                secondary={"used_percent": 30.0, "window_minutes": 10080, "resets_at": 2_500_000},
            ),
        ],
    )
    limits = read_codex_limits(path, now=NOW)
    assert limits.available is True
    assert limits.five_hour is not None and limits.five_hour.used_percent == 15.0
    assert limits.weekly is not None and limits.weekly.used_percent == 30.0
    assert limits.weekly.resets_at == 2_500_000


def test_codex_limits_window_kind_independent_of_field_name(tmp_path: Path) -> None:
    """`primary`/`secondary` qaysi oynani ushlashi ahamiyatsiz — window_minutes hal qiladi."""
    path = _codex_file(tmp_path)
    _write_lines(
        path,
        [
            _token_count_line(
                "2026-09-20T10:00:00.000Z",
                primary={"used_percent": 12.0, "window_minutes": 10080, "resets_at": None},
                secondary=None,
            )
        ],
    )
    limits = read_codex_limits(path, now=NOW)
    assert limits.five_hour is None
    assert limits.weekly is not None and limits.weekly.used_percent == 12.0


def test_codex_limits_uses_line_timestamp_for_freshness(tmp_path: Path) -> None:
    path = _codex_file(tmp_path)
    _write_lines(
        path,
        [
            _token_count_line(
                "2026-09-20T10:00:00.000Z",
                primary={"used_percent": 1.0, "window_minutes": 300, "resets_at": None},
            )
        ],
    )
    from datetime import datetime

    expected = datetime.fromisoformat("2026-09-20T10:00:00.000+00:00").timestamp()
    limits = read_codex_limits(path, now=expected + 60)
    assert limits.updated_at == expected
    assert limits.stale is False
    limits_later = read_codex_limits(path, now=expected + STALE_AFTER + 1)
    assert limits_later.stale is True


def test_codex_limits_skips_lines_without_usable_window(tmp_path: Path) -> None:
    path = _codex_file(tmp_path)
    _write_lines(
        path,
        [
            _token_count_line(
                "2026-09-20T09:00:00.000Z",
                primary={"used_percent": 9.0, "window_minutes": 300, "resets_at": None},
            ),
            _token_count_line("2026-09-20T10:00:00.000Z", primary=None, secondary=None),
        ],
    )
    limits = read_codex_limits(path, now=NOW)
    assert limits.five_hour is not None and limits.five_hour.used_percent == 9.0


def test_codex_limits_missing_file(tmp_path: Path) -> None:
    assert read_codex_limits(tmp_path / "missing.jsonl", now=NOW).available is False


def test_codex_limits_ignores_stale_leading_partial_line(tmp_path: Path) -> None:
    """Katta faylda faqat oxiri o'qiladi — birinchi (to'liq bo'lmagan) qator e'tiborga olinmaydi."""
    path = _codex_file(tmp_path)
    padding = _token_count_line("2026-09-20T08:00:00.000Z", primary=None, secondary=None)
    filler = "x" * 300_000  # CODEX_TAIL_BYTES'dan katta — kesish ishlashini majburlaydi
    payload = padding["payload"]
    assert isinstance(payload, dict)
    payload["filler"] = filler
    good = _token_count_line(
        "2026-09-20T10:00:00.000Z",
        primary={"used_percent": 7.0, "window_minutes": 300, "resets_at": None},
    )
    _write_lines(path, [padding, good])
    limits = read_codex_limits(path, now=NOW)
    assert limits.five_hour is not None and limits.five_hour.used_percent == 7.0


# --- LimitsService: eng so'nggi Codex sessiyasini tanlash -----------------------------------


def test_service_picks_latest_codex_session_by_mtime(tmp_path: Path) -> None:
    roots = {"codex": _codex_root(tmp_path)}
    old_id = "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a01"
    new_id = "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a02"
    old_path = _codex_file(tmp_path, old_id)
    new_path = _codex_file(tmp_path, new_id)
    _write_lines(
        old_path,
        [
            _token_count_line(
                "2026-09-20T09:00:00.000Z", primary={"used_percent": 1.0, "window_minutes": 300}
            )
        ],
    )
    _write_lines(
        new_path,
        [
            _token_count_line(
                "2026-09-20T10:00:00.000Z", primary={"used_percent": 55.0, "window_minutes": 300}
            )
        ],
    )
    service = LimitsService(claude_cache=tmp_path / "claude-cache.json", codex_roots=roots)
    sessions = [
        AgentSession(agent="codex", session_id=old_id, path=str(old_path), mtime=100.0),
        AgentSession(agent="codex", session_id=new_id, path=str(new_path), mtime=200.0),
        AgentSession(agent="claude", session_id="ignored", path="", mtime=999.0),
    ]
    limits = service.codex(sessions, now=NOW)
    assert limits.five_hour is not None and limits.five_hour.used_percent == 55.0


def test_service_codex_without_sessions_is_unavailable(tmp_path: Path) -> None:
    service = LimitsService(
        claude_cache=tmp_path / "claude-cache.json", codex_roots={"codex": _codex_root(tmp_path)}
    )
    assert service.codex([], now=NOW).available is False


def test_service_codex_rejects_path_outside_root(tmp_path: Path) -> None:
    """Yo'l KanBot'dan kelgani uchun ishonilmaydi — root tashqarisidagi fayl o'qilmaydi."""
    outside = tmp_path / "outside.jsonl"
    _write_lines(
        outside,
        [
            _token_count_line(
                "2026-09-20T10:00:00.000Z", primary={"used_percent": 99.0, "window_minutes": 300}
            )
        ],
    )
    service = LimitsService(
        claude_cache=tmp_path / "claude-cache.json", codex_roots={"codex": _codex_root(tmp_path)}
    )
    sessions = [AgentSession(agent="codex", session_id=CODEX_ID, path=str(outside), mtime=100.0)]
    assert service.codex(sessions, now=NOW).available is False


def test_service_for_settings_uses_claude_home(tmp_path: Path) -> None:
    from agent_hub.settings import Settings

    settings = Settings(
        config_dir=tmp_path / "config",
        kanbot_config=tmp_path / "kanbot.json",
        home=tmp_path,
    )
    service = LimitsService.for_settings(settings)
    assert service.claude(now=NOW).available is False  # kesh hali yo'q, xato bermaydi
