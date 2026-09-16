import { describe, expect, it } from "vitest";

import type { AgentUpdate, LivePane } from "../api/types";
import type { UpdateTone } from "./model";
import { anyRunning, canUpdate, livePaneCount, updateTone } from "./model";

function update(overrides: Partial<AgentUpdate> = {}): AgentUpdate {
  return {
    agent: "claude",
    cask: "claude-code@latest",
    installed_version: "2.1.272",
    latest_version: "2.1.272",
    outdated: false,
    running: false,
    last: null,
    ...overrides,
  };
}

function pane(overrides: Partial<LivePane> = {}): LivePane {
  return { agent: "claude", alive: true, ...overrides } as LivePane;
}

describe("updateTone", () => {
  it("brew yo'q bo'lsa hamma narsadan ustun", () => {
    expect(updateTone(update({ running: true }), false)).toBe("no_brew");
  });

  it("ketayotgan yangilash o'rnatilmagan cask'dan ustun", () => {
    expect(updateTone(update({ running: true, installed_version: null }), true)).toBe("running");
  });

  it("cask o'rnatilmagan", () => {
    expect(updateTone(update({ installed_version: null }), true)).toBe("missing");
  });

  it("oxirgi urinish xato bo'lsa — failed", () => {
    const last = { ok: false, exit_code: 1, finished_at: 1, output: "Error" };
    expect(updateTone(update({ last, outdated: true }), true)).toBe("failed");
  });

  it("yangi versiya bor", () => {
    expect(updateTone(update({ latest_version: "2.1.273", outdated: true }), true)).toBe("outdated");
  });

  it("muvaffaqiyatli yangilangandan keyin — done", () => {
    const last = { ok: true, exit_code: 0, finished_at: 1, output: "" };
    expect(updateTone(update({ last }), true)).toBe("done");
  });

  it("so'nggi versiya noma'lum (tarmoq yo'q)", () => {
    expect(updateTone(update({ latest_version: null }), true)).toBe("unknown");
  });

  it("eng so'nggi versiya", () => {
    expect(updateTone(update(), true)).toBe("current");
  });
});

describe("canUpdate", () => {
  it("faqat brew va cask bor, yangilash ketmayotganda", () => {
    const blocked: UpdateTone[] = ["no_brew", "missing", "running"];
    const allowed: UpdateTone[] = ["failed", "outdated", "done", "unknown", "current"];
    expect(blocked.map(canUpdate)).toEqual([false, false, false]);
    expect(allowed.map(canUpdate)).toEqual([true, true, true, true, true]);
  });
});

describe("anyRunning", () => {
  it("bittasi ketayotgan bo'lsa true", () => {
    expect(anyRunning([update(), update({ agent: "codex", running: true })])).toBe(true);
    expect(anyRunning([update(), update({ agent: "codex" })])).toBe(false);
  });
});

describe("livePaneCount", () => {
  it("faqat shu agentning tirik pane'lari", () => {
    const panes = [pane(), pane({ alive: false }), pane({ agent: "codex" })];
    expect(livePaneCount(panes, "claude")).toBe(1);
    expect(livePaneCount(panes, "codex")).toBe(1);
    expect(livePaneCount(undefined, "claude")).toBe(0);
  });
});
