import { useState } from "react";
import type { KeyboardEvent, ReactNode } from "react";

import type { ApiError } from "../api/client";
import {
  useDeleteSessions,
  useKillSessions,
  useLiveSessions,
  usePastSessions,
  useRemoveSessions,
  useResumeSession,
} from "../api/queries";
import type { LivePane, PastSession, ProjectItem, TaskRef } from "../api/types";
import { useI18n } from "../i18n/context";
import {
  BLOCKED,
  baseName,
  groupLive,
  paneActivity,
  pruneSelection,
  sessionKey,
  splitByProject,
  toggleKey,
} from "../sessions/model";
import { focusIndex } from "../sessions/navigation";
import { ErrorText } from "./ErrorText";
import { Panel } from "./Panel";
import { Ago, StateBadge } from "./SessionBits";

export type OpenTask = (projectId: string, taskId: string) => void;

interface SessionsPanelProps {
  project: ProjectItem | null;
  projects: readonly ProjectItem[] | undefined;
  onOpenTask: OpenTask;
  onNewSession: () => void;
  /** `false` — faqat tanlangan loyiha sessiyalari; boshqalarining soni ko'rsatiladi. */
  showAll: boolean;
  onToggleShowAll: () => void;
  /** Markazda ochiq terminal (ro'yxatda belgilanadi). */
  terminalPaneId: string | null;
  onOpenTerminal: (paneId: string) => void;
  /** Olib tashlangan pane terminali ochiq bo'lsa yopiladi. */
  onSessionsRemoved: (paneIds: readonly string[]) => void;
}

export function SessionsPanel({
  project,
  projects,
  onOpenTask,
  onNewSession,
  showAll,
  onToggleShowAll,
  terminalPaneId,
  onOpenTerminal,
  onSessionsRemoved,
}: SessionsPanelProps) {
  const { t } = useI18n();
  const live = useLiveSessions();
  const names = new Map(projects?.map((p) => [p.id, p.name]));
  const projectId = showAll ? null : (project?.id ?? null);
  // Xatoda eski ro'yxat ko'rsatilmaydi: KanBot o'chsa "javob kutmoqda" ham yo'qoladi.
  const split = live.data && !live.error ? splitByProject(live.data.live, projectId) : null;
  const groups = split ? groupLive(split.mine) : null;
  const finished = live.error ? [] : splitByProject(live.data?.finished ?? [], projectId).mine;

  return (
    <Panel
      title={t("panel.sessions")}
      className="panel-sessions"
      aside={
        <button
          type="button"
          className="button button-small"
          title={t("sessions.new_title")}
          disabled={!project}
          onClick={onNewSession}
        >
          {t("sessions.new")}
        </button>
      }
    >
      <div className="sessions-body" onKeyDown={moveSessionFocus}>
      {groups && groups.blocked.length > 0 && (
        <Section title={t("sessions.blocked")} count={groups.blocked.length} className="section-blocked">
          <LiveList panes={groups.blocked} names={names} current={terminalPaneId} onOpenTask={onOpenTask} onOpenTerminal={onOpenTerminal} />
        </Section>
      )}
      <Section title={t("sessions.live")} count={groups?.others.length}>
        <QueryBody error={live.error} loaded={groups !== null} empty={groups?.others.length === 0}>
          {groups && <LiveList panes={groups.others} names={names} current={terminalPaneId} onOpenTask={onOpenTask} onOpenTerminal={onOpenTerminal} />}
        </QueryBody>
        {split && project && (
          <ScopeHint project={project} showAll={showAll} others={split.others} onToggle={onToggleShowAll} />
        )}
        {groups && <p className="muted session-hint">{t("sessions.shortcut_hint")}</p>}
      </Section>
      {finished.length > 0 && (
        <FinishedSection
          panes={finished}
          names={names}
          current={terminalPaneId}
          onOpenTask={onOpenTask}
          onOpenTerminal={onOpenTerminal}
          onRemoved={onSessionsRemoved}
        />
      )}
      {project ? (
        <PastSection key={project.id} project={project} onOpenTask={onOpenTask} />
      ) : (
        <Section title={t("sessions.past")}>
          <p className="muted">{t("sessions.no_project")}</p>
        </Section>
      )}
      </div>
    </Panel>
  );
}

