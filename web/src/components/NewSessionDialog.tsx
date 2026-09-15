import { useState, type SubmitEvent } from "react";

import { useBoard, useHealth, useSessionOptions, useStartSession } from "../api/queries";
import type { ProjectItem, SessionStart } from "../api/types";
import { useI18n } from "../i18n/context";
import { agentChoices, promptPrefix, sessionTasks } from "../sessions/model";
import { ErrorText } from "./ErrorText";
import { Field, Modal } from "./Modal";

interface NewSessionDialogProps {
  project: ProjectItem;
  /** Vazifa detalidan ochilganda oldindan tanlanadi. */
  initialTaskId: string | null;
  onClose: () => void;
}

export function NewSessionDialog({ project, initialTaskId, onClose }: NewSessionDialogProps) {
  const { t } = useI18n();
  const health = useHealth();
  const options = useSessionOptions();
  // Bekloqi o'qilmagan loyihada vazifasiz sessiya ham ochsa bo'ladi.
  const board = useBoard(project.id, project.error === null);
  const startSession = useStartSession(project.id);

  const choices = agentChoices(options.data?.agents ?? [], health.data?.kanbot.agents);
  const dirs = project.repos.length > 0 ? project.repos : [project.backlog_dir];
  const tasks = board.data ? sessionTasks(board.data.tasks, board.data.statuses, initialTaskId) : [];

  const [agent, setAgent] = useState<string | null>(null);
  const [cwd, setCwd] = useState(dirs[0] ?? "");
  const [taskId, setTaskId] = useState(initialTaskId ?? "");
  const [prompt, setPrompt] = useState("");

  // Tanlanmagan bo'lsa — birinchi onlayn agent (options kelguncha bo'sh).
  const selectedAgent = agent ?? (choices.find((c) => c.online !== false) ?? choices[0])?.agent ?? "";
  const kanbotDown = health.data?.kanbot.reachable === false;
  const template = options.data?.prompt_template;

  function submit(event: SubmitEvent) {
    event.preventDefault();
    const body: SessionStart = { agent: selectedAgent, cwd, prompt: prompt.trim() };
    if (taskId) body.task_id = taskId;
    startSession.mutate(body, { onSuccess: onClose });
  }

  return (
    <Modal title={t("session_form.title", { project: project.name })} onClose={onClose}>
      <form className="form" onSubmit={submit}>
        <div className="form-row">
          <Field label={t("session_form.agent")}>
            <select
              value={selectedAgent}
              required
              onChange={(e) => {
                setAgent(e.target.value);
              }}
            >
              {choices.map(({ agent: name, online }) => (
                <option key={name} value={name}>
                  {online === false ? t("session_form.agent_offline", { agent: name }) : name}
                </option>
              ))}
            </select>
          </Field>
          <Field label={t("session_form.repo")}>
            <select
              className="mono"
              value={cwd}
              onChange={(e) => {
                setCwd(e.target.value);
              }}
            >
              {dirs.map((dir) => (
                <option key={dir} value={dir}>
                  {dir}
                </option>
              ))}
            </select>
          </Field>
        </div>
        <Field label={t("session_form.task")} hint={t("session_form.task_hint")}>
          <select
            value={taskId}
            onChange={(e) => {
              setTaskId(e.target.value);
            }}
          >
            <option value="">{t("session_form.no_task")}</option>
            {tasks.map((task) => (
              <option key={task.id} value={task.id}>
                {task.id} · {task.title} ({task.status})
              </option>
            ))}
          </select>
        </Field>
        {taskId && template && (
          <div className="field">
            <span className="field-label">{t("session_form.prefix")}</span>
            <pre className="prompt-prefix">{promptPrefix(template, taskId)}</pre>
          </div>
        )}
        <Field
          label={t("session_form.prompt")}
          hint={taskId ? t("session_form.prompt_hint_task") : t("session_form.prompt_hint")}
        >
          <textarea
            rows={5}
            value={prompt}
            maxLength={20000}
            onChange={(e) => {
              setPrompt(e.target.value);
            }}
          />
        </Field>
        {kanbotDown && <p className="error-text">{t("session_form.kanbot_down")}</p>}
        {startSession.error && <ErrorText error={startSession.error} />}
        <footer className="form-actions">
          <button type="button" className="button" onClick={onClose}>
            {t("common.cancel")}
          </button>
          <button
            type="submit"
            className="button button-primary"
            disabled={startSession.isPending || !selectedAgent || !cwd}
          >
            {startSession.isPending ? t("session_form.starting") : t("session_form.start")}
          </button>
        </footer>
      </form>
    </Modal>
  );
}
