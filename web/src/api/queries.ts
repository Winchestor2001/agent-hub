import { QueryClient, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { apiFetch, type ApiError } from "./client";
import type {
  Board,
  Health,
  Project,
  ProjectCreate,
  ProjectsResponse,
  SessionsResponse,
  TaskCreate,
  TaskDetail,
} from "./types";

/** Jonli holatlar (health, loyihalar, pane'lar). */
export const POLL_MS = 2500;
/** O'tgan sessiyalar — KanBot ularni ~6 s da yangilaydi. */
export const PAST_POLL_MS = 6000;
export const PAST_LIMIT = 50;

export const queryKeys = {
  health: ["health"],
  projects: ["projects"],
  liveSessions: ["sessions", "live"],
  pastSessions: ["sessions", "past"],
  board: (projectId: string) => ["board", projectId] as const,
  tasks: (projectId: string) => ["task", projectId] as const,
  task: (projectId: string, taskId: string) => ["task", projectId, taskId] as const,
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
    select: (data) => data.live,
    refetchInterval: POLL_MS,
  });
}

export function usePastSessions() {
  return useQuery({
    queryKey: queryKeys.pastSessions,
    queryFn: ({ signal }) =>
      apiFetch<SessionsResponse>(`/api/sessions?past_limit=${String(PAST_LIMIT)}`, { signal }),
    select: (data) => data.past,
    refetchInterval: PAST_POLL_MS,
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
