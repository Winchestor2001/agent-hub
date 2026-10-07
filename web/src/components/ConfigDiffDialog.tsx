import { useMemo } from "react";

import type { ApiError } from "../api/client";
import { diffLines, diffStats, withContext } from "../config/diff";
import { useI18n } from "../i18n/context";
import { ErrorText } from "./ErrorText";
import { Modal } from "./Modal";

interface ConfigDiffDialogProps {
  path: string;
  before: string;
  after: string;
  pending: boolean;
  error: ApiError | null;
  onConfirm: () => void;
  onClose: () => void;
}

/** Saqlashdan oldingi oxirgi qadam: diskdagi matn va yangi matn farqi. */
export function ConfigDiffDialog({ path, before, after, pending, error, onConfirm, onClose }: ConfigDiffDialogProps) {
  const { t } = useI18n();
  const lines = useMemo(() => diffLines(before, after), [before, after]);
  const rows = useMemo(() => withContext(lines), [lines]);
  const stats = diffStats(lines);
  const unchanged = stats.added === 0 && stats.removed === 0;

  return (
    <Modal title={t("config.diff_title", { path })} onClose={onClose} className="modal-wide">
      <div className="form">
        <p className="muted">
          {unchanged ? t("config.diff_none") : t("config.diff_stats", { added: stats.added, removed: stats.removed })}
        </p>
        {!unchanged && (
          <div className="config-diff" role="table" aria-label={t("config.diff_label")}>
            {rows.map((row, index) =>
              row.op === "skip" ? (
                <div key={String(index)} className="config-diff-skip" role="row">
                  {t("config.diff_skipped", { count: row.count })}
                </div>
              ) : (
                <div key={String(index)} className={`config-diff-line config-diff-${row.op}`} role="row">
                  <span className="config-diff-no">{row.oldNo ?? ""}</span>
                  <span className="config-diff-no">{row.newNo ?? ""}</span>
                  <span className="config-diff-sign">{row.op === "add" ? "+" : row.op === "del" ? "−" : " "}</span>
                  <span className="config-diff-text">{row.text}</span>
                </div>
              ),
            )}
          </div>
        )}
        {error && <ErrorText error={error} />}
        <div className="form-actions">
          <button type="button" className="button" onClick={onClose}>
            {t("common.cancel")}
          </button>
          <button
            type="button"
            className="button button-primary"
            disabled={pending || unchanged}
            onClick={onConfirm}
          >
            {pending ? t("config.saving") : t("config.save_confirm")}
          </button>
        </div>
      </div>
    </Modal>
  );
}
