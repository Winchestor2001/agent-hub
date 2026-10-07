import { useEffect, useRef, useState } from "react";

import { ApiError } from "../api/client";
import { fetchConfigTemplate, useConfigFile, useConfigTemplates, useDeleteConfig, useWriteConfig } from "../api/queries";
import type { ConfigFile, ConfigItem, ConfigKind, ConfigScope } from "../api/types";
import { lookup, nameFromFile, nameProblem, scopeLabel } from "../config/model";
import { useI18n } from "../i18n/context";
import { ConfigApplyDialog } from "./ConfigApplyDialog";
import { ConfigDiffDialog } from "./ConfigDiffDialog";
import { ErrorText } from "./ErrorText";

/** Diskdagi fayl o'qilgandan keyin o'zgargan (yoki yaratilgan/o'chirilgan) — qayta yuklash kerak. */
const STALE_CODES = new Set(["config_conflict", "config_exists", "config_not_found"]);

interface ConfigEditorProps {
  scope: ConfigScope;
  kind: ConfigKind;
  scopes: ConfigScope[];
  /** `null` — to'plamga yangi element. */
  name: string | null;
  item: ConfigItem | undefined;
  onSaved: (name: string) => void;
  onDeleted: () => void;
  onDirtyChange: (dirty: boolean) => void;
}

export function ConfigEditor(props: ConfigEditorProps) {
  const { t } = useI18n();
  const file = useConfigFile(props.scope.id, props.kind.id, props.name);
  // Qo'llash natijalari forma qayta yuklanganda ham (joriy qamrov ham yozilgan bo'lsa) ko'rinib tursin.
  const [applying, setApplying] = useState<{ name: string; content: string } | null>(null);

  let form;
  if (props.name === null) {
    form = <EditorForm {...props} file={null} onReload={undefined} onApply={setApplying} />;
  } else if (file.error) {
    form = <ErrorText error={file.error} />;
  } else if (!file.data) {
    form = <p className="muted">{t("config.loading")}</p>;
  } else {
    form = (
      <EditorForm
        // Qayta yuklanganda (yangi etag) qoralama diskdagi matndan boshlanadi.
        key={file.data.etag ?? "missing"}
        {...props}
        file={file.data}
        onReload={() => void file.refetch()}
        onApply={setApplying}
      />
    );
  }
  return (
    <>
      {form}
      {applying && (
        <ConfigApplyDialog
          kind={props.kind}
          name={applying.name}
          content={applying.content}
          scopes={props.scopes}
          initialScope={props.scope.id}
          onClose={() => {
            setApplying(null);
          }}
        />
      )}
    </>
  );
}

interface EditorFormProps extends ConfigEditorProps {
  file: ConfigFile | null;
  onReload: (() => void) | undefined;
  onApply: (target: { name: string; content: string }) => void;
}

