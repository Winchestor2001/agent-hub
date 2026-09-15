import { isMessageKey, type Message } from "../i18n/messages";
import { ApiError, BACKEND_UNREACHABLE } from "./client";
import type { ApiErrorBody, Health, ProjectsResponse, Severity } from "./types";

export interface Banner {
  id: string;
  severity: Severity;
  message: Message;
}

export interface BannerInput {
  health: Health | undefined;
  healthError: ApiError | null;
  projects: ProjectsResponse | undefined;
  projectsError: ApiError | null;
}

/** Backend xatosini lug'at xabariga: `error.<code>`, noma'lum kod — `error.unknown`. */
export function errorMessage(error: ApiErrorBody | ApiError): Message {
  const key = `error.${error.code}`;
  return {
    key: isMessageKey(key) ? key : "error.unknown",
    params: { ...error.params, code: error.code },
    detail: error.detail,
  };
}

function problemBanner(code: string, severity: Severity, params: Record<string, unknown>): Banner {
  const id = `health:${code}:${JSON.stringify(params)}`;
  switch (code) {
    case "kanbot_unavailable": {
      const detail = typeof params.error === "string" ? params.error : null;
      return { id, severity: "error", message: { key: "banner.kanbot_unavailable", detail } };
    }
    case "no_runner":
      return { id, severity: "error", message: { key: "banner.no_runner" } };
    default:
      return { id, severity, message: errorMessage({ code, params, detail: null }) };
  }
}

/**
 * Oxirgi polling natijalaridan bannerlar: backend, KanBot, runner, xavfsizlik va bekloq holati.
 * Xatolar ogohlantirishlardan oldin.
 */
export function collectBanners(input: BannerInput): Banner[] {
  const { health, healthError, projects, projectsError } = input;
  const unreachable = [healthError, projectsError].find((e) => e?.code === BACKEND_UNREACHABLE);
  if (unreachable) {
    // Backend yo'q — qolgan ma'lumotlar eskirgan, boshqa bannerlar chalg'itadi.
    return [
      {
        id: BACKEND_UNREACHABLE,
        severity: "error",
        message: { key: "banner.backend_unreachable", detail: unreachable.detail },
      },
    ];
  }

  const banners: Banner[] = [];
  if (healthError) {
    banners.push({ id: `health:${healthError.code}`, severity: "error", message: errorMessage(healthError) });
  } else if (health) {
    for (const problem of health.problems) {
      banners.push(problemBanner(problem.code, problem.severity, problem.params));
    }
  }

  if (projectsError) {
    banners.push({
      id: `projects:${projectsError.code}`,
      severity: "error",
      message: errorMessage(projectsError),
    });
  } else if (projects) {
    let cliMissing = false;
    for (const project of projects.projects) {
      const error = project.error;
      if (!error) continue;
      if (error.code === "backlog_cli_missing") {
        if (!cliMissing) {
          banners.push({
            id: "backlog_cli_missing",
            severity: "error",
            message: { key: "banner.backlog_cli_missing", detail: error.detail },
          });
        }
        cliMissing = true;
      } else if (error.code === "backlog_not_found") {
        banners.push({
          id: `project:${project.id}:${error.code}`,
          severity: "error",
          message: {
            key: "banner.backlog_not_found",
            params: { project: project.name, path: project.backlog_dir },
          },
        });
      } else {
        banners.push({
          id: `project:${project.id}:${error.code}`,
          severity: "error",
          message: {
            key: "banner.backlog_error",
            params: { project: project.name },
            detail: error.detail ?? error.code,
          },
        });
      }
    }
  }

  const rank: Record<Severity, number> = { error: 0, warning: 1 };
  return dedupe(banners).sort((a, b) => rank[a.severity] - rank[b.severity]);
}

/** Bir xil matnli bannerlar (masalan, shell ham config'da, ham runner'da yoqilgan) — bittasi. */
function dedupe(banners: Banner[]): Banner[] {
  const seen = new Set<string>();
  return banners.filter(({ message }) => {
    const params = Object.entries(message.params ?? {}).filter(
      ([name]) => name !== "source" && name !== "runner",
    );
    const identity = JSON.stringify([message.key, params]);
    if (seen.has(identity)) return false;
    seen.add(identity);
    return true;
  });
}
