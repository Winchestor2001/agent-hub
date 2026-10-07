import { useMemo, useState, type DragEvent } from "react";

import { useBoard, useKillSessions, useSetStatus } from "../api/queries";
import type { Board, LivePane, ProjectItem, TaskItem } from "../api/types";
import {
  ALL,
  collectLabels,
  EMPTY_FILTER,
  filterTasks,
  groupByStatus,
  NO_MILESTONE,
  sessionsToClose,
  shouldOpenSession,
  statusTone,
  type BoardFilter,
} from "../board/model";
import { useI18n } from "../i18n/context";
import { CreateTaskDialog } from "./CreateTaskDialog";
import { ErrorText } from "./ErrorText";
import { Panel } from "./Panel";
import { StateBadge } from "./SessionBits";
import { TaskDetailDrawer } from "./TaskDetailDrawer";

const DRAG_TYPE = "application/x-agent-hub-task";

interface BoardPanelProps {
  project: ProjectItem | null;
  openTaskId: string | null;
  onOpenTask: (taskId: string | null) => void;
  /** Yangi sessiya dialogi; vazifa detalidan chaqirilsa vazifa oldindan tanlanadi. */
  onStartSession: (taskId: string | null) => void;
  onOpenTerminal: (paneId: string) => void;
  /** Terminal ochiq: doska yashiriladi, lekin filtr va ochiq detal saqlanadi. */
  hidden: boolean;
}

export function BoardPanel({ project, hidden, ...viewProps }: BoardPanelProps) {
  const { t } = useI18n();

  if (!project) {
    return (
      <Panel title={t("panel.board")} className="panel-board" hidden={hidden}>
        <p className="muted placeholder">{t("board.select_project")}</p>
      </Panel>
    );
  }

  return (
    <Panel
      title={`${t("panel.board")} · ${project.name}`}
      aside={<span className="muted mono">{project.backlog_dir}</span>}
      className="panel-board"
      hidden={hidden}
    >
      {project.error ? (
        <ErrorText error={project.error} />
      ) : (
        // Loyiha almashsa filtr va dialoglar tozalanadi.
        <BoardView key={project.id} projectId={project.id} {...viewProps} />
      )}
    </Panel>
  );
}

function BoardView({
  projectId,
  openTaskId,
  onOpenTask,
  onStartSession,
  onOpenTerminal,
}: Omit<BoardPanelProps, "project" | "hidden"> & { projectId: string }) {
  const { t } = useI18n();
  const board = useBoard(projectId);
  const setStatus = useSetStatus(projectId);
  const kill = useKillSessions(projectId);
  const [filter, setFilter] = useState<BoardFilter>(EMPTY_FILTER);
  const [creating, setCreating] = useState(false);
  /** Tugagan vazifaning yopilishi kutilayotgan pane'lari — tasdiq so'raladi. */
  const [closing, setClosing] = useState<{ taskId: string; panes: LivePane[] } | null>(null);

  if (!board.data) {
    return board.error ? (
      <ErrorText error={board.error} />
    ) : (
      <p className="muted placeholder">{t("board.loading")}</p>
    );
  }

  const tasks = board.data.tasks;
  const statuses = board.data.statuses;

  /**
   * Vazifa jarayonga o'tdi — agent ishni darhol boshlashi uchun sessiya dialogi ochiladi;
   * tugadi — ochiq qolgan agentni yopish taklif qilinadi (o'zi yopilmaydi: agent ishlayotgan bo'lishi mumkin).
   */
  function statusChanged(taskId: string, status: string) {
    const task = tasks.find((item) => item.id === taskId);
    if (shouldOpenSession(task, status)) {
      onStartSession(taskId);
      return;
    }
    const panes = sessionsToClose(task, status, statuses);
    if (panes.length > 0) {
      kill.reset();
      setClosing({ taskId, panes });
    }
  }

  return (
    <div className="board">
      <FilterBar
        board={board.data}
        filter={filter}
        onChange={setFilter}
        onCreate={() => {
          setCreating(true);
        }}
      />
      {setStatus.error && (
        <div className="board-error">
          <span>{t("board.status_failed")}:</span>
          <ErrorText error={setStatus.error} />
        </div>
      )}
      {closing && (
        <div className="confirm" role="alertdialog" aria-label={t("board.close_session")}>
          <p>
            {t("board.close_session_confirm", { task: closing.taskId, count: closing.panes.length })}
          </p>
          {kill.error && (
            <span>
              {t("board.close_failed")}: <ErrorText error={kill.error} />
            </span>
          )}
          <div className="form-actions">
            <button
              type="button"
              className="button button-small"
              disabled={kill.isPending}
              onClick={() => {
                setClosing(null);
                kill.reset();
              }}
            >
              {t("common.cancel")}
            </button>
            <button
              type="button"
              className="button button-small button-danger"
              disabled={kill.isPending}
              onClick={() => {
                kill.mutate(
                  closing.panes.map((pane) => pane.id),
                  {
                    onSuccess: () => {
                      setClosing(null);
                    },
                  },
                );
              }}
            >
              {kill.isPending ? t("board.closing") : t("board.close_session_yes")}
            </button>
          </div>
        </div>
      )}
      <Columns
        board={board.data}
        filter={filter}
        openTaskId={openTaskId}
        pendingTaskId={setStatus.isPending ? setStatus.variables.taskId : null}
        onOpen={onOpenTask}
        onMove={(taskId, status) => {
          setStatus.mutate(
            { taskId, status },
            {
              onSuccess: () => {
                statusChanged(taskId, status);
              },
            },
          );
        }}
      />
      {openTaskId && (
        <TaskDetailDrawer
          key={openTaskId}
          projectId={projectId}
          taskId={openTaskId}
          board={board.data}
          onOpen={onOpenTask}
          onStartSession={onStartSession}
          onStatusChanged={statusChanged}
          onOpenTerminal={onOpenTerminal}
          onClose={() => {
            onOpenTask(null);
          }}
        />
      )}
      {creating && (
        <CreateTaskDialog
          projectId={projectId}
          board={board.data}
          onClose={() => {
            setCreating(false);
          }}
          onCreated={(taskId, startSession) => {
            onOpenTask(taskId);
            if (startSession) onStartSession(taskId);
          }}
        />
      )}
    </div>
  );
}

