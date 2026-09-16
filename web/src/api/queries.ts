import { keepPreviousData, QueryClient, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { ApiError, apiFetch } from "./client";
import { anyRunning } from "../updates/model";
import type {
  AgentUpdate,
  BacklogInit,
  Board,
  FolderListing,
  FolderSuggestions,
  Health,
  Project,
  ProjectCreate,
  ProjectsResponse,
  ProjectUpdate,
  LivePane,
  SessionOptions,
  SessionResume,
  SessionsDelete,
  SessionStart,
  SessionsResponse,
  TaskCreate,
  TaskDetail,
  UpdatesResponse,
  UploadsResponse,
} from "./types";

/** Jonli holatlar (health, loyihalar, pane'lar). */
export const POLL_MS = 2500;
/** O'tgan sessiyalar — KanBot ularni ~6 s da yangilaydi. */
export const PAST_POLL_MS = 6000;
export const PAST_LIMIT = 50;
/** Yangilash ketayotganda holat tez, aks holda kamdan-kam so'raladi (brew chaqiruvi arzon emas). */
export const UPDATES_POLL_MS = 2000;
export const UPDATES_IDLE_MS = 60_000;

export const queryKeys = {
  health: ["health"],
  projects: ["projects"],
  liveSessions: ["sessions", "live"],
  pastSessions: (projectId: string) => ["sessions", "past", projectId] as const,
  sessionOptions: ["sessions", "options"],
  board: (projectId: string) => ["board", projectId] as const,
  tasks: (projectId: string) => ["task", projectId] as const,
  task: (projectId: string, taskId: string) => ["task", projectId, taskId] as const,
  folders: ["folders"],
  folderSuggestions: ["folders", "suggestions"],
  folder: (path: string) => ["folders", "browse", path] as const,
  updates: ["updates"],
};

const enc = encodeURIComponent;

declare module "@tanstack/react-query" {
  interface Register {
    defaultError: ApiError;
  }
}

export function createQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: {
        // Polling o'zi qayta urinadi; xato darhol banner bo'lib ko'rinsin.
        retry: false,
        // Yashirin tabda polling to'xtaydi, qaytganda darhol yangilanadi.
        refetchIntervalInBackground: false,
        refetchOnWindowFocus: true,
      },
    },
  });
}

export function useHealth() {
  return useQuery({
    queryKey: queryKeys.health,
    queryFn: ({ signal }) => apiFetch<Health>("/api/health", { signal }),
    refetchInterval: POLL_MS,
  });
}

export function useProjects() {
  return useQuery({
    queryKey: queryKeys.projects,
    queryFn: ({ signal }) => apiFetch<ProjectsResponse>("/api/projects", { signal }),
    refetchInterval: POLL_MS,
  });
}

export function useLiveSessions() {
  return useQuery({
    queryKey: queryKeys.liveSessions,
    queryFn: ({ signal }) => apiFetch<SessionsResponse>("/api/sessions?past_limit=0", { signal }),
    select: ({ live, finished }) => ({ live, finished }),
    refetchInterval: POLL_MS,
    // Blocked bildirishnomasi boshqa tabda turganda kerak: SSE uzilsa ham polling to'xtamasin.
    refetchIntervalInBackground: true,
  });
}

/** Tanlangan loyihaning o'tgan sessiyalari (davom ettirish loyiha nomidan bo'ladi). */
export function usePastSessions(projectId: string) {
  return useQuery({
    queryKey: queryKeys.pastSessions(projectId),
    queryFn: ({ signal }) =>
      apiFetch<SessionsResponse>(
        `/api/sessions?project=${enc(projectId)}&past_limit=${String(PAST_LIMIT)}`,
        { signal },
      ),
    select: (data) => data.past,
    refetchInterval: PAST_POLL_MS,
  });
}

export function useSessionOptions() {
  return useQuery({
    queryKey: queryKeys.sessionOptions,
    queryFn: ({ signal }) => apiFetch<SessionOptions>("/api/sessions/options", { signal }),
    staleTime: Infinity,
  });
}

/** Loyiha bekloqi o'qilmasa (`enabled: false`) doska so'ralmaydi. */
export function useBoard(projectId: string, enabled = true) {
  return useQuery({
    queryKey: queryKeys.board(projectId),
    queryFn: ({ signal }) => apiFetch<Board>(`/api/projects/${enc(projectId)}/board`, { signal }),
    refetchInterval: POLL_MS,
    enabled,
  });
}

