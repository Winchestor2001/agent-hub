import { FitAddon } from "@xterm/addon-fit";
import { Terminal } from "@xterm/xterm";
import { useCallback, useEffect, useRef, useState, type RefObject } from "react";

import {
  decodeBase64,
  parseServerMessage,
  terminalUrl,
  type ClientMessage,
  type ConnectionStatus,
} from "./protocol";

const RESIZE_DEBOUNCE_MS = 150;

export interface PaneTerminal {
  status: ConnectionStatus;
  /** Backend rad etgan oxirgi xabar kodi (invalid_keys, bad_message). */
  error: string | null;
  sendKeys: (keys: string[]) => void;
  reconnect: () => void;
}

/**
 * xterm + `/ws/panes/{id}` ulanishi. Terminal pane uchun bitta; ulanish qayta ochilsa KanBot
 * scrollback'ni `replay` bilan qayta yuboradi — terminal tozalanib qaytadan yoziladi.
 * Komponent `key={paneId}` bilan ishlatiladi: boshqa pane — yangi holat.
 */
export function usePaneTerminal(containerRef: RefObject<HTMLDivElement | null>, paneId: string): PaneTerminal {
  const [status, setStatus] = useState<ConnectionStatus>({ kind: "connecting" });
  const [error, setError] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);
  const termRef = useRef<Terminal | null>(null);
  const socketRef = useRef<WebSocket | null>(null);

  const send = useCallback((message: ClientMessage) => {
    const socket = socketRef.current;
    if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
  }, []);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    const term = new Terminal({
      fontFamily: '"SF Mono", Menlo, ui-monospace, monospace',
      fontSize: 12,
      cursorBlink: true,
      scrollback: 5000,
      theme: { background: "#0d1016", foreground: "#d7dae0", cursor: "#d7dae0", selectionBackground: "#2f5fb366" },
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(container);
    fit.fit();
    termRef.current = term;

    const input = term.onData((data) => {
      send({ type: "input", data });
    });
    let resizeTimer: number | undefined;
    const resize = term.onResize(({ rows, cols }) => {
      window.clearTimeout(resizeTimer);
      resizeTimer = window.setTimeout(() => {
        send({ type: "resize", rows, cols });
      }, RESIZE_DEBOUNCE_MS);
    });
    const observer = new ResizeObserver(() => {
      fit.fit();
    });
    observer.observe(container);
    term.focus();

    return () => {
      observer.disconnect();
      window.clearTimeout(resizeTimer);
      input.dispose();
      resize.dispose();
      term.dispose();
      termRef.current = null;
    };
  }, [containerRef, send]);

  useEffect(() => {
    const term = termRef.current;
    if (!term) return;
    const socket = new WebSocket(terminalUrl(window.location, paneId, { rows: term.rows, cols: term.cols }));
    socketRef.current = socket;
    socket.onopen = () => {
      setStatus({ kind: "open" });
    };
    socket.onmessage = (event: MessageEvent) => {
      const message = parseServerMessage(event.data);
      if (!message) return;
      if (message.type === "error") {
        setError(message.code);
        return;
      }
      if (message.replay) term.reset();
      term.write(decodeBase64(message.data));
    };
    socket.onclose = (event) => {
      if (socketRef.current === socket) socketRef.current = null;
      setStatus({ kind: "closed", code: event.code, reason: event.reason });
    };
    return () => {
      socket.onopen = socket.onmessage = socket.onclose = null;
      if (socketRef.current === socket) socketRef.current = null;
      socket.close();
    };
  }, [paneId, attempt]);

  const sendKeys = useCallback(
    (keys: string[]) => {
      setError(null);
      send({ type: "keys", keys });
      termRef.current?.focus();
    },
    [send],
  );

  const reconnect = useCallback(() => {
    setStatus({ kind: "connecting" });
    setError(null);
    setAttempt((n) => n + 1);
  }, []);

  return { status, error, sendKeys, reconnect };
}