/** Boshqa loyihalardagi jonli sessiyalar soni va "hammasi / faqat shu loyiha" almashtirgichi. */
function ScopeHint({
  project,
  showAll,
  others,
  onToggle,
}: {
  project: ProjectItem;
  showAll: boolean;
  others: readonly LivePane[];
  onToggle: () => void;
}) {
  const { t } = useI18n();
  if (showAll) {
    return (
      <p className="muted session-scope">
        {t("sessions.showing_all")}
        <button type="button" className="scope-toggle" onClick={onToggle}>
          {t("sessions.show_project", { project: project.name })}
        </button>
      </p>
    );
  }
  if (others.length === 0) return null;
  const blocked = others.filter((pane) => pane.state === BLOCKED).length;
  return (
    <p className="muted session-scope">
      {t("sessions.other_projects", { count: others.length })}
      {blocked > 0 && <span className="scope-blocked">{t("sessions.other_blocked", { count: blocked })}</span>}
      <button type="button" className="scope-toggle" onClick={onToggle}>
        {t("sessions.show_all")}
      </button>
    </p>
  );
}

/** Sessiya sarlavhasi fokusda bo'lsa ↑/↓/Home/End keyingi sarlavhaga o'tadi (barcha bo'limlar bo'ylab). */
function moveSessionFocus(event: KeyboardEvent<HTMLDivElement>) {
  const target = event.target;
  if (!(target instanceof HTMLElement) || !target.classList.contains("session-open")) return;
  if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
  const buttons = [...event.currentTarget.querySelectorAll<HTMLElement>("button.session-open")];
  const next = focusIndex(buttons.length, buttons.indexOf(target), event.key);
  if (next === null) return;
  event.preventDefault();
  buttons[next]?.focus();
}

function Section({
  title,
  count,
  className,
  action,
  children,
}: {
  title: string;
  count?: number | undefined;
  className?: string;
  /** Sarlavha o'ng tomonidagi tugma. */
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className={className ? `section ${className}` : "section"}>
      <h3 className="section-title">
        {title}
        {count !== undefined && <span className="count">{count}</span>}
        {action}
      </h3>
      {children}
    </div>
  );
}

/** KanBot o'chiq, xato, yuklanish va bo'sh holatlar — bitta joyda. */
function QueryBody({
  error,
  loaded,
  empty,
  children,
}: {
  error: ApiError | null;
  loaded: boolean;
  empty: boolean | undefined;
  children: ReactNode;
}) {
  const { t } = useI18n();
  if (error?.code === "kanbot_unavailable") return <p className="muted">{t("sessions.unavailable")}</p>;
  if (error && !loaded) return <ErrorText error={error} />;
  if (!loaded) return <p className="muted">{t("sessions.loading")}</p>;
  if (empty) return <p className="muted">{t("sessions.none")}</p>;
  return children;
}

function LiveList({
  panes,
  names,
  current,
  onOpenTask,
  onOpenTerminal,
}: {
  panes: LivePane[];
  names: Map<string, string>;
  current: string | null;
  onOpenTask: OpenTask;
  onOpenTerminal: (paneId: string) => void;
}) {
  const { t } = useI18n();
  // Loyihalararo ro'yxat: kill'dan keyin barcha doskalar yangilanadi.
  const kill = useKillSessions(null);
  const [closing, setClosing] = useState<string | null>(null);

  return (
    <ul className="list">
      {panes.map((pane) => (
        <li key={pane.id} className={`session session-${pane.state}${pane.id === current ? " session-current" : ""}`}>
          <div className="session-top">
            <StateBadge state={pane.state} approximate={pane.approximate} />
            <span className="session-agent mono">{pane.agent}</span>
            <Ago timestamp={paneActivity(pane)} />
            <button
              type="button"
              className="icon-button"
              aria-label={t("sessions.kill")}
              title={t("sessions.kill")}
              disabled={kill.isPending}
              onClick={() => {
                kill.reset();
                setClosing(pane.id);
              }}
            >
              ■
            </button>
          </div>
          <button
            type="button"
            className="session-title session-open"
            title={`${t("sessions.open_terminal")} · ${pane.title || pane.cwd}`}
            aria-current={pane.id === current ? "true" : undefined}
            onClick={() => {
              onOpenTerminal(pane.id);
            }}
          >
            {pane.title || baseName(pane.cwd)}
          </button>
          <div className="session-meta">
            <span className="muted" title={pane.cwd}>
              {pane.project_id
                ? (names.get(pane.project_id) ?? pane.project_id)
                : t("sessions.outside_project")}
            </span>
            {pane.project_id && pane.task && (
              <TaskLink projectId={pane.project_id} task={pane.task} onOpenTask={onOpenTask} />
            )}
          </div>
          {closing === pane.id && (
            <div className="confirm" role="alertdialog" aria-label={t("sessions.kill")}>
              <p>{t("sessions.kill_confirm", { agent: pane.agent })}</p>
              {kill.error && (
                <span>
                  {t("sessions.kill_failed")}: <ErrorText error={kill.error} />
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
                    kill.mutate([pane.id], {
                      onSuccess: () => {
                        setClosing(null);
                      },
                    });
                  }}
                >
                  {kill.isPending ? t("sessions.killing") : t("sessions.kill_yes")}
                </button>
              </div>
            </div>
          )}
        </li>
      ))}
    </ul>
  );
}

