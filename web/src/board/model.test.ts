import { describe, expect, it } from "vitest";

import type { LivePane, Milestone, TaskItem } from "../api/types";
import {
  ALL,
  collectLabels,
  filterTasks,
  groupByStatus,
  isInProgressStatus,
  milestoneId,
  milestoneTitle,
  NO_MILESTONE,
  shouldOpenSession,
  slugify,
  splitLines,
  splitList,
} from "./model";

function task(id: string, overrides: Partial<TaskItem> = {}): TaskItem {
  return {
    id,
    title: id,
    status: "To Do",
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
    ...overrides,
  };
}

const milestones: Milestone[] = [
  { id: "m-0", title: "M1 MVP", done: 1, total: 3, completed: false },
  { id: "m-1", title: "M2 Avtozapusk", done: 0, total: 1, completed: false },
];

const ids = (tasks: TaskItem[]) => tasks.map((t) => t.id);

describe("groupByStatus", () => {
  it("config tartibi, bo'sh ustunlar qoladi, noma'lum status oxirida, ordinal keyin ID", () => {
    const columns = groupByStatus(
      [
        task("TASK-10", { status: "To Do" }),
        task("TASK-2", { status: "To Do" }),
        task("TASK-3", { status: "Review" }),
        task("TASK-1", { status: "To Do", ordinal: 5 }),
      ],
      ["To Do", "In Progress", "Done"],
    );
    expect(columns.map((c) => [c.status, ids(c.tasks)])).toEqual([
      ["To Do", ["TASK-1", "TASK-2", "TASK-10"]],
      ["In Progress", []],
      ["Done", []],
      ["Review", ["TASK-3"]],
    ]);
  });

  it("tugagan ustun: oxirgi yangilangani tepada", () => {
    const columns = groupByStatus(
      [
        task("TASK-1", { status: "Done", ordinal: 1, updated_at: "2026-09-15T10:00:00Z" }),
        task("TASK-2", { status: "Done", ordinal: 2, updated_at: "2026-09-16T09:00:00Z" }),
        task("TASK-3", { status: "Done", ordinal: 3, created_at: "2026-09-15T08:00:00Z" }),
        task("TASK-4", { status: "Done", ordinal: 4, updated_at: "2026-09-15T18:00:00Z" }),
      ],
      ["To Do", "Done"],
    );
    expect(columns.map((c) => [c.status, ids(c.tasks)])).toEqual([
      ["To Do", []],
      ["Done", ["TASK-2", "TASK-4", "TASK-1", "TASK-3"]],
    ]);
  });

  it("tugagan ustun sanasizlari pastda, ular orasida ID teskari", () => {
    const columns = groupByStatus(
      [
        task("TASK-2", { status: "Done" }),
        task("TASK-10", { status: "Done" }),
        task("TASK-1", { status: "Done", updated_at: "2026-09-15T10:00:00Z" }),
      ],
      ["To Do", "Done"],
    );
    expect(columns.map((c) => [c.status, ids(c.tasks)])).toEqual([
      ["To Do", []],
      ["Done", ["TASK-1", "TASK-10", "TASK-2"]],
    ]);
  });
});

describe("filterTasks", () => {
  const tasks = [
    task("A", { labels: ["backend", "bug"], milestone: "m-0" }),
    task("B", { labels: ["Client"], milestone: "M2 Avtozapusk" }),
    task("C", { labels: [] }),
  ];

  it("filtrsiz — hammasi", () => {
    expect(ids(filterTasks(tasks, { labels: [], milestone: ALL }, milestones))).toEqual(["A", "B", "C"]);
  });

  it("label — tanlanganlarning hammasi, registrsiz (CLI --labels kabi)", () => {
    expect(ids(filterTasks(tasks, { labels: ["client"], milestone: ALL }, milestones))).toEqual(["B"]);
    expect(ids(filterTasks(tasks, { labels: ["BUG", "backend"], milestone: ALL }, milestones))).toEqual(["A"]);
    expect(ids(filterTasks(tasks, { labels: ["bug", "client"], milestone: ALL }, milestones))).toEqual([]);
  });

  it("milestone — ID yoki sarlavha bo'yicha, milestone'siz", () => {
    expect(ids(filterTasks(tasks, { labels: [], milestone: "m-1" }, milestones))).toEqual(["B"]);
    expect(ids(filterTasks(tasks, { labels: [], milestone: NO_MILESTONE }, milestones))).toEqual(["C"]);
    expect(ids(filterTasks(tasks, { labels: ["backend"], milestone: "m-1" }, milestones))).toEqual([]);
  });
});

