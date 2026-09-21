import { describe, expect, it } from "vitest";

import type { LivePane, PastSession, TaskItem } from "../api/types";
import {
  agentChoices,
  baseName,
  elapsed,
  paneActivity,
  promptPrefix,
  pruneSelection,
  sessionKey,
  sessionTasks,
  splitByProject,
  toggleKey,
} from "./model";

function pane(id: string, overrides: Partial<LivePane> = {}): LivePane {
  return {
    id,
    agent: "claude",
    title: "",
    cwd: "/repo",
    state: "working",
    raw_state: "working",
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
    ...overrides,
  };
}

function task(id: string, status: string): TaskItem {
  return {
    id,
    title: id,
    status,
    type: null,
    priority: null,
    assignees: [],
    labels: [],
    milestone: null,
    parent_task_id: null,
    acceptance_criteria_completed: 0,
    acceptance_criteria_count: 0,
    ordinal: null,
    created_at: null,
    updated_at: null,
    is_ready: true,
    dod_completed: 0,
    dod_count: 0,
    sessions: [],
  };
}

describe("splitByProject", () => {
  it("tanlangan loyiha pane'lari alohida, loyihasizlar boshqalar qatorida", () => {
    const panes = [
      pane("a", { project_id: "p1" }),
      pane("b", { project_id: "p2" }),
      pane("c", { project_id: null }),
      pane("d", { project_id: "p1", state: "blocked" }),
    ];
    const split = splitByProject(panes, "p1");
    expect(split.mine.map((p) => p.id)).toEqual(["a", "d"]);
    expect(split.others.map((p) => p.id)).toEqual(["b", "c"]);
  });

  it("holatdan qat'i nazar kelgan tartib saqlanadi (blocked joyidan ko'chmaydi)", () => {
    const panes = [pane("a", { state: "idle" }), pane("b", { state: "blocked" }), pane("c", { state: "working" })];
    expect(splitByProject(panes, null).mine.map((p) => p.id)).toEqual(["a", "b", "c"]);
    expect(splitByProject(panes, "p1").others.map((p) => p.id)).toEqual(["a", "b", "c"]);
  });

  it("loyiha tanlanmagan bo'lsa hammasi ko'rinadi", () => {
    const split = splitByProject([pane("a", { project_id: "p1" }), pane("b", { project_id: null })], null);
    expect(split.mine.map((p) => p.id)).toEqual(["a", "b"]);
    expect(split.others).toEqual([]);
  });
});

describe("elapsed", () => {
  it("birliklar chegaralarda", () => {
    expect(elapsed(100, 100)).toEqual({ unit: "seconds", count: 0 });
    expect(elapsed(100, 159.9)).toEqual({ unit: "seconds", count: 59 });
    expect(elapsed(0, 60)).toEqual({ unit: "minutes", count: 1 });
    expect(elapsed(0, 7199)).toEqual({ unit: "hours", count: 1 });
    expect(elapsed(0, 86400 * 3 + 5)).toEqual({ unit: "days", count: 3 });
    expect(elapsed(200, 100)).toEqual({ unit: "seconds", count: 0 });
  });

  it("pane faolligi — oxirgi chiqish, bo'lmasa boshlanish", () => {
    expect(paneActivity(pane("a", { last_output_at: 150 }))).toBe(150);
    expect(paneActivity(pane("a"))).toBe(100);
    expect(paneActivity(pane("a", { started_at: null }))).toBeNull();
  });
});

describe("prompt va tanlovlar", () => {
  it("prefiks vazifa ID bilan", () => {
    expect(promptPrefix("Работай только над {task_id}. {task_id}!", "TASK-7")).toBe(
      "Работай только над TASK-7. TASK-7!",
    );
  });

  it("agentlar: onlayn holati, KanBot noma'lum bo'lsa null", () => {
    expect(agentChoices(["claude", "codex"], ["claude", "shell"])).toEqual([
      { agent: "claude", online: true },
      { agent: "codex", online: false },
    ]);
    expect(agentChoices(["claude"], undefined)).toEqual([{ agent: "claude", online: null }]);
  });

  it("vazifalar: yakuniy status chiqmaydi (tanlangandan tashqari), ID bo'yicha", () => {
    const tasks = [task("TASK-10", "To Do"), task("TASK-2", "Done"), task("TASK-9", "In Progress"), task("TASK-3", "Done")];
    const statuses = ["To Do", "In Progress", "Done"];
    expect(sessionTasks(tasks, statuses).map((t) => t.id)).toEqual(["TASK-9", "TASK-10"]);
    expect(sessionTasks(tasks, statuses, "TASK-3").map((t) => t.id)).toEqual(["TASK-3", "TASK-9", "TASK-10"]);
    expect(sessionTasks(tasks, ["Done"]).length).toBe(4);
  });

  it("papka nomi", () => {
    expect(baseName("/a/b/web/")).toBe("web");
    expect(baseName("/")).toBe("/");
  });
});

describe("o'tgan sessiyalar tanlovi", () => {
  function past(session_id: string, overrides: Partial<PastSession> = {}): PastSession {
    return {
      agent: "claude",
      session_id,
      cwd: "/repo",
      name: "repo",
      title: null,
      recap: null,
      turns: 1,
      started_at: null,
      mtime: 1,
      active: false,
      runner_id: "r1",
      project_id: "p",
      task: null,
      ...overrides,
    };
  }

  it("kalit va almashtirish", () => {
    expect(sessionKey(past("a"))).toBe("claude:a");
    const once = toggleKey(new Set(), "claude:a");
    expect([...once]).toEqual(["claude:a"]);
    expect([...toggleKey(once, "claude:a")]).toEqual([]);
  });

  it("yo'qolgan va ochiq sessiyalar tanlovdan chiqadi", () => {
    const sessions = [past("a"), past("b", { active: true }), past("c", { agent: "codex" })];
    const selected = new Set(["claude:a", "claude:b", "codex:c", "claude:gone"]);
    expect([...pruneSelection(selected, sessions)]).toEqual(["claude:a", "codex:c"]);
  });
});
