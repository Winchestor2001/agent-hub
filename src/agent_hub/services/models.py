"""Claude modellari katalogi va sessiya ichida model tanlash uchun ID tekshiruvi.

Katalog Anthropic hujjatlaridan (models overview, model-config) olingan; terminaldagi `/model`
pickeri Opus 4.7/4.8 kabi eski modellarni ko'rsatmaydi, lekin to'liq ID yozilsa ular ishlaydi.
Foydalanuvchi ro'yxatda yo'q ID (yangi model yoki provayder ID'si) ham kirita oladi.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Literal

ModelGroup = Literal["current", "legacy", "alias"]

MAX_MODEL_LENGTH = 200
# `/model` ga bitta token beriladi: bo'shliq va boshqaruv belgilari yo'q, boshi harf yoki raqam
# (`-flag` bo'lmasin). Ruxsat: alias, to'liq ID, `opus[1m]`, provayder ID'lari (`:` `/` `.`).
MODEL_ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/-]*(\[[A-Za-z0-9]{1,8}\])?")


@dataclass(frozen=True)
class ClaudeModel:
    id: str
    label: str
    group: ModelGroup

    def as_dict(self) -> dict[str, str]:
        return {"id": self.id, "label": self.label, "group": self.group}


CATALOG: tuple[ClaudeModel, ...] = (
    ClaudeModel("claude-fable-5-1", "Fable 5.1", "current"),
    ClaudeModel("claude-opus-5-5", "Opus 5.5", "current"),
    ClaudeModel("claude-sonnet-5", "Sonnet 5", "current"),
    ClaudeModel("claude-haiku-4-5-20251001", "Haiku 4.5", "current"),
    ClaudeModel("claude-opus-5", "Opus 5", "legacy"),
    ClaudeModel("claude-opus-4-8", "Opus 4.8", "legacy"),
    ClaudeModel("claude-opus-4-7", "Opus 4.7", "legacy"),
    ClaudeModel("claude-opus-4-6", "Opus 4.6", "legacy"),
    ClaudeModel("claude-sonnet-4-6", "Sonnet 4.6", "legacy"),
    ClaudeModel("best", "best", "alias"),
    ClaudeModel("fable", "fable", "alias"),
    ClaudeModel("opus", "opus", "alias"),
    ClaudeModel("sonnet", "sonnet", "alias"),
    ClaudeModel("haiku", "haiku", "alias"),
    ClaudeModel("opusplan", "opusplan", "alias"),
    ClaudeModel("opus[1m]", "opus[1m]", "alias"),
    ClaudeModel("sonnet[1m]", "sonnet[1m]", "alias"),
)


def is_valid_model(value: str) -> bool:
    return len(value) <= MAX_MODEL_LENGTH and MODEL_ID_RE.fullmatch(value) is not None


def catalog() -> list[dict[str, str]]:
    return [model.as_dict() for model in CATALOG]
