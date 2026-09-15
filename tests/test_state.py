from __future__ import annotations

from typing import Any

import pytest

from agent_hub.kanbot_client import KanbotPaneNotFound, Pane
from agent_hub.services.state import StateResolver, classify_screen

CLAUDE_IDLE = """
● Plan tayyor. Tasdiqlaysizmi?

╭──────────────────────────────────────────────╮
│ >                                            │
╰──────────────────────────────────────────────╯
  ? for shortcuts
"""

CLAUDE_IDLE_NEW = """
● Tayyor.

────────────────────────────────────────────────
>
────────────────────────────────────────────────
"""

CLAUDE_PERMISSION = """
● Bash(uv run pytest)

 Bash command
   uv run pytest
   Run tests

 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for uv run pytest commands in /repo
   3. No, and tell Claude what to do differently (esc)
"""

CLAUDE_EDIT = """
 Edit file src/app.py
 Do you want to make this edit to app.py?
 ❯ 1. Yes
   2. Yes, allow all edits during this session (shift+tab)
   3. No, and tell Claude what to do differently (esc)
"""

CLAUDE_QUESTION = """
 ☐ Til

 Qaysi tilni tanlaysiz?

 ❯ 1. O'zbek
   2. Русский

 Enter to select · ↑/↓ to navigate · Esc to cancel
"""

# Ruxsat berilgach tool ishlayapti, eski dialog matni ekranda qolgan.
CLAUDE_WORKING_AFTER_APPROVAL = """
 Do you want to proceed?
● Bash(uv run pytest)
  ⎿  Running…
✻ Pondering… (12s · ↑ 1.2k tokens · esc to interrupt)

╭──────────────────────────────────────────────╮
│ >                                            │
╰──────────────────────────────────────────────╯
"""

# Agent javobida "permission" va "Would you like to" so'zlari — KanBot'ning keng regex'i blocked.
CODEX_WORDS_IDLE = """
• Fayllarga permission kerak emas. Would you like to davom ettiramizmi?

›
  100% context left · ? for shortcuts
"""

CODEX_COMMAND = """
Would you like to run the following command?

  $ uv run pytest

› 1. Yes, proceed (y)
  2. Yes, and don't ask again for this command in this session (a)
  3. No, and tell Codex what to do differently (esc)
"""

CODEX_EDITS = """
Would you like to make the following edits?
› 1. Yes, proceed (y)
"""

CODEX_TRUST = """
> You are in /repo

  Do you trust the contents of this directory? Working with untrusted contents comes with
  higher risk of prompt injection.

› 1. Yes, continue
  2. No, quit
"""

CODEX_WORKING = """
• Working (8s • esc to interrupt)

›
"""


@pytest.mark.parametrize(
    ("text", "agent", "expected"),
    [
        (CLAUDE_IDLE, "claude", "idle"),
        (CLAUDE_IDLE_NEW, "claude", "idle"),
        (CLAUDE_PERMISSION, "claude", "blocked"),
        (CLAUDE_EDIT, "claude", "blocked"),
        (CLAUDE_QUESTION, "claude", "blocked"),
        (CLAUDE_WORKING_AFTER_APPROVAL, "claude", "working"),
        (CODEX_WORDS_IDLE, "codex", "idle"),
        (CODEX_COMMAND, "codex", "blocked"),
        (CODEX_EDITS, "codex", "blocked"),
        (CODEX_TRUST, "codex", "blocked"),
        (CODEX_WORKING, "codex", "working"),
        ("", "claude", None),
        ("some output without markers", "codex", None),
        ("I need permission to write", "codex", None),
    ],
)
def test_classify_screen(text: str, agent: str, expected: str | None) -> None:
    assert classify_screen(text, agent) == expected


def test_classify_screen_only_looks_at_tail() -> None:
    old_prompt = "Do you want to proceed?\n" + "\n".join(f"line {i}" for i in range(40))
    assert classify_screen(old_prompt, "claude") is None


def _pane(**overrides: Any) -> Pane:
    data: dict[str, Any] = {
        "id": "p1",
        "agent": "claude",
        "state": "blocked",
        "state_source": "hook",
        "alive": True,
        "last_output_at": 100.0,
    }
    data.update(overrides)
    return Pane.model_validate(data)


class FakeScreen:
    def __init__(self, text: str = "") -> None:
        self.text = text
        self.calls: list[str] = []
        self.error: Exception | None = None

    async def __call__(self, pane_id: str) -> str:
        self.calls.append(pane_id)
        if self.error is not None:
            raise self.error
        return self.text


async def test_idle_notification_is_not_blocked() -> None:
    screen = FakeScreen(CLAUDE_IDLE)
    resolver = StateResolver(screen)
    await resolver.resolve(_pane(state="idle"))
    result = await resolver.resolve(_pane())
    assert (result.state, result.raw_state, result.corrected) == ("idle", "blocked", True)
    assert result.approximate  # ekrandan tuzatilgan


