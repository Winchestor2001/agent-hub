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
  /** Bekloq papkasiga qo'shimcha repo papkalari. */
  repos: string[];
  /** Barcha loyiha papkalari: bekloq papkasi birinchi, keyin `repos`. */
  dirs: string[];
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
  /** Faqat vazifali sessiya ochilganda: vazifa statusi avtomatik o'zgardimi. */
  lifecycle?: TaskLifecycle;
}

export interface TaskLifecycle {
  promoted: boolean;
  status: string;
  /** Sessiya ochilgan, lekin status o'zgarmagan bo'lsa — sababi. */
  error: ApiErrorBody | null;
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
  /** Chiqib ketgan pane'lar (yangisi oldin) — ro'yxatdan olib tashlash mumkin. */
  finished: LivePane[];
  past: PastSession[];
}

export interface ChecklistItem {
  index: number;
  text: string;
  checked: boolean;
}

export interface Milestone {
  id: string;
  title: string;
  done: number;
  total: number;
  completed: boolean;
}

/** `backlog task list --json` elementi + DoD progressi va bog'langan tirik pane'lar. */
export interface TaskItem {
  id: string;
  title: string;
  status: string;
  type: string | null;
  priority: string | null;
  assignees: string[];
  labels: string[];
  milestone: string | null;
  parent_task_id: string | null;
  acceptance_criteria_completed: number;
  acceptance_criteria_count: number;
  ordinal: number | null;
  created_at: string | null;
  updated_at: string | null;
  is_ready: boolean;
  dod_completed: number;
  dod_count: number;
  sessions: LivePane[];
}

export interface Board {
  project: Project;
  task_prefix: string;
  statuses: string[];
  labels: string[];
  milestones: Milestone[];
  tasks: TaskItem[];
  kanbot_available: boolean;
}

export interface TaskDetail extends TaskItem {
  description: string | null;
  dependencies: string[];
  subtasks: { id: string; title: string }[];
  references: string[];
  documentation: string[];
  acceptance_criteria: ChecklistItem[];
  definition_of_done: ChecklistItem[];
  implementation_plan: string | null;
  implementation_notes: string | null;
  final_summary: string | null;
  kanbot_available: boolean;
}

export interface ProjectCreate {
  id: string;
  name: string;
  backlog_dir: string;
  repos: string[];
}

export type ProjectUpdate = Omit<ProjectCreate, "id">;

export interface TaskCreate {
  title: string;
  description?: string;
  status?: string;
  labels: string[];
  assignees: string[];
  milestone?: string;
  acceptance_criteria: string[];
  /** Yuklangan fayllar yo'llari (`UploadedFile.path`); tavsif oxiriga ro'yxat bo'lib qo'shiladi. */
  files?: string[];
}

/** Loyiha papkasiga yuklangan fayl; `path` — o'sha papkaga nisbatan. */
export interface UploadedFile {
  name: string;
  path: string;
  size: number;
  kind: "image" | "video" | "file";
}

export interface UploadsResponse {
  files: UploadedFile[];
}

export interface SessionOptions {
  agents: string[];
  /** `{task_id}` o'rinbosari bor; vazifa tanlansa prompt shu matn bilan boshlanadi. */
  prompt_template: string;
}

export interface SessionStart {
  agent: string;
  cwd?: string;
  task_id?: string;
  prompt: string;
  /** Yuklangan fayllar yo'llari; prompt oxiriga ro'yxat bo'lib qo'shiladi. */
  files?: string[];
}

export type SessionModelGroup = "current" | "legacy" | "alias";

/** Sessiya ichida tanlanadigan Claude modeli (`GET /api/sessions/models`). */
export interface SessionModel {
  id: string;
  label: string;
  group: SessionModelGroup;
}

export interface SessionModelsResponse {
  models: SessionModel[];
}

export interface SessionModelSet {
  ok: boolean;
  model: string;
}

export interface SessionResume {
  agent: string;
  session_id: string;
}

/** O'tgan sessiyalar transkriptlari diskdan butunlay o'chiriladi. */
export interface SessionsDelete {
  sessions: SessionResume[];
}

export interface FolderEntry {
  name: string;
  path: string;
  has_backlog: boolean;
}

export interface FolderListing extends FolderEntry {
  home: string;
  parent: string | null;
  in_git: boolean;
  entries: FolderEntry[];
  truncated: boolean;
}

export interface FolderSuggestions {
  root: string;
  home: string;
  folders: FolderEntry[];
}

export interface BacklogInit {
  path: string;
  name: string;
}

