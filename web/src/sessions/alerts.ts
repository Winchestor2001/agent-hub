import { useEffect, useRef, useState } from "react";

import type { LivePane } from "../api/types";
import { useI18n } from "../i18n/context";
import { BLOCKED, baseName } from "./model";

/** Tab sarlavhasi: javob kutayotgan sessiyalar soni oldinda — boshqa tabdan ham ko'rinadi. */
export function blockedTitle(base: string, count: number): string {
  return count > 0 ? `(${String(count)}) ${base}` : base;
}

export function blockedIds(panes: readonly LivePane[]): Set<string> {
  return new Set(panes.filter((pane) => pane.state === BLOCKED).map((pane) => pane.id));
}

/** Oldingi ko'rinishda blocked bo'lmagan pane'lar. `previous = null` — birinchi yuklanish, xabar yo'q. */
export function newlyBlocked(previous: ReadonlySet<string> | null, panes: readonly LivePane[]): LivePane[] {
  if (previous === null) return [];
  return panes.filter((pane) => pane.state === BLOCKED && !previous.has(pane.id));
}

export type NotifyPermission = NotificationPermission | "unsupported";

function currentPermission(): NotifyPermission {
  return typeof Notification === "undefined" ? "unsupported" : Notification.permission;
}

/** Brauzer ruxsati; so'rov faqat foydalanuvchi bosganda yuboriladi (brauzerlar shuni talab qiladi). */
export function useNotificationPermission(): { permission: NotifyPermission; request: () => void } {
  const [permission, setPermission] = useState(currentPermission);
  return {
    permission,
    request: () => {
      if (typeof Notification === "undefined") return;
      void Notification.requestPermission().then(setPermission);
    },
  };
}

/**
 * Sarlavha hisoblagichi va yangi blocked uchun bildirishnoma (tab fokusda bo'lmasa).
 * `panes = undefined` — ma'lumot yo'q yoki xato: hisoblagich yashiriladi, oldingi holat saqlanadi.
 */
export function useBlockedAlerts(panes: readonly LivePane[] | undefined, onOpen: (paneId: string) => void) {
  const { t } = useI18n();
  const previous = useRef<Set<string> | null>(null);
  const base = t("app.title");
  const count = panes ? blockedIds(panes).size : 0;

  useEffect(() => {
    document.title = blockedTitle(base, count);
  }, [base, count]);

  useEffect(
    () => () => {
      document.title = base;
    },
    [base],
  );

  useEffect(() => {
    if (!panes) return;
    const fresh = newlyBlocked(previous.current, panes);
    previous.current = blockedIds(panes);
    if (fresh.length === 0 || currentPermission() !== "granted" || document.hasFocus()) return;
    for (const pane of fresh) {
      const notification = new Notification(t("notify.blocked_title", { agent: pane.agent }), {
        body: pane.title || baseName(pane.cwd),
        // Bir pane uchun bitta bildirishnoma: qayta blocked bo'lsa eskisi almashtiriladi.
        tag: `agent-hub-blocked-${pane.id}`,
      });
      notification.onclick = () => {
        window.focus();
        onOpen(pane.id);
        notification.close();
      };
    }
  }, [panes, onOpen, t]);
}