interface FilterBarProps {
  board: Board;
  filter: BoardFilter;
  onChange: (filter: BoardFilter) => void;
  onCreate: () => void;
}

function FilterBar({ board, filter, onChange, onCreate }: FilterBarProps) {
  const { t } = useI18n();
  const labels = useMemo(() => collectLabels(board.labels, board.tasks), [board.labels, board.tasks]);
  const shown = filterTasks(board.tasks, filter, board.milestones).length;
  const active = filter.labels.length > 0 || filter.milestone !== ALL;

  function toggleLabel(label: string) {
    const selected = filter.labels.includes(label);
    onChange({
      ...filter,
      labels: selected ? filter.labels.filter((l) => l !== label) : [...filter.labels, label],
    });
  }

  return (
    <div className="filter-bar">
      <div className="filter-group" role="group" aria-label={t("board.filter_labels")}>
        <span className="filter-label">{t("board.filter_labels")}</span>
        {labels.length === 0 && <span className="muted">{t("board.no_labels")}</span>}
        {labels.map((label) => (
          <button
            key={label}
            type="button"
            className="chip chip-toggle"
            aria-pressed={filter.labels.includes(label)}
            onClick={() => {
              toggleLabel(label);
            }}
          >
            {label}
          </button>
        ))}
      </div>
      <label className="filter-group">
        <span className="filter-label">{t("board.filter_milestone")}</span>
        <select
          value={filter.milestone}
          onChange={(e) => {
            onChange({ ...filter, milestone: e.target.value });
          }}
        >
          <option value={ALL}>{t("board.milestone_all")}</option>
          {board.milestones.map((m) => (
            <option key={m.id} value={m.id}>
              {t("board.milestone_progress", { title: m.title, done: m.done, total: m.total })}
            </option>
          ))}
          <option value={NO_MILESTONE}>{t("board.milestone_none")}</option>
        </select>
      </label>
      {active && (
        <button
          type="button"
          className="button button-small"
          onClick={() => {
            onChange(EMPTY_FILTER);
          }}
        >
          {t("board.filter_clear")}
        </button>
      )}
      <span className="filter-count muted">
        {t("board.shown", { shown, total: board.tasks.length })}
      </span>
      <button type="button" className="button button-small button-primary" onClick={onCreate}>
        {t("board.new_task")}
      </button>
    </div>
  );
}

interface ColumnsProps {
  board: Board;
  filter: BoardFilter;
  openTaskId: string | null;
  pendingTaskId: string | null;
  onOpen: (taskId: string) => void;
  onMove: (taskId: string, status: string) => void;
}