/** Brew orqali bo'lgan oxirgi yangilash urinishi (chiqishi — brew logining oxiri). */
export interface UpdateRun {
  ok: boolean;
  exit_code: number;
  finished_at: number;
  output: string;
}

export interface AgentUpdate {
  agent: string;
  cask: string | null;
  installed_version: string | null;
  /** Brew so'nggi versiyani aytmasa (tarmoq yo'q) — null. */
  latest_version: string | null;
  outdated: boolean;
  running: boolean;
  last: UpdateRun | null;
}

export interface UpdatesResponse {
  /** brew topilmasa yangilash tugmalari o'chirilgan bo'ladi. */
  brew: boolean;
  agents: AgentUpdate[];
}

export interface LimitWindow {
  used_percent: number;
  /** epoch soniya; noma'lum bo'lsa `null`. */
  resets_at: number | null;
}

/** Bitta agentning joriy rate-limit holati (`services/limits.py`). */
export interface AgentLimits {
  agent: string;
  /** `false` — ma'lumot yo'q (kesh/sessiya topilmadi), boshqa maydonlar shu holda ahamiyatsiz. */
  available: boolean;
  five_hour: LimitWindow | null;
  weekly: LimitWindow | null;
  /** epoch soniya — ma'lumot qachon olingan. */
  updated_at: number | null;
  /** Foiz eskirgan (agent uzoq vaqt faol bo'lmagan) — baribir ko'rsatiladi, faqat belgilanadi. */
  stale: boolean;
}

export interface LimitsResponse {
  claude: AgentLimits;
  codex: AgentLimits;
}

// --- Claude konfiguratsiyasi (`services/claude_config.py`) ---

export type ConfigScopeKind = "global" | "project";

export interface ConfigScope {
  /** "global", "project:<id>" yoki "project:<id>:<n>" (loyihaning qo'shimcha papkasi). */
  id: string;
  kind: ConfigScopeKind;
  root: string;
  label: string;
  project_id: string | null;
  exists: boolean;
}

export interface ConfigKind {
  id: string;
  format: "markdown" | "frontmatter" | "json" | "script";
  /** `true` — ko'p elementli papka (skills, agents...), aks holda belgilangan fayl(lar). */
  collection: boolean;
  layout: "file" | "skill";
  extensions: string[];
  scopes: ConfigScopeKind[];
  fixed: Partial<Record<ConfigScopeKind, string[]>>;
  required: string[];
  /** Bir xil nom ikki qamrovda bo'lsa qaysi biri ustun. */
  winner: ConfigScopeKind | null;
}

export interface ConfigScopesResponse {
  scopes: ConfigScope[];
  kinds: ConfigKind[];
}

export interface ConfigShadow {
  scope: string;
  winner: "this" | "other";
}

export interface ConfigItem {
  name: string;
  path: string;
  exists: boolean;
  size: number | null;
  mtime: number | null;
  symlink: boolean;
  shadow: ConfigShadow[];
}

export interface ConfigItemsResponse {
  items: ConfigItem[];
  /** Nomi qoidaga mos kelmagani uchun ko'rsatilmagan elementlar. */
  skipped: string[];
}

export type ConfigWarning = "local_not_ignored";

export interface ConfigFile {
  scope: string;
  kind: string;
  name: string;
  path: string;
  abs_path: string;
  exists: boolean;
  content: string | null;
  etag: string | null;
  mode: string | null;
  warnings: ConfigWarning[];
}

export interface ConfigWrite {
  scope: string;
  kind: string;
  name: string;
  content: string;
  /** `null` — yangi fayl. */
  etag: string | null;
}

export interface ConfigWriteResult {
  scope: string;
  kind: string;
  name: string;
  path: string;
  etag: string;
  created: boolean;
  backup: string | null;
}

export interface ConfigDelete {
  scope: string;
  kind: string;
  name: string;
  etag: string;
}

export interface ConfigApply {
  kind: string;
  name: string;
  content: string;
  scopes: string[];
  overwrite: boolean;
}

export interface ConfigApplyResult {
  scope: string;
  ok: boolean;
  status: "created" | "updated" | "unchanged" | "error";
  error: ApiErrorBody | null;
}

export interface ConfigTemplate {
  id: string;
  kind: string;
  name: string;
}

export interface ConfigTemplateRendered extends ConfigTemplate {
  content: string;
}

export interface ConfigGuide {
  id: string;
  title: string;
  kinds: string[];
}

export interface ConfigGuideContent extends ConfigGuide {
  content: string;
}
