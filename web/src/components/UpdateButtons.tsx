import { useState } from "react";

import { useLiveSessions, useStartUpdate, useUpdates } from "../api/queries";
import type { AgentUpdate } from "../api/types";
import { useI18n } from "../i18n/context";
import type { UpdateTone } from "../updates/model";
import { canUpdate, livePaneCount, updateTone } from "../updates/model";
import { ErrorText } from "./ErrorText";

/** Tugma yonidagi belgi: holat bir qarashda ko'rinsin. */
const MARKS: Partial<Record<UpdateTone, string>> = {
  running: "…",
  done: "✓",
  failed: "✗",
};

/** TopBar'dagi «claude 2.1.272» / «codex 0.154.0» tugmalari — brew orqali yangilash. */
export function UpdateButtons() {
  const updates = useUpdates();
  if (!updates.data) return null;
  const { brew, agents } = updates.data;
  return (
    <div className="topbar-updates">
      {agents.map((item) => (
        <UpdateButton key={item.agent} item={item} brew={brew} />
      ))}
    </div>
  );
}

function UpdateButton({ item, brew }: { item: AgentUpdate; brew: boolean }) {
  const { t } = useI18n();
  const live = useLiveSessions();
  const start = useStartUpdate();
  const [confirming, setConfirming] = useState(false);

  const tone = updateTone(item, brew);
  const version = item.installed_version ?? t("updates.version_unknown");
  const title = buttonTitle(t, item, tone, version);
  const panes = livePaneCount(live.data?.live, item.agent);
  const failed = item.last && !item.last.ok ? item.last.output : null;

  return (
    <div className="update-button">
      <button
        type="button"
        className="button button-small"
        disabled={!canUpdate(tone)}
        title={title}
        aria-label={title}
        onClick={() => {
          start.reset();
          setConfirming((open) => !open);
        }}
      >
        {t("updates.label", { agent: item.agent, version })}
        {tone === "outdated" && <span className="dot dot-warn" aria-hidden="true" />}
        {MARKS[tone] && (
          <span className={`update-mark update-mark-${tone}`} aria-hidden="true">
            {MARKS[tone]}
          </span>
        )}
      </button>
      {confirming && (
        <div className="confirm confirm-neutral update-confirm" role="alertdialog" aria-label={title}>
          <p>{t("updates.confirm", { agent: item.agent })}</p>
          <code className="mono">brew upgrade --cask {item.cask ?? item.agent}</code>
          {panes > 0 && <p className="update-warn">{t("updates.confirm_live", { count: panes })}</p>}
          {failed !== null && (
            <pre className="update-output" aria-label={t("updates.output")}>
              {failed}
            </pre>
          )}
          {start.error && <ErrorText error={start.error} />}
          <div className="form-actions">
            <button
              type="button"
              className="button button-small"
              onClick={() => {
                setConfirming(false);
                start.reset();
              }}
            >
              {t("common.cancel")}
            </button>
            <button
              type="button"
              className="button button-small button-primary"
              disabled={start.isPending}
              onClick={() => {
                start.mutate(item.agent, {
                  onSuccess: () => {
                    setConfirming(false);
                  },
                });
              }}
            >
              {t("updates.confirm_yes")}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function buttonTitle(
  t: ReturnType<typeof useI18n>["t"],
  item: AgentUpdate,
  tone: UpdateTone,
  version: string,
): string {
  const agent = item.agent;
  switch (tone) {
    case "no_brew":
      return t("updates.title_no_brew");
    case "missing":
      return t("updates.title_missing", { agent });
    case "running":
      return t("updates.title_running", { agent });
    case "failed":
      return t("updates.title_failed");
    case "outdated":
      return t("updates.title_outdated", {
        agent,
        installed: version,
        latest: item.latest_version ?? t("updates.version_unknown"),
      });
    case "done":
      return t("updates.title_done", { agent, version });
    case "unknown":
      return t("updates.title_unknown", { agent, version });
    case "current":
      return t("updates.title_current", { agent, version });
  }
}
