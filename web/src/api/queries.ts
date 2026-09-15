import { QueryClient, useQuery } from "@tanstack/react-query";

import { apiFetch, type ApiError } from "./client";
import type { Health, ProjectsResponse, SessionsResponse } from "./types";

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
} as const;

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
