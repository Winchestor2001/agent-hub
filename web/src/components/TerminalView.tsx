import "@xterm/xterm/css/xterm.css";

import { useRef } from "react";

import type { LivePane, Project } from "../api/types";
import { isMessageKey } from "../i18n/messages";
import { useI18n } from "../i18n/context";
import { baseName } from "../sessions/model";
import { closeMessage, QUICK_KEYS } from "../terminal/protocol";
import { usePaneTerminal } from "../terminal/usePaneTerminal";
import { usePasteUpload } from "../terminal/usePasteUpload";
import { ErrorText } from "./ErrorText";
import { StateBadge } from "./SessionBits";

interface TerminalViewProps {
  paneId: string;
  /** Jonli ro'yxatdagi ma'lumot; hali kelmagan yoki pane yo'qolgan bo'lsa undefined. */
  pane: LivePane | undefined;
  /** Pane tegishli loyiha: paste qilingan fayllar shu loyiha papkasiga yuklanadi. */
  project: Project | undefined;
  onBack: () => void;
}

/** Markaziy panel o'rnida pane terminali. `key={paneId}` bilan render qilinadi. */
export function TerminalView({ paneId, pane, project, onBack }: TerminalViewProps) {
  const { t, message } = useI18n();
  const containerRef = useRef<HTMLDivElement>(null);
  const { status, error, sendKeys, pasteText, reconnect } = usePaneTerminal(containerRef, paneId);
  const pasteUpload = usePasteUpload({
    pane,
    project,
    active: status.kind === "open" && pane?.alive !== false,
    paste: pasteText,
  });
  const closed = status.kind === "closed" ? closeMessage(status.reason) : null;
  const errorKey = error ? `terminal.error_${error}` : null;
  const title = pane ? pane.title || baseName(pane.cwd) : paneId;

  return (
    <section className="panel panel-terminal" aria-label={title}>
      <header className="panel-header terminal-header">
        <button type="button" className="button button-small" title={t("terminal.back_title")} onClick={onBack}>
          {t("terminal.back")}
        </button>
        {pane && <StateBadge state={pane.state} approximate={pane.approximate} />}
        {pane && <span className="mono">{pane.agent}</span>}
        <span className="terminal-title" title={pane?.cwd}>
          {title}
        </span>
        <span className={`terminal-status terminal-status-${status.kind}`}>
          {status.kind === "closed" ? "●" : t(`terminal.${status.kind}`)}
        </span>
      </header>
      <div className="terminal-toolbar" role="toolbar" aria-label={t("terminal.quick_keys")}>
        {QUICK_KEYS.map((key) => (
          <button
            key={key.label}
            type="button"
            className="button button-small mono"
            title={t("terminal.key_title", { key: key.label })}
            disabled={status.kind !== "open"}
            onClick={() => {
              sendKeys(key.keys);
            }}
          >
            {key.label}
          </button>
        ))}
        {pane && !pane.alive && <span className="muted">{t("terminal.ended")}</span>}
        {errorKey && (
          <span className="error-text">{isMessageKey(errorKey) ? message({ key: errorKey }) : error}</span>
        )}
        {pasteUpload.uploading && <span className="muted">{t("files.uploading")}</span>}
        {pasteUpload.noProject && <span className="error-text">{t("terminal.upload_no_project")}</span>}
        {pasteUpload.error && <ErrorText error={pasteUpload.error} />}
      </div>
      {closed && (
        <div className="terminal-closed" role="status">
          <span>{message({ key: closed.key })}</span>
          {closed.retry && (
            <button type="button" className="button button-small" onClick={reconnect}>
              {t("terminal.reconnect")}
            </button>
          )}
        </div>
      )}
      <div className="terminal-screen" ref={containerRef} onPasteCapture={pasteUpload.onPasteCapture} />
    </section>
  );
}
