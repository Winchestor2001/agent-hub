import { useState, type SubmitEvent } from "react";

import { useAddProject } from "../api/queries";
import { slugify, splitLines } from "../board/model";
import { useI18n } from "../i18n/context";
import { ErrorText } from "./ErrorText";
import { Field, Modal } from "./Modal";

interface AddProjectDialogProps {
  onClose: () => void;
  onAdded: (projectId: string) => void;
}

export function AddProjectDialog({ onClose, onAdded }: AddProjectDialogProps) {
  const { t } = useI18n();
  const addProject = useAddProject();
  const [name, setName] = useState("");
  // null — ID nomdan avtomatik olinadi; foydalanuvchi tahrirlasa o'shani saqlaymiz.
  const [customId, setCustomId] = useState<string | null>(null);
  const [backlogDir, setBacklogDir] = useState("");
  const [repos, setRepos] = useState("");

  const id = customId ?? slugify(name);

  function submit(event: SubmitEvent) {
    event.preventDefault();
    addProject.mutate(
      { id, name: name.trim(), backlog_dir: backlogDir.trim(), repos: splitLines(repos) },
      {
        onSuccess: (project) => {
          onAdded(project.id);
          onClose();
        },
      },
    );
  }

  return (
    <Modal title={t("projects.add_title")} onClose={onClose}>
      <form className="form" onSubmit={submit}>
        <Field label={t("projects.field_name")}>
          <input
            value={name}
            required
            maxLength={100}
            onChange={(e) => {
              setName(e.target.value);
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
        <Field label={t("projects.field_backlog_dir")} hint={t("projects.field_backlog_dir_hint")}>
          <input
            className="mono"
            value={backlogDir}
            required
            maxLength={1024}
            onChange={(e) => {
              setBacklogDir(e.target.value);
            }}
          />
        </Field>
        <Field label={t("projects.field_repos")} hint={t("projects.field_repos_hint")}>
          <textarea
            className="mono"
            rows={2}
            value={repos}
            onChange={(e) => {
              setRepos(e.target.value);
            }}
          />
        </Field>
        {addProject.error && <ErrorText error={addProject.error} />}
        <footer className="form-actions">
          <button type="button" className="button" onClick={onClose}>
            {t("common.cancel")}
          </button>
          <button type="submit" className="button button-primary" disabled={addProject.isPending}>
            {addProject.isPending ? t("common.saving") : t("common.add")}
          </button>
        </footer>
      </form>
    </Modal>
  );
}
