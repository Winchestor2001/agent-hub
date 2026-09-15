import { useEffect } from "react";

import type { LivePane } from "../api/types";
import { BLOCKED } from "./model";

/**
 * Shortcut tartibi: avval javob kutayotganlar, keyin boshlanish vaqti bo'yicha.
 * Ro'yxat oxirgi chiqish bo'yicha saralanadi va terminal ulanishi o'zi chiqish beradi —
 * o'sha tartib bilan o'tilsa, pane'lar har bosishda joy almashib, "keyingisi" sakraydi.
 */
export function navigationOrder(panes: readonly LivePane[]): string[] {
  const rank = (pane: LivePane) => (pane.state === BLOCKED ? 0 : 1);
  return panes
    .toSorted((a, b) => rank(a) - rank(b) || (a.started_at ?? 0) - (b.started_at ?? 0) || a.id.localeCompare(b.id))
    .map((pane) => pane.id);
}

/** Keyingi/oldingi sessiya (aylanma). Joriy ro'yxatda bo'lmasa — oldinga birinchisi, orqaga oxirgisi. */
export function nextPaneId(order: readonly string[], current: string | null, step: 1 | -1): string | null {
  if (order.length === 0) return null;
  const index = current === null ? -1 : order.indexOf(current);
  if (index < 0) return step > 0 ? (order[0] ?? null) : (order[order.length - 1] ?? null);
  return order[(index + step + order.length) % order.length] ?? null;
}

type ShortcutEvent = Pick<KeyboardEvent, "key" | "altKey" | "shiftKey" | "ctrlKey" | "metaKey">;

/** Alt+Shift+↓/↑ (macOS: ⌥⇧↓/↑) — terminal fokusda bo'lsa ham ishlaydi. */
export function shortcutStep(event: ShortcutEvent): 1 | -1 | null {
  if (!event.altKey || !event.shiftKey || event.ctrlKey || event.metaKey) return null;
  if (event.key === "ArrowDown") return 1;
  if (event.key === "ArrowUp") return -1;
  return null;
}

interface TargetLike {
  tagName: string;
  isContentEditable: boolean;
  classList: { contains: (name: string) => boolean };
}

/** Oddiy matn maydonlarida Alt+Shift+strelka — matn tanlash, uni tortib olmaymiz. xterm maydoni bundan mustasno. */
export function isTextInput(target: TargetLike | null): boolean {
  if (!target) return false;
  if (target.classList.contains("xterm-helper-textarea")) return false;
  return target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName);
}

/** Ro'yxat ichida ↑/↓/Home/End — fokus ko'chadigan indeks (chegarada to'xtaydi). */
export function focusIndex(length: number, current: number, key: string): number | null {
  if (length === 0) return null;
  switch (key) {
    case "ArrowDown":
      return Math.min(current + 1, length - 1);
    case "ArrowUp":
      return Math.max(current - 1, 0);
    case "Home":
      return 0;
    case "End":
      return length - 1;
    default:
      return null;
  }
}

/** Oyna darajasida (capture) — xterm tugmani pane'ga yuborishidan oldin ushlanadi. */
export function useSessionShortcuts(order: readonly string[], current: string | null, onOpen: (paneId: string) => void) {
  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      const step = shortcutStep(event);
      if (step === null || document.querySelector("dialog[open]")) return;
      if (isTextInput(event.target instanceof HTMLElement ? event.target : null)) return;
      const next = nextPaneId(order, current, step);
      if (next === null) return;
      event.preventDefault();
      event.stopPropagation();
      onOpen(next);
    }
    window.addEventListener("keydown", onKey, { capture: true });
    return () => {
      window.removeEventListener("keydown", onKey, { capture: true });
    };
  }, [order, current, onOpen]);
}
