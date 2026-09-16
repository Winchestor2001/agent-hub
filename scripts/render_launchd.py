"""`launchd/*.plist.in` shablonlaridan LaunchAgent plist'larini render qiladi.

Faqat fayl yozadi: launchd'ga yuklamaydi (bu install skriptining ishi). Yo'llar joriy mashinadan
aniqlanadi — `kanbot` va `uv tool` venv python'i, loyiha `.venv` python'i, agent CLI'lar turgan
real papkalar PATH'ga qo'shiladi (launchd servislari login shell PATH'ini olmaydi).

Tokenlar va API kalitlari o'qilmaydi va plist'ga yozilmaydi: runner tokenni o'zi
`~/.kanbot/config.json` dan oladi, `claude`/`codex` obuna avtorizatsiyasidan foydalanadi.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import shutil
import sys
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from xml.sax.saxutils import escape

REPO = Path(__file__).resolve().parents[1]
TEMPLATE_DIR = REPO / "launchd"
SERVICES = ("kanbot-server", "kanbot-runner", "backend")
DEFAULT_LABEL_PREFIX = "local.agent-hub"
DEFAULT_AGENT_HUB_PORT = 8700
DEFAULT_KANBOT_PORT = 8787
# PATH'dagi papkalari qo'shiladigan CLI'lar: runner agentlarni, backend `backlog` va `brew`ni
# (agent CLI'larini yangilash) ishga tushiradi.
PATH_TOOLS = ("kanbot", "claude", "codex", "brew", "backlog", "node", "uv", "git")
SYSTEM_PATH = ("/usr/bin", "/bin", "/usr/sbin", "/sbin")

_PLACEHOLDER = re.compile(r"@([A-Z_]+)@")
_LABEL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]*$")


class RenderError(ValueError):
    """Render qilib bo'lmaydi: yo'l topilmadi yoki shablon noto'g'ri."""


@dataclass(frozen=True)
class LaunchdContext:
    home: Path
    repo: Path
    kanbot: Path
    kanbot_python: Path
    backend_python: Path
    path: str
    agent_hub_port: int = DEFAULT_AGENT_HUB_PORT
    kanbot_port: int = DEFAULT_KANBOT_PORT
    label_prefix: str = DEFAULT_LABEL_PREFIX

    @property
    def log_dir(self) -> Path:
        return self.home / "Library" / "Logs" / "agent-hub"

    def values(self) -> dict[str, str]:
        return {
            "HOME": str(self.home),
            "REPO": str(self.repo),
            "KANBOT": str(self.kanbot),
            "KANBOT_PYTHON": str(self.kanbot_python),
            "BACKEND_PYTHON": str(self.backend_python),
            "PATH": self.path,
            "AGENT_HUB_PORT": str(self.agent_hub_port),
            "KANBOT_PORT": str(self.kanbot_port),
            "LABEL_PREFIX": self.label_prefix,
            "LOG_DIR": str(self.log_dir),
        }

    def label(self, service: str) -> str:
        return f"{self.label_prefix}.{service}"


def build_path(
    home: Path,
    tool_dirs: Iterable[str],
    is_dir: Callable[[str], bool] = os.path.isdir,
) -> str:
    """Topilgan CLI papkalari, keyin odatiy papkalar; faqat mavjudlari, takrorsiz."""
    candidates = [
        # Tizim papkalari (masalan /usr/bin/git) homebrew'dan oldin kelib qolmasin.
        *(directory for directory in tool_dirs if directory not in SYSTEM_PATH),
        str(home / ".local" / "bin"),
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        *SYSTEM_PATH,
    ]
    result: list[str] = []
    for directory in candidates:
        if (
            directory
            and directory not in result
            and (directory in SYSTEM_PATH or is_dir(directory))
        ):
            result.append(directory)
    return ":".join(result)


def discover(
    *,
    home: Path | None = None,
    repo: Path = REPO,
    which: Callable[[str], str | None] = shutil.which,
    agent_hub_port: int = DEFAULT_AGENT_HUB_PORT,
    kanbot_port: int = DEFAULT_KANBOT_PORT,
    label_prefix: str = DEFAULT_LABEL_PREFIX,
) -> LaunchdContext:
    home = home or Path.home()
    kanbot_raw = which("kanbot")
    if not kanbot_raw:
        raise RenderError("`kanbot` PATH'da topilmadi (uv tool install kanbot)")
    kanbot = Path(kanbot_raw)
    # uv tool: ~/.local/bin/kanbot -> <venv>/bin/kanbot; himoya launcher'i shu venv python'ida.
    kanbot_python = kanbot.resolve().parent / "python"
    backend_python = repo / ".venv" / "bin" / "python"
    tool_dirs = [str(Path(found).parent) for tool in PATH_TOOLS if (found := which(tool))]
    return LaunchdContext(
        home=home,
        repo=repo,
        kanbot=kanbot,
        kanbot_python=kanbot_python,
        backend_python=backend_python,
        path=build_path(home, tool_dirs),
        agent_hub_port=agent_hub_port,
        kanbot_port=kanbot_port,
        label_prefix=label_prefix,
    )


def check_context(ctx: LaunchdContext) -> None:
    for port in (ctx.agent_hub_port, ctx.kanbot_port):
        if not 1 <= port <= 65535:
            raise RenderError(f"noto'g'ri port: {port}")
    if ctx.agent_hub_port == ctx.kanbot_port:
        raise RenderError("Agent Hub va KanBot portlari bir xil bo'lmasligi kerak")
    if not _LABEL.match(ctx.label_prefix):
        raise RenderError(f"noto'g'ri label prefiksi: {ctx.label_prefix!r}")
    executables = {
        "kanbot": ctx.kanbot,
        "KanBot python": ctx.kanbot_python,
        "backend python (make sync)": ctx.backend_python,
    }
    for name, path in executables.items():
        if not path.is_absolute() or not os.access(path, os.X_OK):
            raise RenderError(f"{name} topilmadi yoki bajariladigan emas: {path}")


def render_template(template: str, values: Mapping[str, str]) -> str:
    def substitute(match: re.Match[str]) -> str:
        name = match.group(1)
        if name not in values:
            raise RenderError(f"noma'lum placeholder: @{name}@")
        return escape(values[name])

    rendered = _PLACEHOLDER.sub(substitute, template)
    try:
        plistlib.loads(rendered.encode("utf-8"))
    except Exception as exc:  # plistlib ExpatError/ValueError/InvalidFileException tashlaydi
        raise RenderError(f"render qilingan plist o'qilmaydi: {exc}") from exc
    return rendered


def render_all(ctx: LaunchdContext, template_dir: Path = TEMPLATE_DIR) -> dict[str, str]:
    """`{fayl nomi: plist matni}`; fayl nomi launchd odatiga ko'ra `<label>.plist`."""
    values = ctx.values()
    return {
        f"{ctx.label(service)}.plist": render_template(
            (template_dir / f"{service}.plist.in").read_text(encoding="utf-8"), values
        )
        for service in SERVICES
    }


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else None)
    parser.add_argument("--out", type=Path, required=True, help="plist'lar yoziladigan papka")
    parser.add_argument("--agent-hub-port", type=int, default=DEFAULT_AGENT_HUB_PORT)
    parser.add_argument("--kanbot-port", type=int, default=DEFAULT_KANBOT_PORT)
    parser.add_argument("--label-prefix", default=DEFAULT_LABEL_PREFIX)
    args = parser.parse_args(argv)
    try:
        ctx = discover(
            agent_hub_port=args.agent_hub_port,
            kanbot_port=args.kanbot_port,
            label_prefix=args.label_prefix,
        )
        check_context(ctx)
        rendered = render_all(ctx)
    except RenderError as exc:
        print(f"render_launchd: {exc}", file=sys.stderr)
        return 1
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    for name, text in rendered.items():
        (out / name).write_text(text, encoding="utf-8")
        print(out / name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
