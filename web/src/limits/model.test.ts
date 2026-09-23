import { describe, expect, it } from "vitest";

import type { AgentLimits } from "../api/types";
import { formatResetTime, limitBadges, limitTone } from "./model";

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
  it("ikkala oyna mavjud bo'lsa ikkalasi ham qaytadi", () => {
    const item = limits({
      five_hour: { used_percent: 10, resets_at: 100 },
      weekly: { used_percent: 20, resets_at: 200 },
    });
    expect(limitBadges(item).map((b) => b.kind)).toEqual(["five_hour", "weekly"]);
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
