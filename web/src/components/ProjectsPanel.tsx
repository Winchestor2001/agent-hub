import { useState } from "react";

import type { ApiError } from "../api/client";
import { useRemoveProject } from "../api/queries";
import type { ProjectItem, ProjectSummary } from "../api/types";
import { statusTone } from "../board/model";
import { useI18n } from "../i18n/context";
import { AddProjectDialog } from "./AddProjectDialog";
import { ErrorText } from "./ErrorText";
import { Panel } from "./Panel";

interface ProjectsPanelProps {
  projects: ProjectItem[] | undefined;
  error: ApiError | null;
  selectedId: string | null;
  onSelect: (id: string) => void;
  onOpenConfig: (id: string) => void;
}

export function ProjectsPanel({ projects, error, selectedId, onSelect, onOpenConfig }: ProjectsPanelProps) {
  const { t } = useI18n();
  const [adding, setAdding] = useState(false);

  let body;
  if (!projects) {
    body = error ? <ErrorText error={error} /> : <p className="muted">{t("projects.loading")}</p>;
  } else if (projects.length === 0) {
    body = <p className="muted">{t("projects.empty")}</p>;
  } else {
    body = (
      <ul className="list">
        {projects.map((project) => (
          <ProjectRow
            key={project.id}
            project={project}
            selected={project.id === selectedId}
            onSelect={onSelect}
            onOpenConfig={onOpenConfig}
          />
        ))}
      </ul>
    );
  }

  return (
    <Panel
      title={t("panel.projects")}
      className="panel-projects"
      aside={
        <button
          type="button"
          className="button button-small"
          onClick={() => {
            setAdding(true);
          }}
        >
          {t("projects.add")}
        </button>
      }
    >
      {body}
      {adding && (
        <AddProjectDialog
          onClose={() => {
            setAdding(false);
          }}
          onSaved={onSelect}
        />
      )}
    </Panel>
  );
}

interface ProjectRowProps {
  project: ProjectItem;
  selected: boolean;
  onSelect: (id: string) => void;
  onOpenConfig: (id: string) => void;
}

function ProjectRow({ project, selected, onSelect, onOpenConfig }: ProjectRowProps) {
  const { t } = useI18n();
  const remove = useRemoveProject();
  const [confirming, setConfirming] = useState(false);
  const [editing, setEditing] = useState(false);

  return (
    <li className="project-row">
      <button
        type="button"
        className="list-item"
        aria-current={selected}
        onClick={() => {
          onSelect(project.id);
        }}
      >
        <span className="list-item-title">{project.name}</span>
        {project.summary ? (
          <Counters summary={project.summary} />
        ) : (
          <span className="error-text">{t("projects.backlog_error")}</span>
        )}
      </button>
      <button
        type="button"
        className="icon-button project-remove"
        title={t("projects.remove")}
        aria-label={`${t("projects.remove")}: ${project.name}`}
        onClick={() => {
          setConfirming(true);
        }}
      >
        ×
      </button>
      <button
        type="button"
        className="icon-button project-edit"
        title={t("projects.edit")}
        aria-label={`${t("projects.edit")}: ${project.name}`}
        onClick={() => {
          setEditing(true);
        }}
      >
        ✎
      </button>
      <button
        type="button"
        className="icon-button project-config"
        title={t("config.open_project", { name: project.name })}
        aria-label={t("config.open_project", { name: project.name })}
        onClick={() => {
          onOpenConfig(project.id);
        }}
      >
        ⚙
      </button>
      {editing && (
        <AddProjectDialog
          project={project}
          onClose={() => {
            setEditing(false);
          }}
          onSaved={onSelect}
        />
      )}
      {confirming && (
        <div className="confirm" role="alertdialog" aria-label={t("projects.remove")}>
          <p>{t("projects.remove_confirm", { name: project.name })}</p>
          {remove.error && <ErrorText error={remove.error} />}
          <div className="form-actions">
            <button
              type="button"
              className="button button-small"
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
              disabled={remove.isPending}
              onClick={() => {
                remove.mutate(project.id);
              }}
            >
              {t("projects.remove_yes")}
            </button>
          </div>
        </div>
      )}
    </li>
  );
}

function Counters({ summary }: { summary: ProjectSummary }) {
  const { t } = useI18n();
  const blocked = summary.blocked_sessions ?? 0;

  return (
    <span className="counters">
      <span className="counter-row">
        {summary.status_counts.map(({ status, count }, index) => (
          <span key={status} className={`counter ${statusTone(index, summary.status_counts.length)}`} title={status}>
            <span className="counter-label">{status}</span> {count}
          </span>
        ))}
      </span>
      <span className="counter-row">
        {summary.bugs > 0 && (
          <span
            className={summary.open_bugs > 0 ? "counter counter-bug" : "counter"}
            title={t("projects.bugs_title")}
          >
            {t("projects.bugs", { open: summary.open_bugs, total: summary.bugs })}
          </span>
        )}
        {summary.active_sessions === null ? (
          <span className="counter muted" title={t("projects.sessions_unknown_title")}>
            {t("projects.sessions_unknown")}
          </span>
        ) : (
          <>
            <span className="counter">{t("projects.sessions_active", { count: summary.active_sessions })}</span>
            {blocked > 0 && (
              <span className="counter counter-blocked">
                {t("projects.sessions_blocked", { count: blocked })}
              </span>
            )}
          </>
        )}
      </span>
    </span>
  );
}
