import { describe, expect, it } from "vitest";

import type { LivePane } from "../api/types";
import { focusIndex, isTextInput, navigationOrder, nextPaneId, shortcutStep } from "./navigation";

function pane(id: string, state: string, startedAt: number): LivePane {
  return {
    id,
    agent: "claude",
    title: "",
    cwd: "/repo",
    state,
    raw_state: state,
    approximate: false,
    alive: true,
    session_id: "",
    runner_id: "r1",
    runner_name: "mac",
    started_at: startedAt,
    last_output_at: null,
    ended_at: null,
    exit_code: null,
    project_id: "p",
    task: null,
  };
}

describe("navigationOrder", () => {
  it("puts blocked first, then keeps start order regardless of recent output", () => {
    const panes = [pane("c", "working", 30), pane("a", "idle", 10), pane("b", "blocked", 20), pane("d", "blocked", 5)];
    expect(navigationOrder(panes)).toEqual(["d", "b", "a", "c"]);
  });
});

describe("nextPaneId", () => {
  const order = ["a", "b", "c"];

  it("wraps around in both directions", () => {
    expect(nextPaneId(order, "a", 1)).toBe("b");
    expect(nextPaneId(order, "c", 1)).toBe("a");
    expect(nextPaneId(order, "a", -1)).toBe("c");
  });

  it("starts from an end when nothing (or a finished pane) is open", () => {
    expect(nextPaneId(order, null, 1)).toBe("a");
    expect(nextPaneId(order, "gone", -1)).toBe("c");
    expect(nextPaneId([], null, 1)).toBeNull();
  });
});

function key(k: string, mods: Partial<Record<"altKey" | "shiftKey" | "ctrlKey" | "metaKey", boolean>> = {}) {
  return { key: k, altKey: false, shiftKey: false, ctrlKey: false, metaKey: false, ...mods };
}

describe("shortcutStep", () => {
  it("matches Alt+Shift+arrows only", () => {
    expect(shortcutStep(key("ArrowDown", { altKey: true, shiftKey: true }))).toBe(1);
    expect(shortcutStep(key("ArrowUp", { altKey: true, shiftKey: true }))).toBe(-1);
    expect(shortcutStep(key("ArrowDown", { altKey: true }))).toBeNull();
    expect(shortcutStep(key("ArrowDown", { altKey: true, shiftKey: true, metaKey: true }))).toBeNull();
    expect(shortcutStep(key("ArrowLeft", { altKey: true, shiftKey: true }))).toBeNull();
  });
});

function target(tagName: string, className = "", isContentEditable = false) {
  return { tagName, isContentEditable, classList: { contains: (name: string) => name === className } };
}

describe("isTextInput", () => {
  it("skips form fields but not the terminal", () => {
    expect(isTextInput(target("INPUT"))).toBe(true);
    expect(isTextInput(target("TEXTAREA"))).toBe(true);
    expect(isTextInput(target("DIV", "", true))).toBe(true);
    expect(isTextInput(target("TEXTAREA", "xterm-helper-textarea"))).toBe(false);
    expect(isTextInput(target("BUTTON"))).toBe(false);
    expect(isTextInput(null)).toBe(false);
  });
});

describe("focusIndex", () => {
  it("moves within bounds", () => {
    expect(focusIndex(3, 0, "ArrowDown")).toBe(1);
    expect(focusIndex(3, 2, "ArrowDown")).toBe(2);
    expect(focusIndex(3, 0, "ArrowUp")).toBe(0);
    expect(focusIndex(3, 1, "Home")).toBe(0);
    expect(focusIndex(3, 1, "End")).toBe(2);
    expect(focusIndex(3, 1, "Enter")).toBeNull();
    expect(focusIndex(0, 0, "ArrowDown")).toBeNull();
  });
});
