/**
 * Tur darajasidagi kafolatlar: bu fayl bundle'ga kirmaydi, faqat `tsc` tekshiradi.
 * `@ts-expect-error` ostidagi qator xato bermay qolsa, tsc o'zi xato beradi.
 */
import type { Dictionary, Translator } from "./messages";
import { uz } from "./uz";

// Kalit yetishmagan lug'at.
// @ts-expect-error — "status.kanbot_online" va boshqa kalitlar yo'q
export const incomplete: Dictionary = { "app.title": "Agent Hub" };

// Ortiqcha (noma'lum) kalit.
export const extra: Dictionary = {
  ...uz,
  // @ts-expect-error — lug'atda bunday kalit yo'q
  "app.unknown": "?",
};

declare const translator: Translator;

// @ts-expect-error — "{version}" parametri majburiy
translator.t("app.backend_version");
// @ts-expect-error — parametr nomi noto'g'ri
translator.t("app.backend_version", { ver: "1" });
// @ts-expect-error — parametrsiz kalitga parametr berilmaydi
translator.t("panel.board", { x: 1 });
translator.t("app.backend_version", { version: "0.1.0" });
translator.t("panel.board");