export function useTaskDetail(projectId: string, taskId: string) {
  return useQuery({
    queryKey: queryKeys.task(projectId, taskId),
    queryFn: ({ signal }) =>
      apiFetch<TaskDetail>(`/api/projects/${enc(projectId)}/tasks/${enc(taskId)}`, { signal }),
    refetchInterval: POLL_MS,
  });
}

/** Bekloq o'zgargach: loyiha hisoblagichlari, doska va ochiq detal yangilanadi. */
function useInvalidateProject() {
  const client = useQueryClient();
  return (projectId: string) =>
    Promise.all([
      client.invalidateQueries({ queryKey: queryKeys.projects }),
      client.invalidateQueries({ queryKey: queryKeys.board(projectId) }),
      client.invalidateQueries({ queryKey: queryKeys.tasks(projectId) }),
    ]);
}

export function useCreateTask(projectId: string) {
  const invalidate = useInvalidateProject();
  return useMutation({
    mutationFn: (body: TaskCreate) =>
      apiFetch<{ id: string }>(`/api/projects/${enc(projectId)}/tasks`, { method: "POST", body }),
    onSuccess: () => invalidate(projectId),
  });
}

/** Fayllarni loyiha papkasiga yuklaydi; javobdagi `path` lar keyin vazifa/sessiyaga uzatiladi. */
export function useUploadFiles(projectId: string) {
  return useMutation({
    mutationFn: ({ files, cwd, taskId }: { files: File[]; cwd?: string | undefined; taskId?: string | undefined }) => {
      const form = new FormData();
      for (const file of files) form.append("files", file, file.name);
      if (cwd) form.append("cwd", cwd);
      if (taskId) form.append("task_id", taskId);
      return apiFetch<UploadsResponse>(`/api/projects/${enc(projectId)}/uploads`, {
        method: "POST",
        form,
      });
    },
  });
}

/** Agent CLI'lari versiyalari; yangilash ketayotganda polling tezlashadi. */
export function useUpdates() {
  return useQuery({
    queryKey: queryKeys.updates,
    queryFn: ({ signal }) => apiFetch<UpdatesResponse>("/api/updates", { signal }),
    refetchInterval: ({ state }) =>
      state.data && anyRunning(state.data.agents) ? UPDATES_POLL_MS : UPDATES_IDLE_MS,
  });
}

/** Yangilashni fonda boshlaydi; natija polling orqali keladi. */
export function useStartUpdate() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (agent: string) =>
      apiFetch<AgentUpdate>(`/api/updates/${enc(agent)}`, { method: "POST" }),
    onSettled: () => client.invalidateQueries({ queryKey: queryKeys.updates }),
  });
}

export function useSetStatus(projectId: string) {
  const invalidate = useInvalidateProject();
  return useMutation({
    mutationFn: ({ taskId, status }: { taskId: string; status: string }) =>
      apiFetch<{ id: string; status: string }>(
        `/api/projects/${enc(projectId)}/tasks/${enc(taskId)}/status`,
        { method: "POST", body: { status } },
      ),
    onSettled: () => invalidate(projectId),
  });
}

export function useAddLabels(projectId: string) {
  const invalidate = useInvalidateProject();
  return useMutation({
    mutationFn: ({ taskId, labels }: { taskId: string; labels: string[] }) =>
      apiFetch<{ id: string; labels: string[] }>(
        `/api/projects/${enc(projectId)}/tasks/${enc(taskId)}/labels`,
        { method: "POST", body: { labels } },
      ),
    onSuccess: () => invalidate(projectId),
  });
}

export function useAddProject() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (body: ProjectCreate) => apiFetch<Project>("/api/projects", { method: "POST", body }),
    onSuccess: () => client.invalidateQueries({ queryKey: queryKeys.projects }),
  });
}

/** Papkalar o'zgarsa bekloq ham, sessiyalarning loyihaga bog'lanishi ham boshqacha bo'ladi. */
export function useUpdateProject(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (body: ProjectUpdate) =>
      apiFetch<Project>(`/api/projects/${enc(projectId)}`, { method: "PUT", body }),
    onSuccess: () =>
      Promise.all([
        client.invalidateQueries({ queryKey: queryKeys.projects }),
        client.invalidateQueries({ queryKey: queryKeys.board(projectId) }),
        client.invalidateQueries({ queryKey: queryKeys.tasks(projectId) }),
        client.invalidateQueries({ queryKey: ["sessions"] }),
        client.invalidateQueries({ queryKey: queryKeys.folders }),
      ]),
  });
}

