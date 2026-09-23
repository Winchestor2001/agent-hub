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

/** Mavjud oynalar (5 soatlik va/yoki haftalik) — yo'qlari ro'yxatga kirmaydi. */
export function limitBadges(item: AgentLimits): LimitBadge[] {
  const badges: LimitBadge[] = [];
  if (item.five_hour) badges.push({ kind: "five_hour", window: item.five_hour });
  if (item.weekly) badges.push({ kind: "weekly", window: item.weekly });
  return badges;
}

/** Brauzer vaqt zonasida soat:daqiqa; `resets_at` yo'q bo'lsa `null`. */
export function formatResetTime(resetsAt: number | null): string | null {
  if (resetsAt === null) return null;
  return new Date(resetsAt * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}
