import type { LivePane, PastSession, TaskItem } from "../api/types";

/** `blocked` — agent foydalanuvchidan javob kutmoqda; ro'yxatda alohida va tepada. */
export const BLOCKED = "blocked";

export interface LiveGroups {
  blocked: LivePane[];
  others: LivePane[];
}

/** Backend tartibi (holat, keyin oxirgi chiqish) saqlanadi. */
export function groupLive(panes: readonly LivePane[]): LiveGroups {
  const groups: LiveGroups = { blocked: [], others: [] };
  for (const pane of panes) (pane.state === BLOCKED ? groups.blocked : groups.others).push(pane);
  return groups;
}

export interface ProjectPanes {
  mine: LivePane[];
  others: LivePane[];
}

/** Tanlangan loyiha pane'lari va qolganlari (boshqa loyiha yoki loyihasiz); loyiha yo'q bo'lsa hammasi `mine`. */
export function splitByProject(panes: readonly LivePane[], projectId: string | null): ProjectPanes {
  const split: ProjectPanes = { mine: [], others: [] };
  for (const pane of panes) {
    (projectId === null || pane.project_id === projectId ? split.mine : split.others).push(pane);
  }
  return split;
}

export type TimeUnit = "seconds" | "minutes" | "hours" | "days";

export interface Elapsed {
  unit: TimeUnit;
  count: number;
}

/** KanBot vaqtlari — unix soniyalar. Kelajakdagi vaqt (soat farqi) 0 s deb olinadi. */
export function elapsed(timestamp: number, nowSeconds: number): Elapsed {
  const seconds = Math.max(0, Math.floor(nowSeconds - timestamp));
  if (seconds < 60) return { unit: "seconds", count: seconds };
  if (seconds < 3600) return { unit: "minutes", count: Math.floor(seconds / 60) };
  if (seconds < 86400) return { unit: "hours", count: Math.floor(seconds / 3600) };
  return { unit: "days", count: Math.floor(seconds / 86400) };
}

/** Pane uchun ko'rsatiladigan vaqt: oxirgi chiqish, bo'lmasa boshlanish. */
export function paneActivity(pane: LivePane): number | null {
  return pane.last_output_at ?? pane.started_at;
}

/** Backend `build_prompt` bilan bir xil: vazifa tanlansa prompt shu matndan boshlanadi. */
export function promptPrefix(template: string, taskId: string): string {
  return template.replaceAll("{task_id}", taskId);
}

export interface AgentChoice {
  agent: string;
  /** `null` — KanBot holati noma'lum (health kelmagan yoki KanBot o'chiq). */
  online: boolean | null;
}

export function agentChoices(allowed: readonly string[], onlineAgents: readonly string[] | undefined): AgentChoice[] {
  return allowed.map((agent) => ({
    agent,
    online: onlineAgents ? onlineAgents.includes(agent) : null,
  }));
}

/** Sessiya uchun vazifalar: yakuniy statusdagilar (oxirgi ustun) chiqmaydi, tanlangani doim qoladi. */
export function sessionTasks(
  tasks: readonly TaskItem[],
  statuses: readonly string[],
  keepId: string | null = null,
): TaskItem[] {
  const terminal = statuses.length > 1 ? statuses[statuses.length - 1] : undefined;
  return tasks
    .filter((task) => task.status !== terminal || task.id === keepId)
    .toSorted((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
}

/** Loyiha papkasi nomi (ko'rsatish uchun): `/a/b/web` → `web`. */
export function baseName(path: string): string {
  const trimmed = path.replace(/\/+$/, "");
  return trimmed.slice(trimmed.lastIndexOf("/") + 1) || path;
}

export function sessionKey(session: { agent: string; session_id: string }): string {
  return `${session.agent}:${session.session_id}`;
}

/** Tanlovdan ro'yxatda qolmagan va ochiq (o'chirib bo'lmaydigan) sessiyalar chiqariladi. */
export function pruneSelection(selected: ReadonlySet<string>, sessions: readonly PastSession[]): Set<string> {
  return new Set(sessions.filter((s) => !s.active && selected.has(sessionKey(s))).map(sessionKey));
}

export function toggleKey(selected: ReadonlySet<string>, key: string): Set<string> {
  const next = new Set(selected);
  if (!next.delete(key)) next.add(key);
  return next;
}
