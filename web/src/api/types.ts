/** Backend javoblari (`src/agent_hub/api/`) — JSON snake_case. */

export interface ApiErrorBody {
  code: string;
  params: Record<string, unknown>;
  detail: string | null;
}

export type Severity = "error" | "warning";

export interface Problem {
  code: string;
  severity: Severity;
  params: Record<string, unknown>;
}

export interface Health {
  ok: boolean;
  version: string;
  kanbot: {
    url: string;
    reachable: boolean;
    version?: string;
    runners_online?: number;
    agents?: string[];
  };
  problems: Problem[];
}

export interface Project {
  id: string;
  name: string;
  backlog_dir: string;
  repos: string[];
}

export interface ProjectSummary {
  status_counts: { status: string; count: number }[];
  total: number;
  bugs: number;
  open_bugs: number;
  /** KanBot ishlamasa `null` (noma'lum). */
  active_sessions: number | null;
  blocked_sessions: number | null;
  blocked_pane_ids: string[];
}

export interface ProjectItem extends Project {
  summary: ProjectSummary | null;
  error: ApiErrorBody | null;
}

export interface ProjectsResponse {
  projects: ProjectItem[];
  kanbot_available: boolean;
}

export interface TaskRef {
  id: string;
  title: string;
  status: string;
}

export interface LivePane {
  id: string;
  agent: string;
  title: string;
  cwd: string;
  /** effective_state: blocked | working | idle | unknown | done (KanBot boshqasini ham qaytarishi mumkin). */
  state: string;
  raw_state: string;
  approximate: boolean;
  alive: boolean;
  session_id: string;
  runner_id: string;
  runner_name: string;
  started_at: number | null;
  last_output_at: number | null;
  ended_at: number | null;
  exit_code: number | null;
  project_id: string | null;
  task: TaskRef | null;
}

export interface PastSession {
  agent: string;
  session_id: string;
  cwd: string;
  name: string;
  title: string | null;
  recap: string | null;
  turns: number;
  started_at: number | null;
  mtime: number;
  active: boolean;
  runner_id: string;
  project_id: string | null;
  task: TaskRef | null;
}

export interface SessionsResponse {
  live: LivePane[];
  past: PastSession[];
}
