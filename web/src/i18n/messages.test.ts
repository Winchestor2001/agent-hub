import { describe, expect, it } from "vitest";

import { createTranslator, dictionaries, format, isMessageKey } from "./messages";
import { uz } from "./uz";

const placeholders = (text: string) => [...text.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();

describe("format", () => {
  it("o'rinbosarlarni almashtiradi", () => {
    expect(format("{a} va {b}", { a: "x", b: 2 })).toBe("x va 2");
    expect(format("Mumkin: {allowed}", { allowed: ["To Do", "Done"] })).toBe("Mumkin: To Do, Done");
  });

  it("yo'q yoki obyekt parametr — «…»", () => {
    expect(format("Papka: {path}")).toBe("Papka: …");
    expect(format("{x}", { x: { nested: true } })).toBe("…");
    expect(format("{toString}")).toBe("…");
  });
});

describe("translator", () => {
  it("uz lug'atidan matn beradi", () => {
    const { t, message } = createTranslator("uz");
    expect(t("projects.tasks", { count: 3 })).toBe("3 ta vazifa");
    expect(message({ key: "error.project_exists", params: { id: "leveling" } })).toBe(
      "«leveling» loyihasi allaqachon bor",
    );
  });

  it("isMessageKey faqat lug'atdagi kalitlar uchun", () => {
    expect(isMessageKey("error.backlog_not_found")).toBe(true);
    expect(isMessageKey("error.nope")).toBe(false);
    expect(isMessageKey("constructor")).toBe(false);
  });

  it("barcha tillarda o'rinbosarlar uz bilan bir xil", () => {
    for (const dictionary of Object.values(dictionaries)) {
      for (const [key, text] of Object.entries(uz)) {
        expect(placeholders(dictionary[key as keyof typeof uz]), key).toEqual(placeholders(text));
      }
    }
  });
});
