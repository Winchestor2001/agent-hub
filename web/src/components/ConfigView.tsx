import { useCallback, useMemo, useState, type ReactNode } from "react";

import { useConfigGuides, useConfigItems, useConfigScopes } from "../api/queries";
import type { ConfigKind, ConfigScope } from "../api/types";
import { filterItems, firstKind, kindFits, lookup, orderKinds } from "../config/model";
import { useI18n } from "../i18n/context";
import { ConfigEditor } from "./ConfigEditor";
import { ConfigGuidePanel } from "./ConfigGuidePanel";
import { ErrorText } from "./ErrorText";

interface ConfigViewProps {
  initialScope: string;
  /** Boshlang'ich tur (odatda — qamrovdagi birinchisi). */
  initialKind?: string;
  onClose: () => void;
}

/** Tanlangan element: mavjud nom yoki to'plamga yangi element (`null`). */
type Selection = { name: string | null } | null;

/** Claude Code konfiguratsiyasi: qamrov → tur → element → muharrir (asosiy panellar o'rnida). */
export function ConfigView({ initialScope, initialKind, onClose }: ConfigViewProps) {
  const { t, message } = useI18n();
  const scopesQuery = useConfigScopes();
  const scopes = useMemo(() => scopesQuery.data?.scopes ?? [], [scopesQuery.data]);
  const kinds = useMemo(() => orderKinds(scopesQuery.data?.kinds ?? []), [scopesQuery.data]);
  const [scopeId, setScopeId] = useState(initialScope);
  const [kindId, setKindId] = useState<string | null>(initialKind ?? null);
  const [selection, setSelection] = useState<Selection>(null);
  const [dirty, setDirty] = useState(false);
  // Saqlanmagan o'zgarish bor paytda boshqa joyga o'tish — avval tasdiq.
  const [pending, setPending] = useState<(() => void) | null>(null);
  const [guideId, setGuideId] = useState<string | null>(null);

  const scope = scopes.find((entry) => entry.id === scopeId) ?? scopes[0];
  const kind =
    kinds.find((entry) => entry.id === kindId && scope && kindFits(entry, scope)) ??
    kinds.find((entry) => entry.id === firstKind(kinds, scope));

  // Belgilangan fayl turlarida (CLAUDE.md, settings) ro'yxat qisqa — birinchisi darhol ochiladi.
  const fixedFirst = kind && scope && !kind.collection ? (kind.fixed[scope.kind]?.[0] ?? null) : null;
  const current: Selection = selection ?? (fixedFirst ? { name: fixedFirst } : null);

  const guard = useCallback(
    (action: () => void) => {
      if (dirty) setPending(() => action);
      else action();
    },
    [dirty],
  );

  if (scopesQuery.error) {
    return (
      <ConfigShell onClose={onClose}>
        <ErrorText error={scopesQuery.error} />
      </ConfigShell>
    );
  }
  if (!scope || !kind) {
    return (
      <ConfigShell onClose={onClose}>
        <p className="muted">{t("config.loading")}</p>
      </ConfigShell>
    );
  }

  return (
    <ConfigShell
      onClose={() => {
        guard(onClose);
      }}
      toolbar={
        <>
          <ScopeSelect
            scopes={scopes}
            value={scope.id}
            onChange={(id) => {
              guard(() => {
                setScopeId(id);
                setSelection(null);
              });
            }}
          />
          <span className="muted mono config-root" title={scope.root}>
            {scope.root}
          </span>
          <GuideButton kind={kind} onOpen={setGuideId} />
        </>
      }
    >
      {pending && (
        <div className="config-warning config-unsaved" role="alertdialog" aria-label={t("config.unsaved")}>
          <p>{t("config.unsaved_confirm")}</p>
          <div className="form-actions">
            <button
              type="button"
              className="button button-small"
              onClick={() => {
                setPending(null);
              }}
            >
              {t("common.cancel")}
            </button>
            <button
              type="button"
              className="button button-small button-danger"
              onClick={() => {
                const action = pending;
                setPending(null);
                setDirty(false);
                action();
              }}
            >
              {t("config.unsaved_discard")}
            </button>
          </div>
        </div>
      )}
      {!scope.exists && <p className="config-warning">{t("config.scope_missing", { path: scope.root })}</p>}
      <div className={guideId ? "config-body config-body-guide" : "config-body"}>
        <nav className="config-kinds" aria-label={t("config.kinds")}>
          <ul className="list">
            {kinds.map((entry) => {
              const fits = kindFits(entry, scope);
              return (
                <li key={entry.id}>
                  <button
                    type="button"
                    className="list-item"
                    aria-current={entry.id === kind.id}
                    disabled={!fits}
                    title={fits ? undefined : t("config.kind_scope_only", { scopes: entry.scopes.join(", ") })}
                    onClick={() => {
                      guard(() => {
                        setKindId(entry.id);
                        setSelection(null);
                      });
                    }}
                  >
                    <span className="list-item-title">{lookup(message, `config.kind.${entry.id}`, entry.id)}</span>
                    <span className="muted config-kind-hint">
                      {lookup(message, `config.kind_hint.${entry.id}.${scope.kind}`, "")}
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        </nav>
        <ItemList
          key={`${scope.id}|${kind.id}`}
          scope={scope}
          kind={kind}
          selected={current}
          onSelect={(next) => {
            guard(() => {
              setSelection(next);
            });
          }}
        />
        <section className="config-main" aria-label={t("config.editor")}>
          {current ? (
            <EditorFor
              key={`${scope.id}|${kind.id}|${current.name ?? "+new"}`}
              scope={scope}
              kind={kind}
              scopes={scopes}
              name={current.name}
              onSaved={(name) => {
                setSelection({ name });
              }}
              onDeleted={() => {
                setSelection(null);
              }}
              onDirtyChange={setDirty}
            />
          ) : (
            <p className="muted placeholder">{t("config.pick_item")}</p>
          )}
        </section>
        {guideId && (
          <ConfigGuidePanel
            guideId={guideId}
            onSelect={setGuideId}
            onClose={() => {
              setGuideId(null);
            }}
          />
        )}
      </div>
    </ConfigShell>
  );
}

function ConfigShell({
  onClose,
  toolbar,
  children,
}: {
  onClose: () => void;
  toolbar?: ReactNode;
  children: ReactNode;
}) {
  const { t } = useI18n();
  return (
    <main className="config-view" aria-label={t("config.title")}>
      <header className="config-header">
        <h2>{t("config.title")}</h2>
        {toolbar}
        <button type="button" className="button button-small config-close" onClick={onClose}>
          {t("config.close")}
        </button>
      </header>
      {children}
    </main>
  );
}

function ScopeSelect({
  scopes,
  value,
  onChange,
}: {
  scopes: ConfigScope[];
  value: string;
  onChange: (id: string) => void;
}) {
  const { t } = useI18n();
  const projects = scopes.filter((scope) => scope.kind === "project");
  return (
    <select
      className="config-scope"
      aria-label={t("config.scope")}
      value={value}
      onChange={(event) => {
        onChange(event.target.value);
      }}
    >
      {scopes
        .filter((scope) => scope.kind === "global")
        .map((scope) => (
          <option key={scope.id} value={scope.id}>
            {t("config.scope_global")}
          </option>
        ))}
      {projects.length > 0 && (
        <optgroup label={t("config.scope_projects")}>
          {projects.map((scope) => (
            <option key={scope.id} value={scope.id}>
              {scope.label}
            </option>
          ))}
        </optgroup>
      )}
    </select>
  );
}

function GuideButton({ kind, onOpen }: { kind: ConfigKind; onOpen: (id: string) => void }) {
  const { t } = useI18n();
  const guides = useConfigGuides();
  const id = guides.data?.guides.find((guide) => guide.kinds.includes(kind.id))?.id ?? "overview";
  return (
    <button
      type="button"
      className="button button-small"
      onClick={() => {
        onOpen(id);
      }}
    >
      {t("config.guide")}
    </button>
  );
}

interface ItemListProps {
  scope: ConfigScope;
  kind: ConfigKind;
  selected: Selection;
  onSelect: (selection: Selection) => void;
}

function ItemList({ scope, kind, selected, onSelect }: ItemListProps) {
  const { t } = useI18n();
  const items = useConfigItems(scope.id, kind.id);
  const [query, setQuery] = useState("");
  const all = items.data?.items ?? [];
  const shown = filterItems(all, query);
  const skipped = items.data?.skipped ?? [];

  return (
    <section className="config-items" aria-label={t("config.items")}>
      {kind.collection && (
        <div className="config-items-head">
          <input
            type="search"
            placeholder={t("config.search", { count: all.length })}
            aria-label={t("config.search_label")}
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
            }}
          />
          <button
            type="button"
            className="button button-small"
            aria-current={selected?.name === null}
            onClick={() => {
              onSelect({ name: null });
            }}
          >
            {t("config.new")}
          </button>
        </div>
      )}
      <div className="config-items-body">
        {items.error ? (
          <ErrorText error={items.error} />
        ) : !items.data ? (
          <p className="muted">{t("config.loading")}</p>
        ) : shown.length === 0 ? (
          <p className="muted">{query ? t("config.search_empty") : t("config.items_empty")}</p>
        ) : (
          <ul className="list">
            {shown.map((item) => {
              const shadowed = item.shadow.some((shadow) => shadow.winner === "other");
              return (
                <li key={item.name}>
                  <button
                    type="button"
                    className="list-item"
                    aria-current={selected?.name === item.name}
                    onClick={() => {
                      onSelect({ name: item.name });
                    }}
                  >
                    <span className="list-item-title">{item.name}</span>
                    <span className="config-item-meta">
                      <span className="muted mono">{item.path}</span>
                      {!item.exists && <span className="chip">{t("config.missing")}</span>}
                      {item.symlink && <span className="chip">symlink</span>}
                      {item.shadow.length > 0 && (
                        <span
                          className={shadowed ? "chip chip-warn" : "chip"}
                          title={shadowed ? t("config.shadowed_title") : t("config.shadows_title")}
                        >
                          {shadowed ? t("config.shadowed") : t("config.shadows")}
                        </span>
                      )}
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        )}
        {skipped.length > 0 && (
          <p className="muted config-skipped" title={skipped.join(", ")}>
            {t("config.skipped", { count: skipped.length })}
          </p>
        )}
      </div>
    </section>
  );
}

/** Ro'yxatdagi element (shadow ma'lumoti) bilan muharrir. */
function EditorFor(props: {
  scope: ConfigScope;
  kind: ConfigKind;
  scopes: ConfigScope[];
  name: string | null;
  onSaved: (name: string) => void;
  onDeleted: () => void;
  onDirtyChange: (dirty: boolean) => void;
}) {
  const items = useConfigItems(props.scope.id, props.kind.id);
  const item = items.data?.items.find((entry) => entry.name === props.name);
  return <ConfigEditor {...props} item={item} />;
}
