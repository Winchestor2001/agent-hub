import { describe, expect, it } from "vitest";

import type { SessionModel } from "../api/types";
import { chosenModel, CUSTOM_MODEL, groupModels, isValidModelId, MAX_MODEL_LENGTH, modelBlockedReason } from "./models";

const model = (id: string, group: SessionModel["group"]): SessionModel => ({ id, label: id, group });

describe("isValidModelId", () => {
  it("alias, to'liq ID va provayder ID'larini qabul qiladi", () => {
    for (const id of ["opus", "opus[1m]", "claude-opus-4-8", "claude-haiku-4-5-20251001", "us.anthropic.claude-sonnet-5"]) {
      expect(isValidModelId(id), id).toBe(true);
    }
    expect(isValidModelId("a".repeat(MAX_MODEL_LENGTH))).toBe(true);
  });

  it("bo'shliq, yangi qator, bayroq va uzun ID'ni rad etadi", () => {
    const bad = ["", " ", "opus 4", "opus\n/exit", "opus\r", "-opus", "opus;ls", "opus[1m", "[1m]", "opus[1m]x"];
    for (const id of bad) expect(isValidModelId(id), JSON.stringify(id)).toBe(false);
    expect(isValidModelId("a".repeat(MAX_MODEL_LENGTH + 1))).toBe(false);
  });

  it("oxiridagi yangi qatorni ham rad etadi", () => {
    expect(isValidModelId("opus\n")).toBe(false);
  });
});

describe("groupModels", () => {
  it("guruh tartibi: joriy, eski, alias; katalog tartibi saqlanadi", () => {
    const groups = groupModels([
      model("opus", "alias"),
      model("claude-opus-4-8", "legacy"),
      model("claude-sonnet-5", "current"),
      model("claude-opus-4-7", "legacy"),
    ]);
    expect(groups.map((g) => g.group)).toEqual(["current", "legacy", "alias"]);
    expect(groups[1]?.models.map((m) => m.id)).toEqual(["claude-opus-4-8", "claude-opus-4-7"]);
  });

  it("bo'sh guruhni tushirib qoldiradi", () => {
    expect(groupModels([model("opus", "alias")]).map((g) => g.group)).toEqual(["alias"]);
    expect(groupModels([])).toEqual([]);
  });
});

describe("modelBlockedReason", () => {
  it("faqat tirik va idle sessiyada ochiq", () => {
    expect(modelBlockedReason({ alive: true, state: "idle" })).toBeNull();
    expect(modelBlockedReason({ alive: true, state: "working" })).toBe("model.busy");
    expect(modelBlockedReason({ alive: true, state: "blocked" })).toBe("model.busy");
    expect(modelBlockedReason({ alive: false, state: "idle" })).toBe("model.ended");
  });
});

describe("chosenModel", () => {
  it("tanlangan qator yoki qo'lda kiritilgan ID", () => {
    expect(chosenModel("claude-opus-4-8", "")).toBe("claude-opus-4-8");
    expect(chosenModel(CUSTOM_MODEL, "  claude-opus-9  ")).toBe("claude-opus-9");
  });

  it("tanlanmagan yoki yaroqsiz bo'lsa null", () => {
    expect(chosenModel("", "")).toBeNull();
    expect(chosenModel(CUSTOM_MODEL, "")).toBeNull();
    expect(chosenModel(CUSTOM_MODEL, "opus 4")).toBeNull();
  });
});
