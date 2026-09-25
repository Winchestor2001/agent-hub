import { describe, expect, it } from "vitest";

import { errorMessage } from "../api/banners";
import { ApiError } from "../api/client";
import {
  createTranslator,
  DEFAULT_LOCALE,
  dictionaries,
  format,
  isLocale,
  isMessageKey,
  LOCALE_STORAGE_KEY,
  readLocale,
  writeLocale,
} from "./messages";
import { ru } from "./ru";
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

describe("yuklash xatolari", () => {
  const badType = new ApiError(415, "upload_type_invalid", { name: "run.exe", allowed: [".png", ".mp4"] });

  it("qo'llab-quvvatlanmaydigan tur xabarida ruxsat etilgan turlar sanaladi", () => {
    expect(createTranslator("uz").message(errorMessage(badType))).toBe(
      "«run.exe» — bu fayl turi qo'llab-quvvatlanmaydi. Mumkin: .png, .mp4",
    );
    expect(createTranslator("ru").message(errorMessage(badType))).toContain(".png, .mp4");
  });
});

/** Tilga bog'liq bo'lmagan matnlar: nom, versiya, qisqartma va terminlar. */
const SAME_IN_RU = new Set([
  "app.title",
  "app.backend_version",
  "status.kanbot_online",
  "updates.label",
  "updates.version_unknown",
  "projects.field_id",
  "common.none",
  "board.filter_milestone",
  "board.milestone_progress",
  "card.ac",
  "card.dod",
  "card.subtask_of",
  "task.milestone",
  "task.dod",
  "model.custom_placeholder",
]);

describe("ru", () => {
  it("SAME_IN_RU dan tashqari hamma matn tarjima qilingan", () => {
    const untranslated = Object.entries(uz)
      .filter(([key, text]) => ru[key as keyof typeof uz] === text && !SAME_IN_RU.has(key))
      .map(([key]) => key);
    expect(untranslated).toEqual([]);
  });

  it("backend xato kodlari ruscha chiqadi, noma'lum kod ham", () => {
    const { message } = createTranslator("ru");
    const error = new ApiError(409, "project_exists", { id: "leveling" }, "exists");
    expect(message(errorMessage(error))).toBe("Проект «leveling» уже существует");
    expect(message(errorMessage({ code: "weird_code", params: {}, detail: null }))).toBe(
      "Непредвиденная ошибка (weird_code)",
    );
  });

  it("barcha error.* va banner.* kalitlari kirillcha", () => {
    for (const [key, text] of Object.entries(ru)) {
      if (key.startsWith("error.") || key.startsWith("banner.")) expect(text, key).toMatch(/[а-яё]/i);
    }
  });
});

function memoryStorage(initial: Record<string, string> = {}) {
  const data = new Map(Object.entries(initial));
  return {
    data,
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => {
      data.set(key, value);
    },
  };
}

describe("locale storage", () => {
  it("saqlangan tilni o'qiydi, noto'g'ri qiymatda standart til", () => {
    expect(readLocale(memoryStorage({ [LOCALE_STORAGE_KEY]: "ru" }))).toBe("ru");
    expect(readLocale(memoryStorage({ [LOCALE_STORAGE_KEY]: "en" }))).toBe(DEFAULT_LOCALE);
    expect(readLocale(memoryStorage())).toBe(DEFAULT_LOCALE);
    expect(readLocale(null)).toBe(DEFAULT_LOCALE);
  });

  it("yozadi va storage xatosini yutadi", () => {
    const storage = memoryStorage();
    writeLocale(storage, "ru");
    expect(storage.data.get(LOCALE_STORAGE_KEY)).toBe("ru");

    const broken = {
      getItem: () => {
        throw new Error("SecurityError");
      },
      setItem: () => {
        throw new Error("QuotaExceededError");
      },
    };
    expect(readLocale(broken)).toBe(DEFAULT_LOCALE);
    expect(() => {
      writeLocale(broken, "ru");
    }).not.toThrow();
  });

  it("isLocale faqat mavjud tillar uchun", () => {
    expect(isLocale("uz")).toBe(true);
    expect(isLocale("ru")).toBe(true);
    expect(isLocale("en")).toBe(false);
    expect(isLocale("constructor")).toBe(false);
    expect(isLocale(null)).toBe(false);
  });
});
