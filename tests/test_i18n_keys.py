"""Backend chiqaradigan har bir xato kodining UI lug'atlarida (uz, ru) matni bor.

UI kodni `error.<code>` kalitiga o'giradi; kalit bo'lmasa foydalanuvchi faqat
«Kutilmagan xato (code)» ko'radi. Kodlar manba koddan AST bilan yig'iladi, shuning uchun
yangi kod qo'shilib tarjimasi unutilsa test yiqiladi.
"""

from __future__ import annotations

import ast
import re
from dataclasses import dataclass
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "src" / "agent_hub"
I18N = ROOT / "web" / "src" / "i18n"
LOCALES = ("uz", "ru")

CODE_RE = re.compile(r"^[a-z][a-z0-9_]*$")
KEY_RE = re.compile(r'^\s*"([a-z_]+\.[a-z0-9_]+)"\s*:', re.MULTILINE)

# Chaqiruv nomi → kod turgan pozitsion argument indeksi.
CODE_ARG = {
    "ApiError": 1,
    "RegistryError": 0,
    "FolderError": 0,
    "TranscriptError": 0,
    "SessionError": 0,
    "UploadError": 0,
    "ConfigError": 0,
    "UpdateError": 0,
    "Problem": 0,
    "error_response": 1,
    "error_body": 0,
}
# Funksiya → qaytariladigan tuple'dagi kod indeksi.
CODE_RETURN = {"_describe": 1, "rejection": 0}
# UI'ga hech qachon yetib bormaydigan kodlar: sabab bilan.
NOT_SHOWN_IN_UI = {
    "frontend_not_built": "index.html yo'q — lug'atli UI'ning o'zi yuklanmaydi",
}


@dataclass(frozen=True)
class Found:
    code: str
    kind: str  # "error" | "problem" | "terminal"
    where: str


def _name(func: ast.expr) -> str | None:
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return None


def _strings(node: ast.AST) -> list[str]:
    """Literal kod yoki `"a" if shart else "b"` shoxlari (shartdagi satrlar kod emas)."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return [node.value] if CODE_RE.match(node.value) else []
    if isinstance(node, ast.IfExp):
        return _strings(node.body) + _strings(node.orelse)
    return []


class _Collector(ast.NodeVisitor):
    def __init__(self, path: Path) -> None:
        self.rel = path.relative_to(ROOT)
        self.found: list[Found] = []
        self._functions: list[str] = []

    def _add(self, node: ast.AST, codes: list[str], kind: str = "error") -> None:
        where = f"{self.rel}:{getattr(node, 'lineno', '?')}"
        self.found.extend(Found(code, kind, where) for code in codes)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._visit_function(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._visit_function(node)

    def _visit_function(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
        # `def __init__(..., code: str = "backlog_cli_error")`
        args = node.args
        positional = args.posonlyargs + args.args
        for arg, default in zip(
            positional[len(positional) - len(args.defaults) :], args.defaults, strict=True
        ):
            if arg.arg == "code":
                self._add(default, _strings(default))
        for arg, kw_default in zip(args.kwonlyargs, args.kw_defaults, strict=True):
            if arg.arg == "code" and kw_default is not None:
                self._add(kw_default, _strings(kw_default))
        self._functions.append(node.name)
        self.generic_visit(node)
        self._functions.pop()

    def visit_Return(self, node: ast.Return) -> None:
        index = CODE_RETURN.get(self._functions[-1]) if self._functions else None
        if index is not None and isinstance(node.value, ast.Tuple) and len(node.value.elts) > index:
            self._add(node, _strings(node.value.elts[index]))
        self.generic_visit(node)

    def visit_Assign(self, node: ast.Assign) -> None:
        # Klass atributi yoki `code = "a" if ... else "b"`.
        if any(isinstance(t, ast.Name) and t.id == "code" for t in node.targets):
            self._add(node, _strings(node.value))
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call) -> None:
        name = _name(node.func)
        index = CODE_ARG.get(name) if name else None
        if index is not None and len(node.args) > index:
            self._add(node, _strings(node.args[index]), "problem" if name == "Problem" else "error")
        if name == "_error" and node.args:
            self._add(node, _strings(node.args[0]), "terminal")
        for keyword in node.keywords:
            if keyword.arg == "code":
                self._add(node, _strings(keyword.value))
        self.generic_visit(node)


def collect_codes() -> list[Found]:
    found: list[Found] = []
    for path in sorted(BACKEND.rglob("*.py")):
        if "static" in path.parts:
            continue
        collector = _Collector(path)
        collector.visit(ast.parse(path.read_text(encoding="utf-8"), filename=str(path)))
        found.extend(collector.found)
    return found


def dictionary_keys(locale: str) -> set[str]:
    return set(KEY_RE.findall((I18N / f"{locale}.ts").read_text(encoding="utf-8")))


def accepted_keys(item: Found) -> tuple[str, ...]:
    if item.kind == "terminal":
        return (f"terminal.error_{item.code}",)
    if item.kind == "problem":
        # Health muammolari banner sifatida ko'rsatiladi (banners.ts), qolganlari error.* orqali.
        return (f"error.{item.code}", f"banner.{item.code}")
    return (f"error.{item.code}",)


def missing_translations(found: list[Found], keys: set[str]) -> list[str]:
    return sorted(
        {
            f"{item.code} ({' | '.join(accepted_keys(item))}) — {item.where}"
            for item in found
            if item.code not in NOT_SHOWN_IN_UI
            and not any(key in keys for key in accepted_keys(item))
        }
    )


def test_collector_sees_every_source_kind() -> None:
    """Skaner buzilsa test bo'sh ro'yxat bilan jim o'tib ketmasin."""
    codes = {(item.code, item.kind) for item in collect_codes()}
    sample = {
        ("pane_alive", "error"),  # ApiError(409, "pane_alive")
        ("project_exists", "error"),  # RegistryError("project_exists")
        ("runner_unsafe", "error"),  # SessionError(...)
        ("backlog_locked", "error"),  # klass atributi
        ("backlog_bad_output", "error"),  # code="..." kalit so'zli argument
        ("backlog_cli_error", "error"),  # parametr default'i
        ("shell_enabled", "error"),  # code = "..." if ... else "..."
        ("agent_enabled", "error"),
        ("validation_error", "error"),  # _describe tuple'i
        ("forbidden_origin", "error"),  # HostOriginGuard.rejection
        ("no_runner", "problem"),  # Problem("no_runner")
        ("invalid_keys", "terminal"),  # terminal _error("invalid_keys")
    }
    assert sample <= codes, sorted(sample - codes)


@pytest.mark.parametrize("locale", LOCALES)
def test_every_backend_code_is_translated(locale: str) -> None:
    missing = missing_translations(collect_codes(), dictionary_keys(locale))
    assert not missing, f"{locale}.ts da tarjima yo'q:\n" + "\n".join(missing)


def test_missing_key_is_reported() -> None:
    found = [Found("brand_new_code", "error", "src/agent_hub/x.py:1")]
    assert missing_translations(found, {"error.other"}) == [
        "brand_new_code (error.brand_new_code) — src/agent_hub/x.py:1"
    ]
    assert missing_translations(found, {"error.brand_new_code"}) == []
    problem = [Found("no_runner", "problem", "h.py:1")]
    assert missing_translations(problem, {"banner.no_runner"}) == []