function FinishedSection({
  panes,
  names,
  current,
  onOpenTask,
  onOpenTerminal,
  onRemoved,
}: {
  panes: LivePane[];
  names: Map<string, string>;
  current: string | null;
  onOpenTask: OpenTask;
  onOpenTerminal: (paneId: string) => void;
  onRemoved: (paneIds: readonly string[]) => void;
}) {
  const { t } = useI18n();
  const remove = useRemoveSessions();
  const pending = remove.isPending ? remove.variables : null;

  function removePanes(paneIds: readonly string[]) {
    // `mutate` callback'i emas: oxirgi pane olingach bo'lim unmount bo'ladi va u chaqirilmay qoladi.
    // Xato `remove.error` orqali ko'rsatiladi.
    remove.mutateAsync(paneIds).then(
      () => {
        onRemoved(paneIds);
      },
      () => undefined,
    );
  }

  return (
    <div className="section">
      <h3 className="section-title">
        {t("sessions.finished")}
        <span className="count">{panes.length}</span>
        <button
          type="button"
          className="button button-small section-action"
          title={t("sessions.remove_all_title")}
          disabled={remove.isPending}
          onClick={() => {
            removePanes(panes.map((pane) => pane.id));
          }}
        >
          {t("sessions.remove_all")}
        </button>
      </h3>
      {remove.error && <ErrorText error={remove.error} />}
      <ul className="list">
        {panes.map((pane) => (
          <li
            key={pane.id}
            className={`session session-ended${pane.id === current ? " session-current" : ""}`}
          >
            <div className="session-top">
              <span className="session-agent mono">{pane.agent}</span>
              {pane.exit_code !== null && (
                <span className="muted mono">{t("sessions.exit_code", { code: pane.exit_code })}</span>
              )}
              <Ago timestamp={pane.ended_at ?? paneActivity(pane)} />
              <button
                type="button"
                className="icon-button"
                aria-label={t("sessions.remove")}
                title={t("sessions.remove")}
                disabled={pending?.includes(pane.id)}
                onClick={() => {
                  removePanes([pane.id]);
                }}
              >
                ×
              </button>
            </div>
            <button
              type="button"
              className="session-title session-open"
              title={`${t("sessions.open_terminal")} · ${pane.title || pane.cwd}`}
              aria-current={pane.id === current ? "true" : undefined}
              onClick={() => {
                onOpenTerminal(pane.id);
              }}
            >
              {pane.title || baseName(pane.cwd)}
            </button>
            <div className="session-meta">
              <span className="muted" title={pane.cwd}>
                {pane.project_id
                  ? (names.get(pane.project_id) ?? pane.project_id)
                  : t("sessions.outside_project")}
              </span>
              {pane.project_id && pane.task && (
                <TaskLink projectId={pane.project_id} task={pane.task} onOpenTask={onOpenTask} />
              )}
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

function TaskLink({ projectId, task, onOpenTask }: { projectId: string; task: TaskRef; onOpenTask: OpenTask }) {
  const { t } = useI18n();
  return (
    <button
      type="button"
      className="task-link"
      title={`${t("sessions.task_title")}: ${task.title}`}
      onClick={() => {
        onOpenTask(projectId, task.id);
      }}
    >
      <span className="mono">{task.id}</span>
      <span className="chip">{task.status}</span>
    </button>
  );
}

function PastSection({ project, onOpenTask }: { project: ProjectItem; onOpenTask: OpenTask }) {
  const { t } = useI18n();
  const past = usePastSessions(project.id);
  const resume = useResumeSession(project.id);
  const remove = useDeleteSessions(project.id);
  const [selecting, setSelecting] = useState(false);
  const [rawSelected, setSelected] = useState<ReadonlySet<string>>(new Set());
  const [confirming, setConfirming] = useState(false);
  const sessions = past.error ? undefined : past.data;
  // Ro'yxat yangilanganda yo'qolgan yoki ochilib qolgan sessiyalar tanlovdan tushadi.
  const selected = pruneSelection(rawSelected, sessions ?? []);
  const deletable = sessions?.filter((session) => !session.active) ?? [];
  const allSelected = deletable.length > 0 && selected.size === deletable.length;
  const pendingKey = resume.isPending ? sessionKey(resume.variables) : null;
  const failedKey = resume.error ? sessionKey(resume.variables) : null;

  function stopSelecting() {
    setSelecting(false);
    setSelected(new Set());
    setConfirming(false);
    remove.reset();
  }

  function deleteSelected() {
    const items = (sessions ?? [])
      .filter((session) => selected.has(sessionKey(session)))
      .map(({ agent, session_id }) => ({ agent, session_id }));
    remove.mutate({ sessions: items }, { onSuccess: stopSelecting });
  }

  const action = sessions && sessions.length > 0 && (
    <button
      type="button"
      className="button button-small section-action"
      title={selecting ? undefined : t("sessions.select_title")}
      onClick={() => {
        if (selecting) stopSelecting();
        else setSelecting(true);
      }}
    >
      {selecting ? t("common.cancel") : t("sessions.select")}
    </button>
  );

  return (
    <Section title={t("sessions.past_project", { project: project.name })} count={sessions?.length} action={action}>
      {selecting && sessions && sessions.length > 0 && (
        <div className="select-bar">
          <label className="select-all">
            <input
              type="checkbox"
              checked={allSelected}
              disabled={deletable.length === 0 || confirming}
              onChange={() => {
                setSelected(allSelected ? new Set() : new Set(deletable.map(sessionKey)));
              }}
            />
            {t("sessions.select_all")}
          </label>
          <span className="muted">{t("sessions.selected", { count: selected.size })}</span>
          <button
            type="button"
            className="button button-small button-danger section-action"
            disabled={selected.size === 0 || confirming}
            onClick={() => {
              setConfirming(true);
            }}
          >
            {t("sessions.delete")}
          </button>
        </div>
      )}
      {selecting && confirming && (
        <div className="confirm" role="alertdialog" aria-label={t("sessions.delete")}>
          <p>{t("sessions.delete_confirm", { count: selected.size })}</p>
          {remove.error && <ErrorText error={remove.error} />}
          <div className="form-actions">
            <button
              type="button"
              className="button button-small"
              disabled={remove.isPending}
              onClick={() => {
                setConfirming(false);
                remove.reset();
              }}
            >
              {t("common.cancel")}
            </button>
            <button
              type="button"
              className="button button-small button-danger"
              disabled={remove.isPending || selected.size === 0}
              onClick={deleteSelected}
            >
              {remove.isPending ? t("sessions.deleting") : t("sessions.delete_yes")}
            </button>
          </div>
        </div>
      )}
      <QueryBody error={past.error} loaded={sessions !== undefined} empty={sessions?.length === 0}>
        <ul className="list">
          {sessions?.map((session) => {
            const key = sessionKey(session);
            const checked = selected.has(key);
            return (
              <li key={key} className={`session${checked ? " session-selected" : ""}`}>
                <div className="session-top">
                  {selecting && (
                    <input
                      type="checkbox"
                      className="session-check"
                      checked={checked}
                      disabled={session.active || confirming}
                      aria-label={pastTitle(session)}
                      title={session.active ? t("sessions.delete_active") : undefined}
                      onChange={() => {
                        setSelected(toggleKey(selected, key));
                      }}
                    />
                  )}
                  <span className="session-agent mono">{session.agent}</span>
                  <Ago timestamp={session.mtime} />
                  {session.turns > 0 && (
                    <span className="muted">{t("sessions.turns", { count: session.turns })}</span>
                  )}
                </div>
                <div className="session-title" title={session.recap ?? session.title ?? session.name}>
                  {pastTitle(session)}
                </div>
                <div className="session-meta">
                  <span className="muted mono" title={session.cwd}>
                    {baseName(session.cwd)}
                  </span>
                  {session.task && <TaskLink projectId={project.id} task={session.task} onOpenTask={onOpenTask} />}
                  {!selecting && (
                    <button
                      type="button"
                      className="button button-small session-resume"
                      disabled={session.active || resume.isPending}
                      title={
                        session.active
                          ? t("sessions.resume_active")
                          : t("sessions.resume_title", { cwd: session.cwd })
                      }
                      onClick={() => {
                        resume.mutate({ agent: session.agent, session_id: session.session_id });
                      }}
                    >
                      {pendingKey === key ? t("sessions.resuming") : t("sessions.resume")}
                    </button>
                  )}
                </div>
                {failedKey === key && resume.error && <ErrorText error={resume.error} />}
              </li>
            );
          })}
        </ul>
      </QueryBody>
    </Section>
  );
}

function pastTitle(session: PastSession): string {
  return session.title || session.name || session.recap || session.session_id;
}