describe("milestone", () => {
  it("ID'ga keltiriladi, noma'lumi o'zicha qoladi", () => {
    expect(milestoneId("m2 avtozapusk", milestones)).toBe("m-1");
    expect(milestoneId(" ", milestones)).toBeNull();
    expect(milestoneId("m-9", milestones)).toBe("m-9");
    expect(milestoneTitle("m-0", milestones)).toBe("M1 MVP");
    expect(milestoneTitle("m-9", milestones)).toBe("m-9");
  });
});

describe("collectLabels", () => {
  it("config tartibida, keyin vazifalardagilar alifbo bo'yicha, takrorsiz", () => {
    const tasks = [task("A", { labels: ["zeta", "Bug"] }), task("B", { labels: ["alpha", "zeta"] })];
    expect(collectLabels(["bug", "backend"], tasks)).toEqual(["bug", "backend", "alpha", "zeta"]);
  });
});

describe("slugify va ro'yxatlar", () => {
  it("loyiha ID", () => {
    expect(slugify("Hub nusxasi")).toBe("hub-nusxasi");
    expect(slugify("  O'zbek  Loyiha!! ")).toBe("o-zbek-loyiha");
    expect(slugify("Café")).toBe("cafe");
    expect(slugify("Проект")).toBe("");
    expect(slugify("a".repeat(39) + "-b")).toMatch(/^[a-z0-9][a-z0-9-]{0,39}$/);
    expect(slugify("a".repeat(39) + "-b")).toBe("a".repeat(39));
  });

  it("vergul/qator bo'yicha ajratish", () => {
    expect(splitList("backend, bug,\n bug ,,client")).toEqual(["backend", "bug", "client"]);
    expect(splitLines("Birinchi, shart\n\n Ikkinchi ")).toEqual(["Birinchi, shart", "Ikkinchi"]);
  });
});

describe("isInProgressStatus", () => {
  it("keng tarqalgan nomlarni registr va ajratuvchidan qat'i nazar taniydi", () => {
    for (const status of ["In Progress", "in-progress", "IN_PROGRESS", "doing", "WIP", "В работе", "jarayonda"]) {
      expect(isInProgressStatus(status)).toBe(true);
    }
  });

  it("boshqa ustunlar uchun false", () => {
    for (const status of ["To Do", "Done", "Blocked", "", "progress report", "in progress soon"]) {
      expect(isInProgressStatus(status)).toBe(false);
    }
  });
});

describe("shouldOpenSession", () => {
  const live = [{ id: "pane-1" } as LivePane];

  it("jarayonga o'tgan va sessiyasiz vazifa uchun ochiladi", () => {
    expect(shouldOpenSession(task("A"), "In Progress")).toBe(true);
  });

  it("tirik sessiyasi bor vazifa uchun ochilmaydi", () => {
    expect(shouldOpenSession(task("A", { sessions: live }), "In Progress")).toBe(false);
  });

  it("boshqa statusda yoki noma'lum vazifada ochilmaydi", () => {
    expect(shouldOpenSession(task("A"), "Done")).toBe(false);
    expect(shouldOpenSession(undefined, "In Progress")).toBe(false);
  });
});
