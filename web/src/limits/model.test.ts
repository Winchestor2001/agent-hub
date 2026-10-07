import { describe, expect, it } from "vitest";

import type { AgentLimits } from "../api/types";
import { formatAge, formatLimitPercent, formatResetDateTime, formatResetTime, limitBadges, limitTone } from "./model";

function limits(overrides: Partial<AgentLimits> = {}): AgentLimits {
  return {
    agent: "claude",
    available: true,
    five_hour: null,
    weekly: null,
    updated_at: 1000,
    stale: false,
    ...overrides,
  };
}

describe("limitTone", () => {
  it("50% dan past — ok", () => {
    expect(limitTone(0)).toBe("ok");
    expect(limitTone(49.9)).toBe("ok");
  });

  it("50-74% — warn", () => {
    expect(limitTone(50)).toBe("warn");
    expect(limitTone(74.9)).toBe("warn");
  });

  it("75% va undan yuqori — bad", () => {
    expect(limitTone(75)).toBe("bad");
    expect(limitTone(100)).toBe("bad");
  });
});

describe("limitBadges", () => {
  it("Claude uchun haftalik oynani primary badge qiladi", () => {
    const item = limits({
      agent: "claude",
      five_hour: { used_percent: 10, resets_at: 100 },
      weekly: { used_percent: 20, resets_at: 200 },
    });
    expect(limitBadges(item).map((b) => b.kind)).toEqual(["weekly"]);
  });

  it("Codex uchun 5 soatlik oynani primary badge qiladi", () => {
    const item = limits({
      agent: "codex",
      five_hour: { used_percent: 10, resets_at: 100 },
      weekly: { used_percent: 20, resets_at: 200 },
    });
    expect(limitBadges(item).map((b) => b.kind)).toEqual(["five_hour"]);
  });

  it("faqat mavjud oyna qaytadi", () => {
    const item = limits({ five_hour: { used_percent: 10, resets_at: null } });
    expect(limitBadges(item).map((b) => b.kind)).toEqual(["five_hour"]);
  });

  it("hech qaysi oyna yo'q bo'lsa bo'sh ro'yxat", () => {
    expect(limitBadges(limits())).toEqual([]);
  });
});

describe("formatResetTime", () => {
  it("resets_at yo'q bo'lsa null", () => {
    expect(formatResetTime(null)).toBeNull();
  });

  it("epoch soniyadan soat:daqiqa hosil qiladi", () => {
    expect(formatResetTime(1_700_000_000)).toMatch(/\d{1,2}:\d{2}/);
  });
});

describe("limit formatting helpers", () => {
  it("foizni butun songa tushirib ko'rsatadi", () => {
    expect(formatLimitPercent(18.9)).toBe("18%");
  });

  it("card uchun reset sana-vaqtini chiqaradi", () => {
    expect(formatResetDateTime(null)).toBeNull();
    expect(formatResetDateTime(1_700_000_000)).toContain(":");
  });

  it("yangilangan vaqt yoshini ixcham chiqaradi", () => {
    const now = 1_700_000_000_000;
    expect(formatAge(null, now)).toBeNull();
    expect(formatAge(1_699_999_970, now)).toBe("<1m");
    expect(formatAge(1_699_999_700, now)).toBe("5m");
    expect(formatAge(1_699_992_800, now)).toBe("2h");
    expect(formatAge(1_699_740_800, now)).toBe("3d");
  });
});
