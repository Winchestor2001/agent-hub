import { useCallback, useMemo, useState } from "react";

import { collectBanners } from "./api/banners";
import { useLiveEvents } from "./api/events";
import { useHealth, useLiveSessions, useProjects } from "./api/queries";
import { Banners } from "./components/Banners";
import { BoardPanel } from "./components/BoardPanel";
import { ConfigView } from "./components/ConfigView";
import { NewSessionDialog } from "./components/NewSessionDialog";
import { ProjectsPanel } from "./components/ProjectsPanel";
import { SessionsPanel } from "./components/SessionsPanel";
import { TerminalView } from "./components/TerminalView";
import { TopBar } from "./components/TopBar";
import { useBlockedAlerts } from "./sessions/alerts";
import { splitByProject } from "./sessions/model";
import { useSessionShortcuts } from "./sessions/navigation";

interface TaskTarget {
  projectId: string;
  taskId: string;
}

export function App() {
  useLiveEvents();
  const health = useHealth();
  const projects = useProjects();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  // Sessiyalar panelidan ham ochiladi, shuning uchun doskadan yuqorida saqlanadi.
  const [openTask, setOpenTask] = useState<TaskTarget | null>(null);
  const [newSession, setNewSession] = useState<{ projectId: string; taskId: string | null } | null>(null);
  // Terminal markaziy panel o'rnida; doska yashiriladi (filtr va detal saqlanadi).
  const [terminalPaneId, setTerminalPaneId] = useState<string | null>(null);
  // Sessiyalar paneli odatda faqat tanlangan loyiha sessiyalarini ko'rsatadi.
  const [showAllSessions, setShowAllSessions] = useState(false);
  // Claude konfiguratsiyasi ochiq bo'lsa asosiy panellar o'rnida ko'rinadi (boshlang'ich qamrov bilan).
  const [configScope, setConfigScope] = useState<string | null>(null);
  const live = useLiveSessions();
  // Xatoda eski ro'yxat hisobga olinmaydi (panel ham uni ko'rsatmaydi).
  const livePanes = live.error ? undefined : live.data?.live;

  const items = projects.data?.projects;
  const selected = items?.find((p) => p.id === selectedId) ?? items?.[0] ?? null;
  const selectedProjectId = selected?.id ?? null;
  const sessionProject = newSession && items?.find((p) => p.id === newSession.projectId);
  const terminalPane = terminalPaneId
    ? [...(live.data?.live ?? []), ...(live.data?.finished ?? [])].find((pane) => pane.id === terminalPaneId)
    : undefined;

  // Shortcut panelda ko'rinayotgan sessiyalar orasida, panel tartibida (backend tartibi) o'tadi.
  const paneOrder = useMemo(() => {
    const panes = livePanes ?? [];
    return (showAllSessions ? panes : splitByProject(panes, selectedProjectId).mine).map((pane) => pane.id);
  }, [livePanes, showAllSessions, selectedProjectId]);
  useSessionShortcuts(paneOrder, terminalPaneId, setTerminalPaneId);

  // Bildirishnoma barcha loyihalar uchun; bosilganda sessiya loyihasi tanlanadi.
  const openAlertedPane = useCallback(
    (paneId: string) => {
      const projectId = livePanes?.find((pane) => pane.id === paneId)?.project_id;
      if (projectId && projectId !== selectedProjectId) {
        setSelectedId(projectId);
        setOpenTask(null);
      }
      setTerminalPaneId(paneId);
    },
    [livePanes, selectedProjectId],
  );
  useBlockedAlerts(livePanes, openAlertedPane);
  function selectProject(projectId: string) {
    setSelectedId(projectId);
    setOpenTask(null);
    setTerminalPaneId(null);
  }

  const banners = useMemo(
    () =>
      collectBanners({
        health: health.data,
        healthError: health.error,
        projects: projects.data,
        projectsError: projects.error,
      }),
    [health.data, health.error, projects.data, projects.error],
  );

  return (
    <div className="app">
      <TopBar
        health={health.data}
        error={health.error}
        onOpenConfig={() => {
          setConfigScope("global");
        }}
      />
      <Banners banners={banners} />
      {configScope !== null && (
        <ConfigView
          initialScope={configScope}
          onClose={() => {
            setConfigScope(null);
          }}
        />
      )}
      <main className="panels" hidden={configScope !== null}>
        <ProjectsPanel
          projects={items}
          error={projects.error}
          selectedId={selected?.id ?? null}
          onSelect={selectProject}
          onOpenConfig={(projectId) => {
            setConfigScope(`project:${projectId}`);
          }}
        />
        {terminalPaneId && (
          <TerminalView
            key={terminalPaneId}
            paneId={terminalPaneId}
            pane={terminalPane}
            project={items?.find((p) => p.id === terminalPane?.project_id)}
            onBack={() => {
              setTerminalPaneId(null);
            }}
          />
        )}
        <BoardPanel
          project={selected}
          hidden={terminalPaneId !== null}
          onOpenTerminal={setTerminalPaneId}
          openTaskId={openTask && openTask.projectId === selected?.id ? openTask.taskId : null}
          onOpenTask={(taskId) => {
            setOpenTask(selected && taskId ? { projectId: selected.id, taskId } : null);
          }}
          onStartSession={(taskId) => {
            if (selected) setNewSession({ projectId: selected.id, taskId });
          }}
        />
        <SessionsPanel
          project={selected}
          projects={items}
          onOpenTask={(projectId, taskId) => {
            setSelectedId(projectId);
            setOpenTask({ projectId, taskId });
            setTerminalPaneId(null);
          }}
          showAll={showAllSessions}
          onToggleShowAll={() => {
            setShowAllSessions((value) => !value);
          }}
          terminalPaneId={terminalPaneId}
          onOpenTerminal={setTerminalPaneId}
          onSessionsRemoved={(paneIds) => {
            setTerminalPaneId((current) => (current && paneIds.includes(current) ? null : current));
          }}
          onNewSession={() => {
            if (selected) setNewSession({ projectId: selected.id, taskId: null });
          }}
        />
      </main>
      {newSession && sessionProject && (
        <NewSessionDialog
          project={sessionProject}
          initialTaskId={newSession.taskId}
          onClose={() => {
            setNewSession(null);
          }}
        />
      )}
    </div>
  );
}