function Columns({ board, filter, openTaskId, pendingTaskId, onOpen, onMove }: ColumnsProps) {
  const { t } = useI18n();
  const [dragged, setDragged] = useState<TaskItem | null>(null);
  const [overStatus, setOverStatus] = useState<string | null>(null);

  const columns = useMemo(
    () => groupByStatus(filterTasks(board.tasks, filter, board.milestones), board.statuses),
    [board.tasks, board.statuses, board.milestones, filter],
  );

  const canDrop = (status: string) => dragged !== null && dragged.status !== status;

  function drop(event: DragEvent, status: string) {
    event.preventDefault();
    if (dragged && canDrop(status)) onMove(dragged.id, status);
    setDragged(null);
    setOverStatus(null);
  }

  return (
    <div className="columns">
      {columns.map((column) => {
        const configIndex = board.statuses.indexOf(column.status);
        const tone =
          configIndex === -1 ? "tone-progress" : statusTone(configIndex, board.statuses.length);
        return (
          <section
            key={column.status}
            className={`column${overStatus === column.status ? " column-drop" : ""}`}
            aria-label={column.status}
            onDragOver={(event) => {
              if (!canDrop(column.status)) return;
              event.preventDefault();
              event.dataTransfer.dropEffect = "move";
              setOverStatus(column.status);
            }}
            onDragLeave={(event) => {
              if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setOverStatus(null);
            }}
            onDrop={(event) => {
              drop(event, column.status);
            }}
          >
            <header className="column-header">
              <span className={`dot ${tone}`} aria-hidden="true" />
              <h3>{column.status}</h3>
              <span className="count">{column.tasks.length}</span>
            </header>
            <ul className="column-body">
              {column.tasks.length === 0 && <li className="muted column-empty">{t("board.column_empty")}</li>}
              {column.tasks.map((task) => (
                <li key={task.id}>
                  <TaskCard
                    task={task}
                    open={task.id === openTaskId}
                    pending={task.id === pendingTaskId}
                    onOpen={onOpen}
                    onDragStart={(event) => {
                      event.dataTransfer.setData(DRAG_TYPE, task.id);
                      event.dataTransfer.effectAllowed = "move";
                      setDragged(task);
                    }}
                    onDragEnd={() => {
                      setDragged(null);
                      setOverStatus(null);
                    }}
                  />
                </li>
              ))}
            </ul>
          </section>
        );
      })}
    </div>
  );
}

interface TaskCardProps {
  task: TaskItem;
  open: boolean;
  pending: boolean;
  onOpen: (taskId: string) => void;
  onDragStart: (event: DragEvent) => void;
  onDragEnd: () => void;
}

function TaskCard({ task, open, pending, onOpen, onDragStart, onDragEnd }: TaskCardProps) {
  const { t } = useI18n();
  const acDone = task.acceptance_criteria_count > 0 && task.acceptance_criteria_completed === task.acceptance_criteria_count;
  const dodDone = task.dod_count > 0 && task.dod_completed === task.dod_count;

  return (
    <button
      type="button"
      className={`card${pending ? " card-pending" : ""}`}
      aria-current={open}
      title={t("board.drag_hint")}
      draggable
      onClick={() => {
        onOpen(task.id);
      }}
      onDragStart={onDragStart}
      onDragEnd={onDragEnd}
    >
      <span className="card-top">
        <span className="card-id mono">{task.id}</span>
        {task.parent_task_id && (
          <span className="muted mono">{t("card.subtask_of", { parent: task.parent_task_id })}</span>
        )}
        {task.assignees.length > 0 && <span className="card-assignee">{task.assignees.join(", ")}</span>}
      </span>
      <span className="card-title">{task.title}</span>
      {task.sessions.length > 0 && (
        <span className="card-sessions" title={t("card.sessions_title")}>
          {task.sessions.map((pane) => (
            <span key={pane.id} className="card-session">
              <span className="mono">{pane.agent}</span>
              <StateBadge state={pane.state} approximate={pane.approximate} />
            </span>
          ))}
        </span>
      )}
      {(task.labels.length > 0 || task.acceptance_criteria_count > 0 || task.dod_count > 0) && (
        <span className="card-meta">
          {task.labels.map((label) => (
            <span key={label} className={`chip${label.toLowerCase() === "bug" ? " chip-bug" : ""}`}>
              {label}
            </span>
          ))}
          <span className="card-progress">
            {task.acceptance_criteria_count > 0 && (
              <span className={acDone ? "progress-done" : undefined} title={t("card.ac_title")}>
                {t("card.ac", { done: task.acceptance_criteria_completed, total: task.acceptance_criteria_count })}
              </span>
            )}
            {task.dod_count > 0 && (
              <span className={dodDone ? "progress-done" : undefined} title={t("card.dod_title")}>
                {t("card.dod", { done: task.dod_completed, total: task.dod_count })}
              </span>
            )}
          </span>
        </span>
      )}
    </button>
  );
}
