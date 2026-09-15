import { useEffect, useState, type SubmitEvent, type ReactNode } from "react";

import { useAddLabels, useSetStatus, useTaskDetail } from "../api/queries";
import type { Board, ChecklistItem, TaskDetail } from "../api/types";
import { collectLabels, milestoneTitle, splitList } from "../board/model";
import { useI18n } from "../i18n/context";
import { ErrorText } from "./ErrorText";

interface TaskDetailDrawerProps {
  projectId: string;
  taskId: string;
  board: Board;
  onOpen: (taskId: string) => void;
  onClose: () => void;
}

export function TaskDetailDrawer({ projectId, taskId, board, onOpen, onClose }: TaskDetailDrawerProps) {
  const { t } = useI18n();
  const detail = useTaskDetail(projectId, taskId);

  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      // Modal ochiq bo'lsa Escape'ni o'zi ushlaydi.
      if (event.key === "Escape" && !document.querySelector("dialog[open]")) onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
    };
  }, [onClose]);

  const task = detail.data;

  return (
    <aside className="drawer" aria-label={task ? `${task.id} ${task.title}` : taskId}>
      <header className="drawer-header">
        <span className="card-id mono">{task?.id ?? taskId}</span>
        <h3 className="drawer-title">{task?.title}</h3>
        <button type="button" className="icon-button" aria-label={t("common.close")} onClick={onClose}>
          ×
        </button>
      </header>
      <div className="drawer-body">
        {task ? (
          <DetailBody projectId={projectId} task={task} board={board} onOpen={onOpen} />
        ) : detail.error ? (
          <ErrorText error={detail.error} />
        ) : (
          <p className="muted">{t("task.loading")}</p>
        )}
      </div>
    </aside>
  );
}

interface DetailBodyProps {
  projectId: string;
  task: TaskDetail;
  board: Board;
  onOpen: (taskId: string) => void;
}

function DetailBody({ projectId, task, board, onOpen }: DetailBodyProps) {
  const { t } = useI18n();
  const setStatus = useSetStatus(projectId);
  const statuses = board.statuses.includes(task.status) ? board.statuses : [...board.statuses, task.status];
  const byId = new Map(board.tasks.map((item) => [item.id.toLowerCase(), item]));

  const taskLink = (id: string, fallbackTitle?: string) => {
    const item = byId.get(id.toLowerCase());
    return (
      <li key={id}>
        {item ? (
          <button
            type="button"
            className="link-row"
            onClick={() => {
              onOpen(item.id);
            }}
          >
            <span className="card-id mono">{item.id}</span>
            <span className="link-row-title">{item.title}</span>
            <span className="chip">{item.status}</span>
          </button>
        ) : (
          <span className="link-row">
            <span className="card-id mono">{id}</span>
            <span className="link-row-title">{fallbackTitle}</span>
            <span className="muted">{t("task.not_on_board")}</span>
          </span>
        )}
      </li>
    );
  };

  return (
    <>
      <dl className="props">
        <dt>{t("task.status")}</dt>
        <dd>
          <select
            value={task.status}
            disabled={setStatus.isPending}
            onChange={(e) => {
              setStatus.mutate({ taskId: task.id, status: e.target.value });
            }}
          >
            {statuses.map((status) => (
              <option key={status} value={status}>
                {status}
              </option>
            ))}
          </select>
          {setStatus.error && <ErrorText error={setStatus.error} />}
        </dd>

        <dt>{t("task.labels")}</dt>
        <dd>
          <LabelEditor projectId={projectId} task={task} board={board} />
        </dd>

        <dt>{t("task.assignees")}</dt>
        <dd>{task.assignees.length > 0 ? task.assignees.join(", ") : <Empty />}</dd>

        <dt>{t("task.milestone")}</dt>
        <dd>{milestoneTitle(task.milestone, board.milestones) ?? <Empty />}</dd>

        {task.priority && (
          <>
            <dt>{t("task.priority")}</dt>
            <dd>{task.priority}</dd>
          </>
        )}
        {task.parent_task_id && (
          <>
            <dt>{t("task.parent")}</dt>
            <dd>
              <ul className="links">{taskLink(task.parent_task_id)}</ul>
            </dd>
          </>
        )}
      </dl>

      <Section title={t("task.description")} text={task.description} />
      <Checklist title={t("task.acceptance")} items={task.acceptance_criteria} />
      {task.definition_of_done.length > 0 && <Checklist title={t("task.dod")} items={task.definition_of_done} />}
      <Section title={t("task.plan")} text={task.implementation_plan} />
      <Section title={t("task.notes")} text={task.implementation_notes} />
      {task.final_summary && <Section title={t("task.final_summary")} text={task.final_summary} />}

      <DetailSection title={t("task.dependencies")} count={task.dependencies.length}>
        {task.dependencies.length > 0 ? (
          <ul className="links">{task.dependencies.map((id) => taskLink(id))}</ul>
        ) : (
          <Empty />
        )}
      </DetailSection>
      <DetailSection title={t("task.subtasks")} count={task.subtasks.length}>
        {task.subtasks.length > 0 ? (
          <ul className="links">{task.subtasks.map((sub) => taskLink(sub.id, sub.title))}</ul>
        ) : (
          <Empty />
        )}
      </DetailSection>
    </>
  );
}

