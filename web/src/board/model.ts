import type { LivePane, Milestone, TaskItem } from "../api/types";

/** Milestone filtri: hammasi, milestone'siz yoki aniq milestone ID. */
export const ALL = "__all__";
export const NO_MILESTONE = "__none__";

export interface BoardFilter {
  /** Tanlangan labellar — vazifada ulardan istalgani bo'lsa ko'rinadi; bo'sh — filtr yo'q. */
  labels: readonly string[];
  milestone: string;
}

export const EMPTY_FILTER: BoardFilter = { labels: [], milestone: ALL };

/** Birinchi status — kutilmoqda, oxirgisi — tugagan, oradagilar — jarayonda (config tartibi). */
export function statusTone(index: number, count: number): "tone-todo" | "tone-progress" | "tone-done" {
  if (index === 0) return "tone-todo";
  return index === count - 1 ? "tone-done" : "tone-progress";
}

export interface Column {
  status: string;
  tasks: TaskItem[];
}

/**
 * "Jarayonda" ustunimi? Backlog config'da ustun nomi erkin, shuning uchun keng tarqalgan
 * nomlar bo'yicha taxmin qilinadi; mos kelmasa hech narsa ochilmaydi.
 */
const IN_PROGRESS = /^(in[ _-]*progress|doing|wip|в[ _-]*работе|jarayon(da)?)$/i;

export function isInProgressStatus(status: string): boolean {
  return IN_PROGRESS.test(status.trim());
}

/** Vazifa jarayonga o'tdi va tirik sessiyasi yo'q — sessiya dialogi ochilsin. */
export function shouldOpenSession(task: TaskItem | undefined, status: string): boolean {
  return isInProgressStatus(status) && task !== undefined && task.sessions.length === 0;
}

/** Tugagan ustun — config'dagi oxirgi status; unga o'tgan vazifaning agenti endi kerak emas. */
export function isDoneStatus(status: string, statuses: readonly string[]): boolean {
  return statuses.length > 0 && status === statuses[statuses.length - 1];
}

/** Vazifa tugadi — shu vazifaga bog'langan tirik pane'lar yopishga taklif qilinadi. */
export function sessionsToClose(
  task: TaskItem | undefined,
  status: string,
  statuses: readonly string[],
): LivePane[] {
  if (!task || !isDoneStatus(status, statuses)) return [];
  return task.sessions.filter((pane) => pane.alive);
}

const norm = (value: string) => value.trim().toLowerCase();

function byOrdinalThenId(a: TaskItem, b: TaskItem): number {
  const ao = a.ordinal ?? Number.POSITIVE_INFINITY;
  const bo = b.ordinal ?? Number.POSITIVE_INFINITY;
  if (ao !== bo) return ao - bo;
  return a.id.localeCompare(b.id, undefined, { numeric: true });
}

/** Tugagan ustun uchun: oxirgi yangilangani tepada; sanasizlar pastda, ular orasida ordinal/ID teskari. */
function byRecencyDesc(a: TaskItem, b: TaskItem): number {
  const at = a.updated_at ?? a.created_at ?? "";
  const bt = b.updated_at ?? b.created_at ?? "";
  if (at !== bt) return at < bt ? 1 : -1;
  return -byOrdinalThenId(a, b);
}

/**
 * Config tartibidagi status ustunlari; config'da yo'q statuslar oxirida (bo'sh bo'lsa ham config ustunlari qoladi).
 * Ustun ichida navbat tartibi (ordinal, keyin ID), tugagan ustunda esa teskari — yangi bajarilgani tepada.
 */
export function groupByStatus(tasks: readonly TaskItem[], statuses: readonly string[]): Column[] {
  const columns = new Map<string, TaskItem[]>(statuses.map((status) => [status, []]));
  for (const task of tasks) {
    const column = columns.get(task.status);
    if (column) column.push(task);
    else columns.set(task.status, [task]);
  }
  return [...columns].map(([status, items]) => ({
    status,
    tasks: items.sort(isDoneStatus(status, statuses) ? byRecencyDesc : byOrdinalThenId),
  }));
}

/** Vazifadagi milestone qiymati ID ham, sarlavha ham bo'lishi mumkin — ID'ga keltiriladi. */
export function milestoneId(value: string | null, milestones: readonly Milestone[]): string | null {
  if (!value?.trim()) return null;
  const key = norm(value);
  const found = milestones.find((m) => norm(m.id) === key || norm(m.title) === key);
  return found ? found.id : value;
}

export function milestoneTitle(value: string | null, milestones: readonly Milestone[]): string | null {
  const id = milestoneId(value, milestones);
  return milestones.find((m) => m.id === id)?.title ?? id;
}

export function matchesFilter(
  task: TaskItem,
  filter: BoardFilter,
  milestones: readonly Milestone[],
): boolean {
  if (filter.labels.length > 0) {
    // `backlog task list --labels` kabi: tanlangan har bir label bo'lishi kerak.
    const own = new Set(task.labels.map(norm));
    if (!filter.labels.every((label) => own.has(norm(label)))) return false;
  }
  if (filter.milestone === ALL) return true;
  const id = milestoneId(task.milestone, milestones);
  return filter.milestone === NO_MILESTONE ? id === null : id === filter.milestone;
}

export function filterTasks(
  tasks: readonly TaskItem[],
  filter: BoardFilter,
  milestones: readonly Milestone[],
): TaskItem[] {
  return tasks.filter((task) => matchesFilter(task, filter, milestones));
}

/** Filtr uchun labellar: config'dagilar (tartibida), keyin vazifalardagilar (alifbo bo'yicha); registrsiz takrorsiz. */
export function collectLabels(configLabels: readonly string[], tasks: readonly TaskItem[]): string[] {
  const seen = new Map<string, string>();
  for (const label of configLabels) {
    if (label.trim() && !seen.has(norm(label))) seen.set(norm(label), label.trim());
  }
  const extra = new Map<string, string>();
  for (const task of tasks) {
    for (const label of task.labels) {
      const key = norm(label);
      if (label.trim() && !seen.has(key) && !extra.has(key)) extra.set(key, label.trim());
    }
  }
  return [...seen.values(), ...[...extra.values()].sort((a, b) => a.localeCompare(b))];
}

/** Loyiha nomidan registr ID'si: `^[a-z0-9][a-z0-9-]{0,39}$`. */
export function slugify(name: string): string {
  const ascii = name
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return ascii.slice(0, 40).replace(/-+$/, "");
}

/** Vergul yoki yangi qator bilan ajratilgan ro'yxat; bo'sh va takrorlar tashlanadi. */
export function splitList(text: string, separator: RegExp = /[,\n]/): string[] {
  return [...new Set(text.split(separator).map((item) => item.trim()).filter(Boolean))];
}

export const splitLines = (text: string) => splitList(text, /\n/);