function EditorForm({
  scope,
  kind,
  scopes,
  name,
  item,
  file,
  onSaved,
  onDeleted,
  onDirtyChange,
  onReload,
  onApply,
}: EditorFormProps) {
  const { t, message } = useI18n();
  const write = useWriteConfig();
  const remove = useDeleteConfig();
  const templates = useConfigTemplates();
  const base = file?.content ?? "";
  const [draft, setDraft] = useState(base);
  const [newName, setNewName] = useState("");
  const [showDiff, setShowDiff] = useState(false);
  const [stale, setStale] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [localError, setLocalError] = useState<ApiError | null>(null);
  const uploadRef = useRef<HTMLInputElement>(null);

  const isNew = name === null;
  const effectiveName = name ?? newName.trim();
  const problem = isNew ? nameProblem(kind, effectiveName) : null;
  const dirty = draft !== base || (isNew && newName !== "");
  const exists = file?.exists ?? false;
  const kindTemplates = (templates.data?.templates ?? []).filter(
    (template) => template.kind === kind.id && (kind.collection || template.name === name),
  );

  useEffect(() => {
    onDirtyChange(dirty);
  }, [dirty, onDirtyChange]);
  useEffect(() => () => {
    onDirtyChange(false);
  }, [onDirtyChange]);

  function handleError(error: ApiError) {
    if (STALE_CODES.has(error.code)) {
      setShowDiff(false);
      setConfirmDelete(false);
      setStale(true);
    }
  }

  function save() {
    write.mutate(
      { scope: scope.id, kind: kind.id, name: effectiveName, content: draft, etag: file?.etag ?? null },
      {
        onSuccess: (result) => {
          setShowDiff(false);
          onDirtyChange(false);
          onSaved(result.name);
        },
        onError: handleError,
      },
    );
  }

  async function fillFromTemplate(templateId: string) {
    const template = kindTemplates.find((entry) => entry.id === templateId);
    if (!template) return;
    const target = kind.collection && effectiveName && !problem ? effectiveName : template.name;
    try {
      const rendered = await fetchConfigTemplate(template.id, target);
      setDraft(rendered.content);
      if (isNew && !newName) setNewName(rendered.name);
      setLocalError(null);
    } catch (error) {
      if (error instanceof ApiError) setLocalError(error);
    }
  }

  async function fillFromFile(selected: File | undefined) {
    if (!selected) return;
    setDraft(await selected.text());
    if (isNew && !newName) setNewName(nameFromFile(kind, selected.name));
  }

  const accept = kind.collection ? kind.extensions.join(",") : kind.format === "json" ? ".json" : ".md";
  const path = file?.abs_path ?? `${scope.root}/…`;

  return (
    <div className="config-editor">
      <header className="config-editor-header">
        {isNew ? (
          <label className="config-name-field">
            <span className="field-label">{t("config.name")}</span>
            <input
              value={newName}
              placeholder={kind.extensions.length > 1 ? "guard-bash.sh" : "my-name"}
              aria-invalid={problem !== null && newName !== ""}
              onChange={(event) => {
                setNewName(event.target.value);
              }}
            />
          </label>
        ) : (
          <div className="config-editor-title">
            <span className="list-item-title">{name}</span>
            <span className="muted mono" title={path}>
              {path}
            </span>
          </div>
        )}
        <span className="chips">
          {!exists && <span className="chip">{t("config.new_file")}</span>}
          {file?.mode && <span className="chip mono">{file.mode}</span>}
          {dirty && <span className="chip chip-dirty">{t("config.unsaved")}</span>}
        </span>
      </header>

      {isNew && newName !== "" && problem && (
        <p className="error-text">{t(`config.name_${problem}`, { extensions: kind.extensions.join(" ") })}</p>
      )}
      {file?.warnings.includes("local_not_ignored") && (
        <p className="config-warning" role="alert">
          {t("config.warn_local_not_ignored")}
        </p>
      )}
      {kind.id === "claude_local_md" && !exists && <p className="muted">{t("config.hint_local")}</p>}
      {kind.id === "hooks" && <p className="muted">{t("config.hint_hooks")}</p>}
      {item?.shadow.map((shadow) => (
        <p key={shadow.scope} className="config-warning" role="alert">
          {shadow.winner === "other"
            ? t("config.warn_shadowed", { scope: scopeLabel(scopes, shadow.scope) })
            : t("config.warn_shadows", { scope: scopeLabel(scopes, shadow.scope) })}
        </p>
      ))}
      {stale && (
        <div className="config-warning config-stale" role="alert">
          <p>{t("config.stale")}</p>
          <div className="form-actions">
            <button
              type="button"
              className="button button-small"
              onClick={() => void navigator.clipboard.writeText(draft)}
            >
              {t("config.copy_draft")}
            </button>
            {onReload && (
              <button type="button" className="button button-small button-primary" onClick={onReload}>
                {t("config.reload")}
              </button>
            )}
          </div>
        </div>
      )}

      <div className="config-toolbar">
        {kindTemplates.length > 0 && (
          <select
            aria-label={t("config.template")}
            value=""
            onChange={(event) => void fillFromTemplate(event.target.value)}
          >
            <option value="">{t("config.template_choose")}</option>
            {kindTemplates.map((template) => (
              <option key={template.id} value={template.id}>
                {lookup(message, `config.template.${template.id}`, template.id)}
              </option>
            ))}
          </select>
        )}
        <button
          type="button"
          className="button button-small"
          onClick={() => {
            uploadRef.current?.click();
          }}
        >
          {t("config.upload")}
        </button>
        <input
          ref={uploadRef}
          type="file"
          accept={accept}
          hidden
          aria-label={t("config.upload")}
          onChange={(event) => {
            void fillFromFile(event.target.files?.[0]);
            event.target.value = "";
          }}
        />
        <span className="muted config-toolbar-hint">{t("config.paste_hint")}</span>
      </div>
      {localError && <ErrorText error={localError} />}

      <textarea
        className="config-textarea mono"
        aria-label={t("config.content")}
        spellCheck={false}
        value={draft}
        onChange={(event) => {
          setDraft(event.target.value);
        }}
        onKeyDown={(event) => {
          if ((event.metaKey || event.ctrlKey) && event.key === "s") {
            event.preventDefault();
            if (!problem) setShowDiff(true);
          }
        }}
      />

      {write.error && !showDiff && !stale && <ErrorText error={write.error} />}
      {remove.error && !stale && <ErrorText error={remove.error} />}

      {confirmDelete && file?.etag && (
        <div className="confirm" role="alertdialog" aria-label={t("config.delete")}>
          <p>{t("config.delete_confirm", { path })}</p>
          <div className="form-actions">
            <button
              type="button"
              className="button button-small"
              onClick={() => {
                setConfirmDelete(false);
              }}
            >
              {t("common.cancel")}
            </button>
            <button
              type="button"
              className="button button-small button-danger"
              disabled={remove.isPending}
              onClick={() => {
                if (!file.etag || name === null) return;
                remove.mutate(
                  { scope: scope.id, kind: kind.id, name, etag: file.etag },
                  { onSuccess: onDeleted, onError: handleError },
                );
              }}
            >
              {t("config.delete_yes")}
            </button>
          </div>
        </div>
      )}

      <div className="form-actions config-actions">
        {exists && (
          <button
            type="button"
            className="button button-danger"
            onClick={() => {
              setConfirmDelete(true);
            }}
          >
            {t("config.delete")}
          </button>
        )}
        <span className="config-actions-spacer" />
        {dirty && (
          <button
            type="button"
            className="button"
            onClick={() => {
              setDraft(base);
              setNewName("");
            }}
          >
            {t("config.discard")}
          </button>
        )}
        <button
          type="button"
          className="button"
          disabled={problem !== null || draft === ""}
          title={t("config.apply_title_hint")}
          onClick={() => {
            onApply({ name: effectiveName, content: draft });
          }}
        >
          {t("config.apply")}
        </button>
        <button
          type="button"
          className="button button-primary"
          disabled={problem !== null || stale || (!dirty && exists)}
          onClick={() => {
            setShowDiff(true);
          }}
        >
          {exists ? t("config.save") : t("config.create")}
        </button>
      </div>

      {showDiff && (
        <ConfigDiffDialog
          path={isNew ? effectiveName : path}
          before={base}
          after={draft}
          pending={write.isPending}
          error={write.error && !STALE_CODES.has(write.error.code) ? write.error : null}
          onConfirm={save}
          onClose={() => {
            setShowDiff(false);
            write.reset();
          }}
        />
      )}
    </div>
  );
}
