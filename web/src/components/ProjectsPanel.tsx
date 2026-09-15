import type { ApiError } from "../api/client";
import type { ProjectItem } from "../api/types";
import { useI18n } from "../i18n/context";
import { ErrorText } from "./ErrorText";
import { Panel } from "./Panel";

interface ProjectsPanelProps {
  projects: ProjectItem[] | undefined;
  error: ApiError | null;
  selectedId: string | null;
  onSelect: (id: string) => void;
}

export function ProjectsPanel({ projects, error, selectedId, onSelect }: ProjectsPanelProps) {
  const { t } = useI18n();

  let body;
  if (!projects) {
    body = error ? <ErrorText error={error} /> : <p className="muted">{t("projects.loading")}</p>;
  } else if (projects.length === 0) {
    body = <p className="muted">{t("projects.empty")}</p>;
  } else {
    body = (
      <ul className="list">
        {projects.map((project) => (
          <li key={project.id}>
            <button
              type="button"
              className="list-item"
              aria-current={project.id === selectedId}
              onClick={() => {
                onSelect(project.id);
              }}
            >
              <span className="list-item-title">{project.name}</span>
              {project.summary ? (
                <span className="muted">{t("projects.tasks", { count: project.summary.total })}</span>
              ) : (
                <span className="error-text">{t("projects.backlog_error")}</span>
              )}
            </button>
          </li>
        ))}
      </ul>
    );
  }

  return (
    <Panel title={t("panel.projects")} className="panel-projects">
      {body}
    </Panel>
  );
}