async def test_real_permission_prompt_stays_blocked() -> None:
    resolver = StateResolver(FakeScreen(CLAUDE_PERMISSION))
    await resolver.resolve(_pane(state="idle"))
    result = await resolver.resolve(_pane())
    assert (result.state, result.corrected, result.approximate) == ("blocked", False, False)


async def test_hook_blocked_after_approval_shows_working() -> None:
    resolver = StateResolver(FakeScreen(CLAUDE_WORKING_AFTER_APPROVAL))
    assert (await resolver.resolve(_pane())).state == "working"


async def test_unclear_screen_uses_previous_state() -> None:
    screen = FakeScreen("no markers here")
    resolver = StateResolver(screen)
    # Oldingi holat noma'lum/working — haqiqiy so'rovni yashirmaymiz.
    assert (await resolver.resolve(_pane(id="a"))).state == "blocked"
    await resolver.resolve(_pane(id="b", state="working"))
    assert (await resolver.resolve(_pane(id="b"))).state == "blocked"
    # idle → blocked, ekranda so'rov yo'q: idle notification.
    await resolver.resolve(_pane(id="c", state="idle"))
    assert (await resolver.resolve(_pane(id="c"))).state == "idle"
    # Blocked davomida oldingi holat (idle) saqlanadi.
    assert (await resolver.resolve(_pane(id="c", last_output_at=101.0))).state == "idle"


async def test_read_error_keeps_blocked_unless_previous_idle() -> None:
    screen = FakeScreen()
    screen.error = KanbotPaneNotFound("gone", 404)
    resolver = StateResolver(screen)
    assert (await resolver.resolve(_pane(id="a"))).state == "blocked"
    await resolver.resolve(_pane(id="b", state="idle"))
    assert (await resolver.resolve(_pane(id="b"))).state == "idle"


async def test_codex_screen_state_is_approximate() -> None:
    resolver = StateResolver(FakeScreen(CODEX_WORDS_IDLE))
    working = await resolver.resolve(_pane(agent="codex", state="working", state_source="screen"))
    assert (working.state, working.approximate, working.corrected) == ("working", True, False)
    blocked = await resolver.resolve(_pane(agent="codex", state_source="screen"))
    assert (blocked.state, blocked.approximate) == ("idle", True)

    resolver = StateResolver(FakeScreen(CODEX_COMMAND))
    real = await resolver.resolve(_pane(agent="codex", state_source="screen"))
    assert (real.state, real.approximate) == ("blocked", True)


async def test_non_blocked_states_do_not_read_screen() -> None:
    screen = FakeScreen(CLAUDE_PERMISSION)
    resolver = StateResolver(screen)
    for state in ("working", "idle", "done", "unknown"):
        result = await resolver.resolve(_pane(state=state))
        assert (result.state, result.corrected) == (state, False)
    dead = await resolver.resolve(_pane(alive=False))
    assert dead.state == "blocked"
    assert screen.calls == []


async def test_screen_cached_by_last_output_at() -> None:
    screen = FakeScreen(CLAUDE_IDLE)
    resolver = StateResolver(screen)
    await resolver.resolve(_pane())
    await resolver.resolve(_pane())
    assert len(screen.calls) == 1
    screen.text = CLAUDE_PERMISSION
    assert (await resolver.resolve(_pane(last_output_at=200.0))).state == "blocked"
    assert len(screen.calls) == 2
    # Blocked'dan chiqqach kesh tozalanadi.
    await resolver.resolve(_pane(state="working", last_output_at=200.0))
    await resolver.resolve(_pane(last_output_at=200.0))
    assert len(screen.calls) == 3


async def test_errors_are_not_cached() -> None:
    screen = FakeScreen(CLAUDE_IDLE)
    screen.error = KanbotPaneNotFound("gone", 404)
    resolver = StateResolver(screen)
    assert (await resolver.resolve(_pane())).state == "blocked"
    screen.error = None
    assert (await resolver.resolve(_pane())).state == "idle"
    assert len(screen.calls) == 2


async def test_resolve_all_prunes_missing_panes() -> None:
    screen = FakeScreen(CLAUDE_IDLE)
    resolver = StateResolver(screen)
    await resolver.resolve_all([_pane(id="a", state="idle"), _pane(id="b")])
    results = await resolver.resolve_all([_pane(id="a"), _pane(id="c", state="done")])
    assert {k: v.state for k, v in results.items()} == {"a": "idle", "c": "done"}
    assert resolver._previous == {"a": "idle", "c": "done"}
    assert set(resolver._screens) == {"a"}


async def test_for_kanbot_reads_30_lines() -> None:
    calls: list[tuple[str, int]] = []

    class Client:
        async def read_pane(self, pane_id: str, lines: int = 60) -> Any:
            calls.append((pane_id, lines))
            return type("Read", (), {"text": CLAUDE_IDLE})()

    resolver = StateResolver.for_kanbot(Client())  # type: ignore[arg-type]
    assert (await resolver.resolve(_pane())).state == "idle"
    assert calls == [("p1", 30)]
