import { useMemo, useState } from "react";

import { collectBanners } from "./api/banners";
import { useHealth, useLiveSessions, useProjects } from "./api/queries";
import { Banners } from "./components/Banners";
import { BoardPanel } from "./components/BoardPanel";
import { NewSessionDialog } from "./components/NewSessionDialog";
import { ProjectsPanel } from "./components/ProjectsPanel";
import { SessionsPanel } from "./components/SessionsPanel";
import { TerminalView } from "./components/TerminalView";
import { TopBar } from "./components/TopBar";

interface TaskTarget {
  projectId: string;
  taskId: string;
}

export function App() {
  const health = useHealth();
  const projects = useProjects();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  // Sessiyalar panelidan ham ochiladi, shuning uchun doskadan yuqorida saqlanadi.
  const [openTask, setOpenTask] = useState<TaskTarget | null>(null);
  const [newSession, setNewSession] = useState<{ projectId: string; taskId: string | null } | null>(null);
  // Terminal markaziy panel o'rnida; doska yashiriladi (filtr va detal saqlanadi).
  const [terminalPaneId, setTerminalPaneId] = useState<string | null>(null);
  const live = useLiveSessions();

  const items = projects.data?.projects;
  const selected = items?.find((p) => p.id === selectedId) ?? items?.[0] ?? null;
  const sessionProject = newSession && items?.find((p) => p.id === newSession.projectId);

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
      <TopBar health={health.data} error={health.error} />
      <Banners banners={banners} />
      <main className="panels">
        <ProjectsPanel
          projects={items}
          error={projects.error}
          selectedId={selected?.id ?? null}
          onSelect={selectProject}
        />
        {terminalPaneId && (
          <TerminalView
            key={terminalPaneId}
            paneId={terminalPaneId}
            pane={live.data?.find((pane) => pane.id === terminalPaneId)}
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
          terminalPaneId={terminalPaneId}
          onOpenTerminal={setTerminalPaneId}
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