export function useFolderSuggestions() {
  return useQuery({
    queryKey: queryKeys.folderSuggestions,
    queryFn: ({ signal }) => apiFetch<FolderSuggestions>("/api/folders/suggestions", { signal }),
  });
}

/** `path` bo'sh bo'lsa server ~/my-projects (yoki uy papkasi)ni ochadi. */
export function useFolder(path: string, enabled = true) {
  return useQuery({
    queryKey: queryKeys.folder(path),
    queryFn: ({ signal }) => apiFetch<FolderListing>(`/api/folders?path=${enc(path)}`, { signal }),
    enabled,
    placeholderData: keepPreviousData,
  });
}

export function useInitBacklog() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (body: BacklogInit) =>
      apiFetch<{ path: string; has_backlog: boolean }>("/api/folders/init-backlog", { method: "POST", body }),
    onSuccess: () => client.invalidateQueries({ queryKey: queryKeys.folders }),
  });
}

export function useRemoveProject() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (projectId: string) =>
      apiFetch<{ ok: boolean }>(`/api/projects/${enc(projectId)}`, { method: "DELETE" }),
    onSuccess: (_data, projectId) => {
      client.removeQueries({ queryKey: queryKeys.board(projectId) });
      client.removeQueries({ queryKey: queryKeys.tasks(projectId) });
      return client.invalidateQueries({ queryKey: queryKeys.projects });
    },
  });
}

/** Yangi pane: jonli ro'yxat, loyiha hisoblagichlari va doska kartochkalari yangilanadi. */
/** `projectId` null — sessiya loyihalararo ro'yxatdan o'zgardi, barcha doska va vazifalar yangilanadi. */
function useInvalidateSessions() {
  const client = useQueryClient();
  return (projectId: string | null) =>
    Promise.all([
      client.invalidateQueries({ queryKey: ["sessions"] }),
      client.invalidateQueries({ queryKey: queryKeys.projects }),
      client.invalidateQueries({ queryKey: projectId ? queryKeys.board(projectId) : ["board"] }),
      client.invalidateQueries({ queryKey: projectId ? queryKeys.tasks(projectId) : ["task"] }),
    ]);
}

export function useStartSession(projectId: string) {
  const invalidate = useInvalidateSessions();
  return useMutation({
    mutationFn: (body: SessionStart) =>
      apiFetch<LivePane>(`/api/projects/${enc(projectId)}/sessions`, { method: "POST", body }),
    onSuccess: () => invalidate(projectId),
  });
}

export function useResumeSession(projectId: string) {
  const invalidate = useInvalidateSessions();
  return useMutation({
    mutationFn: (body: SessionResume) =>
      apiFetch<LivePane>(`/api/projects/${enc(projectId)}/sessions/resume`, {
        method: "POST",
        body,
      }),
    onSuccess: () => invalidate(projectId),
  });
}

export function useDeleteSessions(projectId: string) {
  const invalidate = useInvalidateSessions();
  return useMutation({
    mutationFn: (body: SessionsDelete) =>
      apiFetch<{ deleted: number }>(`/api/projects/${enc(projectId)}/sessions/delete`, { method: "POST", body }),
    onSuccess: () => invalidate(projectId),
  });
}

/** Vazifa tugagach agent pane'larini to'xtatish; allaqachon yo'q bo'lgani xato emas. */
export function useKillSessions(projectId: string | null) {
  const invalidate = useInvalidateSessions();
  return useMutation({
    mutationFn: async (paneIds: readonly string[]) => {
      for (const paneId of paneIds) {
        try {
          await apiFetch<{ ok: boolean }>(`/api/sessions/${enc(paneId)}/kill`, { method: "POST" });
        } catch (error) {
          if (!(error instanceof ApiError && error.code === "pane_not_found")) throw error;
        }
      }
    },
    onSettled: () => invalidate(projectId),
  });
}

/** Tugagan pane'larni KanBot ro'yxatidan olib tashlash; allaqachon yo'q bo'lgani xato emas. */
export function useRemoveSessions() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (paneIds: readonly string[]) => {
      for (const paneId of paneIds) {
        try {
          await apiFetch<{ ok: boolean }>(`/api/sessions/${enc(paneId)}`, { method: "DELETE" });
        } catch (error) {
          if (!(error instanceof ApiError && error.code === "pane_not_found")) throw error;
        }
      }
    },
    onSettled: () =>
      Promise.all([
        client.invalidateQueries({ queryKey: ["sessions"] }),
        client.invalidateQueries({ queryKey: queryKeys.projects }),
      ]),
  });
}
