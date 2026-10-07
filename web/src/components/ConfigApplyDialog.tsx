import { useState } from "react";

import { useApplyConfig } from "../api/queries";
import type { ConfigApplyResult, ConfigKind, ConfigScope } from "../api/types";
import { kindFits, scopeLabel } from "../config/model";
import { useI18n } from "../i18n/context";
import { ErrorText } from "./ErrorText";
import { Modal } from "./Modal";

interface ConfigApplyDialogProps {
  kind: ConfigKind;
  name: string;
  content: string;
  scopes: ConfigScope[];
  /** Boshlang'ich belgilangan qamrov (joriy). */
  initialScope: string;
  onClose: () => void;
}

/** Bitta matnni global va/yoki tanlangan loyihalarga yozish; natija har qamrov uchun alohida. */
export function ConfigApplyDialog({ kind, name, content, scopes, initialScope, onClose }: ConfigApplyDialogProps) {
  const { t } = useI18n();
  const apply = useApplyConfig();
  const available = scopes.filter((scope) => kindFits(kind, scope));
  const [selected, setSelected] = useState<ReadonlySet<string>>(
    () => new Set(available.some((scope) => scope.id === initialScope) ? [initialScope] : []),
  );
  const [overwrite, setOverwrite] = useState(false);
  const results: ConfigApplyResult[] | undefined = apply.data?.results;

  function toggle(id: string) {
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  return (
    <Modal title={t("config.apply_title", { name })} onClose={onClose}>
      <form
        className="form"
        onSubmit={(event) => {
          event.preventDefault();
          apply.mutate({
            kind: kind.id,
            name,
            content,
            // Ekrandagi tartibda.
            scopes: available.filter((scope) => selected.has(scope.id)).map((scope) => scope.id),
            overwrite,
          });
        }}
      >
        <p className="muted">{t("config.apply_hint")}</p>
        <div className="config-apply-actions">
          <button
            type="button"
            className="button button-small"
            onClick={() => {
              setSelected(new Set(available.map((scope) => scope.id)));
            }}
          >
            {t("config.apply_all")}
          </button>
          <button
            type="button"
            className="button button-small"
            onClick={() => {
              setSelected(new Set());
            }}
          >
            {t("config.apply_none")}
          </button>
        </div>
        <ul className="config-apply-list">
          {available.map((scope) => (
            <li key={scope.id}>
              <label className="checkbox-row" title={scope.root}>
                <input
                  type="checkbox"
                  checked={selected.has(scope.id)}
                  onChange={() => {
                    toggle(scope.id);
                  }}
                />
                <span>{scope.label}</span>
                {!scope.exists && <span className="warning-text">{t("config.scope_missing_short")}</span>}
              </label>
            </li>
          ))}
        </ul>
        <label className="checkbox-row">
          <input
            type="checkbox"
            checked={overwrite}
            onChange={(event) => {
              setOverwrite(event.target.checked);
            }}
          />
          <span>{t("config.apply_overwrite")}</span>
        </label>
        {apply.error && <ErrorText error={apply.error} />}
        {results && (
          <ul className="config-apply-results" aria-label={t("config.apply_results")}>
            {results.map((result) => (
              <li key={result.scope} className={result.ok ? "config-result-ok" : "config-result-error"}>
                <span className="config-result-scope">{scopeLabel(scopes, result.scope)}</span>
                {result.error ? <ErrorText error={result.error} /> : <span>{t(`config.status_${result.status}`)}</span>}
              </li>
            ))}
          </ul>
        )}
        <div className="form-actions">
          <button type="button" className="button" onClick={onClose}>
            {t("common.close")}
          </button>
          <button type="submit" className="button button-primary" disabled={apply.isPending || selected.size === 0}>
            {apply.isPending ? t("config.applying") : t("config.apply_submit", { count: selected.size })}
          </button>
        </div>
      </form>
    </Modal>
  );
}
