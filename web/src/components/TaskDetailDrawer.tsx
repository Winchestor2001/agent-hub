import { useEffect, useRef, useState, type SubmitEvent, type ReactNode } from "react";

import {
  useAddLabels,
  useCompleteTask,
  useDeleteTask,
  useSetAcceptance,
  useSetStatus,
  useTaskDetail,
} from "../api/queries";
import type { Board, ChecklistItem, TaskDetail } from "../api/types";
import { collectLabels, milestoneTitle, splitList } from "../board/model";
import { useI18n } from "../i18n/context";
import { paneActivity } from "../sessions/model";
import { ErrorText } from "./ErrorText";
import { Ago, StateBadge } from "./SessionBits";

interface TaskDetailDrawerProps {
  projectId: string;
  taskId: string;
  board: Board;
  onOpen: (taskId: string) => void;
  onStartSession: (taskId: string) => void;
  /** Status muvaffaqiyatli o'zgardi — doska qaror qiladi (masalan, sessiya dialogini ochish). */
  onStatusChanged: (taskId: string, status: string) => void;
  onOpenTerminal: (paneId: string) => void;
  onClose: () => void;
}

export function TaskDetailDrawer({
  projectId,
  taskId,
  board,
  onOpen,
  onStartSession,
  onStatusChanged,
  onOpenTerminal,
  onClose,
}: TaskDetailDrawerProps) {
  const { t } = useI18n();
  const detail = useTaskDetail(projectId, taskId);
  const ref = useRef<HTMLElement>(null);

  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      // Modal ochiq bo'lsa Escape'ni o'zi ushlaydi; doska yashirin bo'lsa (terminal) Escape pane'niki.
      const visible = ref.current?.offsetParent != null;
      if (event.key === "Escape" && visible && !document.querySelector("dialog[open]")) onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
    };
  }, [onClose]);

  const task = detail.data;

  return (
    <aside ref={ref} className="drawer" aria-label={task ? `${task.id} ${task.title}` : taskId}>
      <header className="drawer-header">
        <span className="card-id mono">{task?.id ?? taskId}</span>
        <h3 className="drawer-title">{task?.title}</h3>
        <button
          type="button"
          className="button button-small"
          title={t("task.start_session_title")}
          onClick={() => {
            onStartSession(task?.id ?? taskId);
          }}
        >
          {t("task.start_session")}
        </button>
        <button type="button" className="icon-button" aria-label={t("common.close")} onClick={onClose}>
          ×
        </button>
      </header>
      <div className="drawer-body">
        {task ? (
          <DetailBody
            projectId={projectId}
            task={task}
            board={board}
            onOpen={onOpen}
            onStatusChanged={onStatusChanged}
            onOpenTerminal={onOpenTerminal}
            onClose={onClose}
          />
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
  onStatusChanged: (taskId: string, status: string) => void;
  onOpenTerminal: (paneId: string) => void;
  onClose: () => void;
}

function DetailBody({
  projectId,
  task,
  board,
  onOpen,
  onStatusChanged,
  onOpenTerminal,
  onClose,
}: DetailBodyProps) {
  const { t } = useI18n();
  const setStatus = useSetStatus(projectId);
  const completeTask = useCompleteTask(projectId);
  const deleteTask = useDeleteTask(projectId, onClose);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const statuses = board.statuses.includes(task.status) ? board.statuses : [...board.statuses, task.status];
  const byId = new Map(board.tasks.map((item) => [item.id.toLowerCase(), item]));
  const doneStatus = statuses.find((status) => status.toLowerCase() === "done") ?? "Done";
  const isDone = task.status === doneStatus;
  const acceptanceDone = task.acceptance_criteria.filter((item) => item.checked).length;
  const acceptanceTotal = task.acceptance_criteria.length;
  const acceptanceReady = acceptanceTotal === 0 || acceptanceDone === acceptanceTotal;
  const hasFinishedSession = task.sessions.some((pane) => !pane.alive || pane.state === "done");

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
              const status = e.target.value;
              setStatus.mutate(
                { taskId: task.id, status },
                {
                  onSuccess: () => {
                    onStatusChanged(task.id, status);
                  },
                },
              );
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

      <DetailSection title={t("task.sessions")} count={task.sessions.length}>
        {task.sessions.length > 0 ? (
          <ul className="links">
            {task.sessions.map((pane) => (
              <li key={pane.id}>
                <button
                  type="button"
                  className="link-row"
                  title={`${t("task.open_terminal")} · ${pane.cwd}`}
                  onClick={() => {
                    onOpenTerminal(pane.id);
                  }}
                >
                  <StateBadge state={pane.state} approximate={pane.approximate} />
                  <span className="mono">{pane.agent}</span>
                  <span className="link-row-title">{pane.title || pane.cwd}</span>
                  <Ago timestamp={paneActivity(pane)} />
                </button>
              </li>
            ))}
          </ul>
        ) : (
          <span className="muted">
            {task.kanbot_available ? t("task.no_sessions") : t("sessions.unavailable")}
          </span>
        )}
      </DetailSection>

      <DetailSection title={t("task.lifecycle_title")}>
        <div className="lifecycle-card">
          <p className="muted">
            {t("task.lifecycle_hint", {
              done: acceptanceDone,
              total: acceptanceTotal,
              sessions: task.sessions.length,
            })}
          </p>
          {!acceptanceReady && <p className="warning-text">{t("task.lifecycle_ac_pending")}</p>}
          {hasFinishedSession && <p className="muted">{t("task.lifecycle_finished_session")}</p>}
          {completeTask.error && <ErrorText error={completeTask.error} />}
          <button
            type="button"
            className="button button-small button-primary"
            disabled={completeTask.isPending || isDone || !acceptanceReady}
            title={!acceptanceReady ? t("task.lifecycle_done_disabled") : undefined}
            onClick={() => {
              completeTask.mutate(task.id);
            }}
          >
            {isDone
              ? t("task.lifecycle_done_already")
              : completeTask.isPending
                ? t("common.saving")
                : t("task.lifecycle_mark_done")}
          </button>
        </div>
      </DetailSection>

      <Section title={t("task.description")} text={task.description} />
      <AcceptanceChecklist projectId={projectId} task={task} />
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
      <DetailSection title={t("task.danger_zone")}>
        <div className="danger-card">
          <p className="muted">{t("task.delete_hint")}</p>
          {confirmDelete ? (
            <>
              <p className="warning-text">{t("task.delete_confirm", { task: task.id })}</p>
              {deleteTask.error && <ErrorText error={deleteTask.error} />}
              <div className="form-actions">
                <button
                  type="button"
                  className="button button-small"
                  disabled={deleteTask.isPending}
                  onClick={() => {
                    setConfirmDelete(false);
                    deleteTask.reset();
                  }}
                >
                  {t("common.cancel")}
                </button>
                <button
                  type="button"
                  className="button button-small button-danger"
                  disabled={deleteTask.isPending}
                  onClick={() => {
                    deleteTask.mutate(task.id);
                  }}
                >
                  {deleteTask.isPending ? t("task.deleting") : t("task.delete_yes")}
                </button>
              </div>
            </>
          ) : (
            <button
              type="button"
              className="button button-small button-danger"
              onClick={() => {
                setConfirmDelete(true);
              }}
            >
              {t("task.delete")}
            </button>
          )}
        </div>
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

function AcceptanceChecklist({ projectId, task }: { projectId: string; task: TaskDetail }) {
  const { t } = useI18n();
  const setAcceptance = useSetAcceptance(projectId, task.id);
  const done = task.acceptance_criteria.filter((item) => item.checked).length;
  return (
    <DetailSection title={`${t("task.acceptance")} ${String(done)}/${String(task.acceptance_criteria.length)}`}>
      {task.acceptance_criteria.length > 0 ? (
        <>
          <ul className="checklist">
            {task.acceptance_criteria.map((item) => (
              <li key={item.index} className={item.checked ? "checked" : undefined}>
                <label className="checklist-toggle">
                  <input
                    type="checkbox"
                    checked={item.checked}
                    disabled={setAcceptance.isPending}
                    onChange={(event) => {
                      setAcceptance.mutate({ index: item.index, checked: event.target.checked });
                    }}
                  />
                  <span>
                    <span className="muted">#{item.index}</span> {item.text}
                  </span>
                </label>
              </li>
            ))}
          </ul>
          {setAcceptance.error && <ErrorText error={setAcceptance.error} />}
        </>
      ) : (
        <Empty />
      )}
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
