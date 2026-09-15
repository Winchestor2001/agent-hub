"""Haqiqiy KanBot bilan himoya launcher'i (opt-in: `pytest -m integration`).

KanBot o'z venv python'ida, vaqtinchalik KANBOT_HOME va bo'sh port bilan ishga tushiriladi —
foydalanuvchining ~/.kanbot va 8787 porti ishlatilmaydi.
"""

from __future__ import annotations

import os
import shutil
import socket
import subprocess
import time
from collections.abc import Iterator
from pathlib import Path

import httpx
import pytest
from websockets.exceptions import InvalidStatus
from websockets.sync.client import connect
from websockets.typing import Origin

pytestmark = pytest.mark.integration

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "kanbot_guarded_server.py"


def _kanbot_python() -> Path:
    kanbot = shutil.which("kanbot")
    if kanbot is None:
        pytest.skip("kanbot topilmadi")
    python = Path(kanbot).resolve().parent / "python"
    if not python.exists():
        pytest.skip(f"KanBot venv python topilmadi: {python}")
    return python


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


@pytest.fixture(scope="module")
def kanbot_url(tmp_path_factory: pytest.TempPathFactory) -> Iterator[str]:
    home = tmp_path_factory.mktemp("kanbot-home")
    port = _free_port()
    env = {**os.environ, "KANBOT_HOME": str(home)}
    proc = subprocess.Popen(
        [str(_kanbot_python()), str(SCRIPT), "--port", str(port)],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    url = f"http://127.0.0.1:{port}"
    try:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            try:
                if httpx.get(f"{url}/api/health", timeout=0.5).status_code == 200:
                    break
            except httpx.TransportError:
                time.sleep(0.2)
        else:
            proc.kill()
            output = proc.communicate()[0].decode(errors="replace")
            pytest.fail(f"KanBot ishga tushmadi:\n{output}")
        yield url
    finally:
        proc.terminate()
        proc.wait(timeout=10)


def test_health_without_origin(kanbot_url: str) -> None:
    resp = httpx.get(f"{kanbot_url}/api/health")
    assert resp.status_code == 200
    assert resp.json()["ok"] is True


def test_own_ui_origin_allowed(kanbot_url: str) -> None:
    resp = httpx.get(f"{kanbot_url}/api/health", headers={"Origin": kanbot_url})
    assert resp.status_code == 200


def test_foreign_origin_cannot_start_pane(kanbot_url: str) -> None:
    resp = httpx.post(
        f"{kanbot_url}/api/panes/start",
        headers={"Origin": "https://evil.example"},
        json={"agent": "claude", "prompt": "x", "cwd": str(ROOT)},
    )
    assert resp.status_code == 403


def test_foreign_host_rejected(kanbot_url: str) -> None:
    resp = httpx.get(f"{kanbot_url}/api/health", headers={"Host": "evil.example"})
    assert resp.status_code == 403


def test_ws_web_foreign_origin_rejected(kanbot_url: str) -> None:
    ws_url = kanbot_url.replace("http://", "ws://") + "/ws/web"
    with (
        pytest.raises(InvalidStatus) as exc,
        connect(ws_url, origin=Origin("https://evil.example")),
    ):
        pass
    assert exc.value.response.status_code == 403


def test_ws_web_without_origin_allowed(kanbot_url: str) -> None:
    ws_url = kanbot_url.replace("http://", "ws://") + "/ws/web"
    with connect(ws_url, open_timeout=5) as ws:
        ws.close()