function LabelEditor({ projectId, task, board }: { projectId: string; task: TaskDetail; board: Board }) {
  const { t } = useI18n();
  const addLabels = useAddLabels(projectId);
  const [value, setValue] = useState("");
  const listId = `labels-${projectId}`;
  const known = collectLabels(board.labels, board.tasks).filter(
    (label) => !task.labels.some((own) => own.toLowerCase() === label.toLowerCase()),
  );

  function submit(event: SubmitEvent) {
    event.preventDefault();
    const labels = splitList(value);
    if (labels.length === 0) return;
    addLabels.mutate(
      { taskId: task.id, labels },
      {
        onSuccess: () => {
          setValue("");
        },
      },
    );
  }

  return (
    <div className="label-editor">
      {task.labels.length > 0 && (
        <span className="chips">
          {task.labels.map((label) => (
            <span key={label} className={`chip${label.toLowerCase() === "bug" ? " chip-bug" : ""}`}>
              {label}
            </span>
          ))}
        </span>
      )}
      <form className="inline-form" onSubmit={submit}>
        <input
          value={value}
          list={listId}
          maxLength={200}
          placeholder={t("task.label_placeholder")}
          aria-label={t("task.label_placeholder")}
          onChange={(e) => {
            setValue(e.target.value);
          }}
        />
        <datalist id={listId}>
          {known.map((label) => (
            <option key={label} value={label} />
          ))}
        </datalist>
        <button
          type="submit"
          className="button button-small"
          disabled={addLabels.isPending || splitList(value).length === 0}
        >
          {addLabels.isPending ? t("common.saving") : t("common.add")}
        </button>
      </form>
      {addLabels.error && <ErrorText error={addLabels.error} />}
    </div>
  );
}

function Empty() {
  const { t } = useI18n();
  return <span className="muted">{t("task.empty")}</span>;
}

function DetailSection({ title, count, children }: { title: string; count?: number; children: ReactNode }) {
  return (
    <section className="detail-section">
      <h4>
        {title}
        {count !== undefined && count > 0 && <span className="count">{count}</span>}
      </h4>
      {children}
    </section>
  );
}

function Section({ title, text }: { title: string; text: string | null }) {
  return (
    <DetailSection title={title}>
      {text?.trim() ? <p className="prose">{text}</p> : <Empty />}
    </DetailSection>
  );
}

function Checklist({ title, items }: { title: string; items: ChecklistItem[] }) {
  const done = items.filter((item) => item.checked).length;
  return (
    <DetailSection title={`${title} ${String(done)}/${String(items.length)}`}>
      {items.length > 0 ? (
        <ul className="checklist">
          {items.map((item) => (
            <li key={item.index} className={item.checked ? "checked" : undefined}>
              <span className="check" aria-hidden="true">
                {item.checked ? "✓" : "○"}
              </span>
              <span>
                <span className="muted">#{item.index}</span> {item.text}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <Empty />
      )}
    </DetailSection>
  );
}
