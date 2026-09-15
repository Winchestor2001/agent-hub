import { describe, expect, it } from "vitest";

import type { LivePane } from "../api/types";
import { blockedIds, blockedTitle, newlyBlocked } from "./alerts";

function pane(id: string, state: string): LivePane {
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
    started_at: 100,
    last_output_at: null,
    ended_at: null,
    exit_code: null,
    project_id: "p",
    task: null,
  };
}

describe("blockedTitle", () => {
  it("prefixes the count only when something is blocked", () => {
    expect(blockedTitle("Agent Hub", 0)).toBe("Agent Hub");
    expect(blockedTitle("Agent Hub", 2)).toBe("(2) Agent Hub");
  });
});

describe("newlyBlocked", () => {
  it("stays silent on the first load", () => {
    expect(newlyBlocked(null, [pane("a", "blocked")])).toEqual([]);
  });

  it("returns panes that just became blocked", () => {
    const before = blockedIds([pane("a", "blocked"), pane("b", "working")]);
    expect(before).toEqual(new Set(["a"]));
    const now = [pane("a", "blocked"), pane("b", "blocked"), pane("c", "blocked"), pane("d", "idle")];
    expect(newlyBlocked(before, now).map((p) => p.id)).toEqual(["b", "c"]);
  });

  it("notifies again after a pane was answered and blocks once more", () => {
    const answered = blockedIds([pane("a", "working")]);
    expect(newlyBlocked(answered, [pane("a", "blocked")]).map((p) => p.id)).toEqual(["a"]);
  });
});
