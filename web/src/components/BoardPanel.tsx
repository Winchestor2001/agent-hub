import type { ProjectItem } from "../api/types";
import { useI18n } from "../i18n/context";
import { ErrorText } from "./ErrorText";
import { Panel } from "./Panel";

export function BoardPanel({ project }: { project: ProjectItem | null }) {
  const { t } = useI18n();

  if (!project) {
    return (
      <Panel title={t("panel.board")} className="panel-board">
        <p className="muted placeholder">{t("board.select_project")}</p>
      </Panel>
    );
  }

  return (
    <Panel
      title={`${t("panel.board")} · ${project.name}`}
      aside={<span className="muted mono">{project.backlog_dir}</span>}
      className="panel-board"
    >
      {project.error ? (
        <ErrorText error={project.error} />
      ) : (
        <p className="muted placeholder">{t("board.placeholder")}</p>
      )}
    </Panel>
  );
}
