import type { MessageKey } from "../i18n/messages";

/** Backend `/ws/panes/{id}` protokoli (src/agent_hub/api/terminal.py bilan mos). */
export type ServerMessage =
  | { type: "data"; data: string; replay: boolean }
  | { type: "error"; code: string };

export type ClientMessage =
  | { type: "input"; data: string }
  | { type: "keys"; keys: string[] }
  | { type: "resize"; rows: number; cols: number };

export interface QuickKey {
  label: string;
  keys: string[];
}

export const QUICK_KEYS: readonly QuickKey[] = [
  { label: "Enter", keys: ["Enter"] },
  { label: "y", keys: ["y"] },
  { label: "n", keys: ["n"] },
  { label: "Esc", keys: ["Escape"] },
  { label: "Ctrl-C", keys: ["C-c"] },
];

export function terminalUrl(
  location: Pick<Location, "protocol" | "host">,
  paneId: string,
  size: { rows: number; cols: number } | null,
): string {
  const proto = location.protocol === "https:" ? "wss" : "ws";
  const query = size ? `?rows=${String(size.rows)}&cols=${String(size.cols)}` : "";
  return `${proto}://${location.host}/ws/panes/${encodeURIComponent(paneId)}${query}`;
}

export function parseServerMessage(raw: unknown): ServerMessage | null {
  if (typeof raw !== "string") return null;
  let msg: unknown;
  try {
    msg = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof msg !== "object" || msg === null) return null;
  const record = msg as Record<string, unknown>;
  if (record.type === "data" && typeof record.data === "string") {
    return { type: "data", data: record.data, replay: record.replay === true };
  }
  if (record.type === "error" && typeof record.code === "string") {
    return { type: "error", code: record.code };
  }
  return null;
}

export function decodeBase64(data: string): Uint8Array {
  const binary = atob(data);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export type ConnectionStatus =
  | { kind: "connecting" }
  | { kind: "open" }
  | { kind: "closed"; code: number; reason: string };

/** Yopilish sababi → foydalanuvchiga xabar; qayta ulanish ma'nosi bormi. */
export function closeMessage(reason: string): { key: MessageKey; retry: boolean } {
  switch (reason) {
    case "pane_gone":
      return { key: "terminal.closed_gone", retry: false };
    case "kanbot_unavailable":
      return { key: "terminal.closed_kanbot", retry: true };
    case "slow_client":
      return { key: "terminal.closed_slow", retry: true };
    case "bad_request":
      return { key: "terminal.closed_bad_request", retry: false };
    default:
      return { key: "terminal.closed", retry: true };
  }
}
