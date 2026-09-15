import { useQueryClient, type QueryKey } from "@tanstack/react-query";
import { useEffect } from "react";

import { queryKeys } from "./queries";

/**
 * Push yangilanishlar (`/api/events`, SSE): backend faqat "qaysi ma'lumot eskirdi" mavzusini yuboradi,
 * UI tegishli so'rovlarni qayta bajaradi. Polling o'zgarishsiz qoladi — oqim uzilsa zaxira.
 */
export const EVENTS_PATH = "/api/events";
/** Backend rad etsa (EventSource butunlay yopilsa) qayta urinish. */
export const EVENTS_REOPEN_MS = 5000;

export type Topic = "sessions" | "health";
export const ALL_TOPICS: readonly Topic[] = ["sessions", "health"];

const TOPIC_KEYS: Record<Topic, readonly QueryKey[]> = {
  // Pane holati: jonli va o'tgan sessiyalar, loyiha hisoblagichlari, doska kartochkalari, vazifa detali.
  sessions: [["sessions"], queryKeys.projects, ["board"], ["task"]],
  health: [queryKeys.health],
};

function isTopic(value: unknown): value is Topic {
  return typeof value === "string" && (ALL_TOPICS as readonly string[]).includes(value);
}

/** `invalidate` hodisasining `data` qismi; noma'lum mavzular tashlanadi. */
export function parseTopics(data: string): Topic[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(data);
  } catch {
    return [];
  }
  if (typeof parsed !== "object" || parsed === null) return [];
  const topics = (parsed as Record<string, unknown>).topics;
  return Array.isArray(topics) ? topics.filter(isTopic) : [];
}

export function keysForTopics(topics: readonly Topic[]): QueryKey[] {
  return [...new Set(topics)].flatMap((topic) => TOPIC_KEYS[topic]);
}

/** Ilova bo'yicha bitta oqim. Qayta ulanganda (birinchi ochilishda emas) hammasi yangilanadi. */
export function useLiveEvents(): void {
  const client = useQueryClient();

  useEffect(() => {
    if (typeof EventSource === "undefined") return;
    let source: EventSource | null = null;
    let reopenTimer: number | undefined;
    let opened = false;

    const invalidate = (topics: readonly Topic[]) => {
      for (const queryKey of keysForTopics(topics)) void client.invalidateQueries({ queryKey });
    };

    const open = () => {
      const current = new EventSource(EVENTS_PATH);
      source = current;
      current.addEventListener("ready", () => {
        if (opened) invalidate(ALL_TOPICS);
        opened = true;
      });
      current.addEventListener("invalidate", (event) => {
        invalidate(parseTopics(event.data as string));
      });
      current.addEventListener("error", () => {
        // CONNECTING — brauzer o'zi qayta ulanadi; CLOSED (masalan, 403/503) — o'zimiz.
        if (current.readyState !== EventSource.CLOSED) return;
        window.clearTimeout(reopenTimer);
        reopenTimer = window.setTimeout(open, EVENTS_REOPEN_MS);
      });
    };

    open();
    return () => {
      window.clearTimeout(reopenTimer);
      source?.close();
    };
  }, [client]);
}
