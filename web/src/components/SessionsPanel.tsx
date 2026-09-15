import type { ReactNode } from "react";

import type { ApiError } from "../api/client";
import { useLiveSessions, usePastSessions, useResumeSession } from "../api/queries";
import type { LivePane, PastSession, ProjectItem, TaskRef } from "../api/types";
import { useI18n } from "../i18n/context";
import { baseName, groupLive, paneActivity } from "../sessions/model";
import { ErrorText } from "./ErrorText";
import { Panel } from "./Panel";
import { Ago, StateBadge } from "./SessionBits";

export type OpenTask = (projectId: string, taskId: string) => void;

interface SessionsPanelProps {
  project: ProjectItem | null;
  projects: readonly ProjectItem[] | undefined;
  onOpenTask: OpenTask;
  onNewSession: () => void;
  /** Markazda ochiq terminal (ro'yxatda belgilanadi). */
  terminalPaneId: string | null;
  onOpenTerminal: (paneId: string) => void;
}

export function SessionsPanel({
  project,
  projects,
  onOpenTask,
  onNewSession,
  terminalPaneId,
  onOpenTerminal,
}: SessionsPanelProps) {
  const { t } = useI18n();
  const live = useLiveSessions();
  const names = new Map(projects?.map((p) => [p.id, p.name]));
  // Xatoda eski ro'yxat ko'rsatilmaydi: KanBot o'chsa "javob kutmoqda" ham yo'qoladi.
  const groups = live.data && !live.error ? groupLive(live.data) : null;

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
      {groups && groups.blocked.length > 0 && (
        <Section title={t("sessions.blocked")} count={groups.blocked.length} className="section-blocked">
          <LiveList panes={groups.blocked} names={names} current={terminalPaneId} onOpenTask={onOpenTask} onOpenTerminal={onOpenTerminal} />
        </Section>
      )}
      <Section title={t("sessions.live")} count={groups?.others.length}>
        <QueryBody error={live.error} loaded={groups !== null} empty={groups?.others.length === 0}>
          {groups && <LiveList panes={groups.others} names={names} current={terminalPaneId} onOpenTask={onOpenTask} onOpenTerminal={onOpenTerminal} />}
        </QueryBody>
      </Section>
      {project ? (
        <PastSection key={project.id} project={project} onOpenTask={onOpenTask} />
      ) : (
        <Section title={t("sessions.past")}>
          <p className="muted">{t("sessions.no_project")}</p>
        </Section>
      )}
    </Panel>
  );
}

function Section({
  title,
  count,
  className,
  children,
}: {
  title: string;
  count?: number | undefined;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div className={className ? `section ${className}` : "section"}>
      <h3 className="section-title">
        {title}
        {count !== undefined && <span className="count">{count}</span>}
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
  return (
    <ul className="list">
      {panes.map((pane) => (
        <li key={pane.id} className={`session session-${pane.state}${pane.id === current ? " session-current" : ""}`}>
          <div className="session-top">
            <StateBadge state={pane.state} approximate={pane.approximate} />
            <span className="session-agent mono">{pane.agent}</span>
            <Ago timestamp={paneActivity(pane)} />
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
  const sessions = past.error ? undefined : past.data;
  const pendingKey = resume.isPending ? sessionKey(resume.variables) : null;
  const failedKey = resume.error ? sessionKey(resume.variables) : null;

  return (
    <Section title={t("sessions.past_project", { project: project.name })} count={sessions?.length}>
      <QueryBody error={past.error} loaded={sessions !== undefined} empty={sessions?.length === 0}>
        <ul className="list">
          {sessions?.map((session) => {
            const key = sessionKey(session);
            return (
              <li key={key} className="session">
                <div className="session-top">
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

function sessionKey(session: { agent: string; session_id: string }): string {
  return `${session.agent}:${session.session_id}`;
}

function pastTitle(session: PastSession): string {
  return session.title || session.name || session.recap || session.session_id;
}
