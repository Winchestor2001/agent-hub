import type { AgentLimits, LimitWindow } from "../api/types";

export type LimitTone = "ok" | "warn" | "bad";

const WARN_AT = 50;
const BAD_AT = 75;

/** `statusline.sh` dagi rang chegaralari bilan bir xil: <50 yashil, <75 sariq, aks holda qizil. */
export function limitTone(usedPercent: number): LimitTone {
  if (usedPercent >= BAD_AT) return "bad";
  if (usedPercent >= WARN_AT) return "warn";
  return "ok";
}

export interface LimitBadge {
  kind: "five_hour" | "weekly";
  window: LimitWindow;
}

/**
 * TopBar uchun ixcham primary badge.
 * To'liq 5h/7d tafsilotlar hover/focus card ichida qoladi.
 */
export function limitBadges(item: AgentLimits): LimitBadge[] {
  if (item.agent === "codex") {
    if (item.five_hour) return [{ kind: "five_hour", window: item.five_hour }];
    if (item.weekly) return [{ kind: "weekly", window: item.weekly }];
    return [];
  }
  if (item.weekly) return [{ kind: "weekly", window: item.weekly }];
  if (item.five_hour) return [{ kind: "five_hour", window: item.five_hour }];
  return [];
}

/** Brauzer vaqt zonasida soat:daqiqa; `resets_at` yo'q bo'lsa `null`. */
export function formatResetTime(resetsAt: number | null): string | null {
  if (resetsAt === null) return null;
  return new Date(resetsAt * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

/** Foiz UI'da butun son sifatida ko'rsatiladi. */
export function formatLimitPercent(usedPercent: number): string {
  return `${String(Math.floor(usedPercent))}%`;
}

/** Tooltip/card uchun sana + vaqt; `null` bo'lsa `null`. */
export function formatResetDateTime(resetsAt: number | null): string | null {
  if (resetsAt === null) return null;
  return new Date(resetsAt * 1000).toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/** Ma'lumot nechchi daqiqa oldin yangilanganini ixcham ko'rsatadi. */
export function formatAge(updatedAt: number | null, nowMs = Date.now()): string | null {
  if (updatedAt === null) return null;
  const seconds = Math.max(0, Math.floor(nowMs / 1000 - updatedAt));
  if (seconds < 60) return "<1m";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${String(minutes)}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${String(hours)}h`;
  return `${String(Math.floor(hours / 24))}d`;
}
