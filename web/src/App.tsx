import { useMemo, useState } from "react";

import { collectBanners } from "./api/banners";
import { useHealth, useProjects } from "./api/queries";
import { Banners } from "./components/Banners";
import { BoardPanel } from "./components/BoardPanel";
import { ProjectsPanel } from "./components/ProjectsPanel";
import { SessionsPanel } from "./components/SessionsPanel";
import { TopBar } from "./components/TopBar";

export function App() {
  const health = useHealth();
  const projects = useProjects();
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const items = projects.data?.projects;
  const selected = items?.find((p) => p.id === selectedId) ?? items?.[0] ?? null;

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
          onSelect={setSelectedId}
        />
        <BoardPanel project={selected} />
        <SessionsPanel />
      </main>
    </div>
  );
}
