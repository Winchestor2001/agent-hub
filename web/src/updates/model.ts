import type { AgentUpdate, LivePane } from "../api/types";

/**
 * Tugma ko'rinishi: `no_brew`/`missing` — bosib bo'lmaydi, `running` — ketmoqda,
 * `failed` — oxirgi urinish xato (qayta bosish mumkin), `outdated` — yangi versiya bor,
 * `done` — shu yerda yangilandi, `unknown` — so'nggi versiya noma'lum (tarmoq yo'q).
 */
export type UpdateTone =
  | "no_brew"
  | "missing"
  | "running"
  | "failed"
  | "outdated"
  | "done"
  | "unknown"
  | "current";

export function updateTone(item: AgentUpdate, brewAvailable: boolean): UpdateTone {
  if (!brewAvailable) return "no_brew";
  if (item.running) return "running";
  if (item.installed_version === null) return "missing";
  if (item.last && !item.last.ok) return "failed";
  if (item.outdated) return "outdated";
  if (item.last?.ok) return "done";
  if (item.latest_version === null) return "unknown";
  return "current";
}

/** `no_brew` va `missing` da yangilashni boshlab bo'lmaydi, `running` da esa navbat yo'q. */
export function canUpdate(tone: UpdateTone): boolean {
  return tone !== "no_brew" && tone !== "missing" && tone !== "running";
}

export function anyRunning(agents: readonly AgentUpdate[]): boolean {
  return agents.some((item) => item.running);
}

/** Ogohlantirish uchun: shu agentning tirik pane'lari soni. */
export function livePaneCount(panes: readonly LivePane[] | undefined, agent: string): number {
  return (panes ?? []).filter((pane) => pane.agent === agent && pane.alive).length;
}
