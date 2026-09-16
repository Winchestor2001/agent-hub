import { useState, type SubmitEvent } from "react";

import { useCreateTask } from "../api/queries";
import type { Board, TaskCreate, UploadedFile } from "../api/types";
import { collectLabels, splitLines, splitList } from "../board/model";
import { useI18n } from "../i18n/context";
import { ErrorText } from "./ErrorText";
import { FileAttach } from "./FileAttach";
import { Field, Modal } from "./Modal";

interface CreateTaskDialogProps {
  projectId: string;
  board: Board;
  onClose: () => void;
  onCreated: (taskId: string) => void;
}

export function CreateTaskDialog({ projectId, board, onClose, onCreated }: CreateTaskDialogProps) {
  const { t } = useI18n();
  const createTask = useCreateTask(projectId);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [status, setStatus] = useState(board.statuses[0] ?? "");
  const [labels, setLabels] = useState("");
  const [assignees, setAssignees] = useState("");
  const [milestone, setMilestone] = useState("");
  const [acceptance, setAcceptance] = useState("");
  const [files, setFiles] = useState<UploadedFile[]>([]);
  const listId = `new-task-labels-${projectId}`;

  function submit(event: SubmitEvent) {
    event.preventDefault();
    const body: TaskCreate = {
      title: title.trim(),
      labels: splitList(labels),
      assignees: splitList(assignees),
      acceptance_criteria: splitLines(acceptance),
    };
    if (description.trim()) body.description = description.trim();
    if (status) body.status = status;
    if (milestone) body.milestone = milestone;
    if (files.length > 0) body.files = files.map((file) => file.path);
    createTask.mutate(body, {
      onSuccess: ({ id }) => {
        onCreated(id);
        onClose();
      },
    });
  }

  return (
    <Modal title={t("task_form.title")} onClose={onClose}>
      <form className="form" onSubmit={submit}>
        <Field label={t("task_form.field_title")}>
          <input
            value={title}
            required
            maxLength={200}
            onChange={(e) => {
              setTitle(e.target.value);
            }}
          />
        </Field>
        <Field label={t("task_form.description")}>
          <textarea
            rows={4}
            value={description}
            maxLength={20000}
            onChange={(e) => {
              setDescription(e.target.value);
            }}
          />
        </Field>
        <div className="form-row">
          <Field label={t("task.status")}>
            <select
              value={status}
              onChange={(e) => {
                setStatus(e.target.value);
              }}
            >
              {board.statuses.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </Field>
          <Field label={t("task.milestone")}>
            <select
              value={milestone}
              onChange={(e) => {
                setMilestone(e.target.value);
              }}
            >
              <option value="">{t("common.none")}</option>
              {board.milestones
                .filter((m) => !m.completed)
                .map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.title}
                  </option>
                ))}
            </select>
          </Field>
        </div>
        <div className="form-row">
          <Field label={t("task_form.labels")} hint={t("task_form.labels_hint")}>
            <input
              value={labels}
              list={listId}
              onChange={(e) => {
                setLabels(e.target.value);
              }}
            />
            <datalist id={listId}>
              {collectLabels(board.labels, board.tasks).map((label) => (
                <option key={label} value={label} />
              ))}
            </datalist>
          </Field>
          <Field label={t("task_form.assignees")} hint={t("task_form.assignees_hint")}>
            <input
              value={assignees}
              onChange={(e) => {
                setAssignees(e.target.value);
              }}
            />
          </Field>
        </div>
        <Field label={t("task_form.acceptance")} hint={t("task_form.acceptance_hint")}>
          <textarea
            rows={3}
            value={acceptance}
            onChange={(e) => {
              setAcceptance(e.target.value);
            }}
          />
        </Field>
        <FileAttach projectId={projectId} files={files} onChange={setFiles} />
        {createTask.error && <ErrorText error={createTask.error} />}
        <footer className="form-actions">
          <button type="button" className="button" onClick={onClose}>
            {t("common.cancel")}
          </button>
          <button type="submit" className="button button-primary" disabled={createTask.isPending}>
            {createTask.isPending ? t("common.saving") : t("task_form.create")}
          </button>
        </footer>
      </form>
    </Modal>
  );
}
