from __future__ import annotations

import json

from .conftest import ApiEnv


def test_limits_unavailable_when_no_data(api: ApiEnv) -> None:
    resp = api.client.get("/api/limits")
    assert resp.status_code == 200
    body = resp.json()
    assert body["claude"]["available"] is False
    assert body["codex"]["available"] is False


def test_limits_reads_claude_cache_and_codex_session(api: ApiEnv) -> None:
    claude_home = api.backend.parents[0] / ".claude"  # tmp_path / ".claude"
    claude_home.mkdir(parents=True, exist_ok=True)
    (claude_home / "agent-hub-rate-limits.json").write_text(
        json.dumps(
            {
                "captured_at": 2_000_000,
                "rate_limits": {
                    "five_hour": {"used_percentage": 33.0, "resets_at": 2_003_600},
                    "seven_day": {"used_percentage": 8.0, "resets_at": 2_600_000},
                },
            }
        )
    )

    session_id = "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a99"
    codex_root = api.backend.parents[0] / ".codex" / "sessions" / "2026" / "09" / "20"
    codex_root.mkdir(parents=True, exist_ok=True)
    rollout = codex_root / f"rollout-2026-09-20T10-00-00-{session_id}.jsonl"
    rollout.write_text(
        json.dumps(
            {
                "timestamp": "2026-09-20T10:00:00.000Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "rate_limits": {
                        "limit_id": "codex",
                        "primary": {
                            "used_percent": 20.0,
                            "window_minutes": 300,
                            "resets_at": 2_003_600,
                        },
                        "secondary": None,
                    },
                },
            }
        )
        + "\n"
    )
    api.session(session_id=session_id, path=str(rollout), mtime=5000.0)

    resp = api.client.get("/api/limits")
    assert resp.status_code == 200
    body = resp.json()
    assert body["claude"]["available"] is True
    assert body["claude"]["five_hour"]["used_percent"] == 33.0
    assert body["claude"]["weekly"]["used_percent"] == 8.0
    assert body["codex"]["available"] is True
    assert body["codex"]["five_hour"]["used_percent"] == 20.0
    assert body["codex"]["weekly"] is None


def test_limits_when_kanbot_down_codex_is_unavailable_not_error(api: ApiEnv) -> None:
    api.kanbot_down = True
    resp = api.client.get("/api/limits")
    assert resp.status_code == 200
    assert resp.json()["codex"]["available"] is False
