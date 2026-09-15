import { describe, expect, it } from "vitest";

import type { LivePane, TaskItem } from "../api/types";
import { agentChoices, baseName, elapsed, groupLive, paneActivity, promptPrefix, sessionTasks } from "./model";

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

describe("groupLive", () => {
  it("blocked alohida, tartib saqlanadi", () => {
    const groups = groupLive([
      pane("a", { state: "blocked" }),
      pane("b"),
      pane("c", { state: "blocked" }),
      pane("d", { state: "idle" }),
    ]);
    expect(groups.blocked.map((p) => p.id)).toEqual(["a", "c"]);
    expect(groups.others.map((p) => p.id)).toEqual(["b", "d"]);
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
