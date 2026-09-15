import { useEffect, useId, useState, type ReactNode, type SubmitEvent } from "react";

import { useAddProject, useFolder, useFolderSuggestions, useInitBacklog } from "../api/queries";
import { addUnique, baseName, filterFolders, tildify } from "../board/folders";
import { slugify } from "../board/model";
import { useI18n } from "../i18n/context";
import { ErrorText } from "./ErrorText";
import { FolderPicker } from "./FolderPicker";
import { Field, Modal } from "./Modal";

const STATUS_DEBOUNCE_MS = 300;

interface AddProjectDialogProps {
  onClose: () => void;
  onAdded: (projectId: string) => void;
}

function useDebounced<T>(value: T, delay: number): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebounced(value);
    }, delay);
    return () => {
      clearTimeout(timer);
    };
  }, [value, delay]);
  return debounced;
}

export function AddProjectDialog({ onClose, onAdded }: AddProjectDialogProps) {
  const { t } = useI18n();
  const addProject = useAddProject();
  const initBacklog = useInitBacklog();
  const suggestions = useFolderSuggestions();
  const [search, setSearch] = useState("");
  const [name, setName] = useState("");
  // Foydalanuvchi nomni o'zi yozmaguncha u tanlangan papka nomidan olinadi.
  const [nameTouched, setNameTouched] = useState(false);
  // null — ID nomdan avtomatik olinadi; foydalanuvchi tahrirlasa o'shani saqlaymiz.
  const [customId, setCustomId] = useState<string | null>(null);
  const [backlogDir, setBacklogDir] = useState("");
  const [repos, setRepos] = useState<string[]>([]);
  const [picker, setPicker] = useState<"backlog" | "repo" | null>(null);
  const [confirmInit, setConfirmInit] = useState(false);

  const id = customId ?? slugify(name);
  const dir = backlogDir.trim();
  const debouncedDir = useDebounced(dir, STATUS_DEBOUNCE_MS);
  const status = useFolder(debouncedDir, debouncedDir !== "");
  const statusReady = dir !== "" && debouncedDir === dir && !status.isPlaceholderData;
  const backlogMissing = statusReady && status.data?.has_backlog === false;
  const home = suggestions.data?.home ?? status.data?.home ?? "";

  function chooseBacklogDir(path: string) {
    // Server `~` ni ochadi; maydonda qisqa ko'rinish o'qishga qulay.
    setBacklogDir(tildify(path, home));
    if (!nameTouched) setName(baseName(path));
    setPicker(null);
    setConfirmInit(false);
    initBacklog.reset();
  }

  function createBacklog() {
    const path = status.data?.path ?? dir;
    initBacklog.mutate(
      { path, name: name.trim() || baseName(path) },
      {
        onSuccess: () => {
          setConfirmInit(false);
        },
      },
    );
  }

  function submit(event: SubmitEvent) {
    event.preventDefault();
    addProject.mutate(
      { id, name: name.trim(), backlog_dir: dir, repos },
      {
        onSuccess: (project) => {
          onAdded(project.id);
          onClose();
        },
      },
    );
  }

  const folders = filterFolders(suggestions.data?.folders ?? [], search);

  return (
    <Modal title={t("projects.add_title")} onClose={onClose}>
      <form className="form" onSubmit={submit}>
        <Group
          label={t("projects.suggestions_title", {
            root: suggestions.data ? tildify(suggestions.data.root, home) : "~/my-projects",
          })}
        >
          <input
            type="search"
            value={search}
            placeholder={t("projects.suggestions_search")}
            onChange={(e) => {
              setSearch(e.target.value);
            }}
          />
          {suggestions.error && <ErrorText error={suggestions.error} />}
          <ul className="list picker-list">
            {folders.map((folder) => (
              <li key={folder.path}>
                <button
                  type="button"
                  className="list-item picker-entry"
                  aria-current={tildify(folder.path, home) === dir}
                  title={folder.path}
                  onClick={() => {
                    chooseBacklogDir(folder.path);
                  }}
                >
                  <span className="list-item-title">{folder.name}</span>
                  <span className={folder.has_backlog ? "chip chip-ok" : "chip muted"}>
                    {t(folder.has_backlog ? "projects.backlog_yes" : "projects.backlog_no")}
                  </span>
                </button>
              </li>
            ))}
          </ul>
          {suggestions.data && folders.length === 0 && (
            <p className="muted">{t("projects.suggestions_empty")}</p>
          )}
        </Group>

        <div className="form-row">
          <Field label={t("projects.field_name")}>
            <input
              value={name}
              required
              maxLength={100}
              onChange={(e) => {
                setName(e.target.value);
                setNameTouched(true);
              }}
            />
          </Field>
          <Field label={t("projects.field_id")} hint={t("projects.field_id_hint")}>
            <input
              className="mono"
              value={id}
              required
              maxLength={40}
              pattern="[a-z0-9][a-z0-9\-]{0,39}"
              onChange={(e) => {
                setCustomId(e.target.value);
              }}
            />
          </Field>
        </div>

        <Group label={t("projects.field_backlog_dir")} hint={t("projects.field_backlog_dir_hint")}>
          {(labelId) => (
            <>
              <div className="input-row">
                <input
                  className="mono"
                  aria-labelledby={labelId}
                  value={backlogDir}
                  required
                  maxLength={1024}
                  placeholder="~/my-projects/…"
                  onChange={(e) => {
                    setBacklogDir(e.target.value);
                    setConfirmInit(false);
                    initBacklog.reset();
                  }}
                />
                <button
                  type="button"
                  className="button"
                  aria-expanded={picker === "backlog"}
                  onClick={() => {
                    setPicker(picker === "backlog" ? null : "backlog");
                  }}
                >
                  {t("projects.choose")}
                </button>
              </div>
              {picker === "backlog" && (
                <FolderPicker
                  initialPath={dir}
                  onSelect={chooseBacklogDir}
                  onCancel={() => {
                    setPicker(null);
                  }}
                />
              )}
              {statusReady && status.error && <ErrorText error={status.error} />}
              {statusReady && status.data?.has_backlog && (
                <p className="field-ok">{t("projects.backlog_found")}</p>
              )}
              {backlogMissing && !confirmInit && (
                <div className="notice">
                  <span>{t("projects.backlog_missing")}</span>
                  <button
                    type="button"
                    className="button button-small"
                    onClick={() => {
                      setConfirmInit(true);
                    }}
                  >
                    {t("projects.init")}
                  </button>
                </div>
              )}
              {backlogMissing && confirmInit && (
                <div className="confirm confirm-neutral">
                  <span>
                    {t("projects.init_confirm", {
                      path: tildify(status.data?.path ?? dir, home),
                    })}
                  </span>
                  {initBacklog.error && <ErrorText error={initBacklog.error} />}
                  <div className="form-actions">
                    <button
                      type="button"
                      className="button button-small"
                      onClick={() => {
                        setConfirmInit(false);
                      }}
                    >
                      {t("common.cancel")}
                    </button>
                    <button
                      type="button"
                      className="button button-small button-primary"
                      disabled={initBacklog.isPending}
                      onClick={createBacklog}
                    >
                      {initBacklog.isPending ? t("projects.init_pending") : t("projects.init_yes")}
                    </button>
                  </div>
                </div>
              )}
            </>
          )}
        </Group>

        <Group label={t("projects.field_repos")} hint={t("projects.field_repos_hint")}>
          {repos.length === 0 ? (
            <p className="muted">{t("projects.repos_empty")}</p>
          ) : (
            <ul className="list">
              {repos.map((repo) => (
                <li key={repo} className="repo-row">
                  <span className="mono" title={repo}>
                    {tildify(repo, home)}
                  </span>
                  <button
                    type="button"
                    className="icon-button"
                    aria-label={t("projects.remove_repo")}
                    title={t("projects.remove_repo")}
                    onClick={() => {
                      setRepos(repos.filter((item) => item !== repo));
                    }}
                  >
                    ×
                  </button>
                </li>
              ))}
            </ul>
          )}
          {picker === "repo" ? (
            <FolderPicker
              initialPath={dir}
              onSelect={(path) => {
                setRepos(addUnique(repos, path));
                setPicker(null);
              }}
              onCancel={() => {
                setPicker(null);
              }}
            />
          ) : (
            <div>
              <button
                type="button"
                className="button button-small"
                onClick={() => {
                  setPicker("repo");
                }}
              >
                {t("projects.add_repo")}
              </button>
            </div>
          )}
        </Group>

        {addProject.error && <ErrorText error={addProject.error} />}
        <footer className="form-actions">
          <button type="button" className="button" onClick={onClose}>
            {t("common.cancel")}
          </button>
          <button
            type="submit"
            className="button button-primary"
            disabled={addProject.isPending || backlogMissing}
          >
            {addProject.isPending ? t("common.saving") : t("common.add")}
          </button>
        </footer>
      </form>
    </Modal>
  );
}

interface GroupProps {
  label: string;
  hint?: string;
  children: ReactNode | ((labelId: string) => ReactNode);
}

/** `Field`ga o'xshash, lekin ichida tugmalar bo'lgani uchun `<label>` emas — `role="group"`. */
function Group({ label, hint, children }: GroupProps) {
  const labelId = useId();
  return (
    <div className="field" role="group" aria-labelledby={labelId}>
      <span className="field-label" id={labelId}>
        {label}
      </span>
      {typeof children === "function" ? children(labelId) : children}
      {hint && <span className="field-hint">{hint}</span>}
    </div>
  );
}
