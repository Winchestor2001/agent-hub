from __future__ import annotations

import pytest

from agent_hub.services.models import CATALOG, MAX_MODEL_LENGTH, catalog, is_valid_model

# Foydalanuvchi so'ragan eski modellar: terminal pickerida yo'q, to'liq ID bilan ishlaydi.
LEGACY_OPUS = ("claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6")


def test_catalog_ids_are_unique_and_valid() -> None:
    ids = [model.id for model in CATALOG]
    assert len(ids) == len(set(ids))
    assert all(is_valid_model(model_id) for model_id in ids)


def test_catalog_has_requested_legacy_and_current_models() -> None:
    by_id = {model.id: model for model in CATALOG}
    for model_id in LEGACY_OPUS:
        assert by_id[model_id].group == "legacy"
    assert by_id["claude-opus-5-5"].group == "current"
    assert by_id["claude-haiku-4-5-20251001"].group == "current"
    assert {"opus", "sonnet", "haiku", "fable", "best", "opusplan"} <= {
        model.id for model in CATALOG if model.group == "alias"
    }


def test_catalog_dicts_have_stable_shape() -> None:
    assert all(set(item) == {"id", "label", "group"} for item in catalog())


@pytest.mark.parametrize(
    "value",
    [
        "opus",
        "opus[1m]",
        "claude-opus-4-8",
        "claude-haiku-4-5-20251001",
        "anthropic.claude-opus-4-8",
        "us.anthropic.claude-sonnet-5",
    ],
)
def test_valid_model_ids(value: str) -> None:
    assert is_valid_model(value)


def test_provider_arn_is_valid() -> None:
    arn = "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.anthropic.claude-opus-4-8"
    assert is_valid_model(arn)


@pytest.mark.parametrize(
    "value",
    [
        "",
        " ",
        "opus 4",  # ikkinchi token
        " opus",
        "opus ",
        "opus\n/exit",  # ikkinchi buyruq
        "opus\r",
        "opus\n",
        "opus\t",
        "\x1bopus",
        "-opus",  # bayroqqa o'xshaydi
        ".opus",
        "opus;ls",
        "opus$(x)",
        "opus`x`",
        "opus[1m",
        "[1m]",
        "opus[1m]x",
        "opus[]",
        "opus[1m][1m]",
        "claude-opus-4-1@20250805",
        "a" * (MAX_MODEL_LENGTH + 1),
    ],
)
def test_invalid_model_ids(value: str) -> None:
    assert not is_valid_model(value)


def test_max_length_boundary() -> None:
    assert is_valid_model("a" * MAX_MODEL_LENGTH)
