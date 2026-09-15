import { describe, expect, it } from "vitest";

import { createTranslator } from "../i18n/messages";
import { collectBanners, errorMessage, type BannerInput } from "./banners";
import { ApiError } from "./client";
import type { Health, ProjectItem, ProjectsResponse } from "./types";

const { message } = createTranslator("uz");

const healthy: Health = {
  ok: true,
  version: "0.1.0",
  kanbot: { url: "http://127.0.0.1:8787", reachable: true, version: "0.8.2", runners_online: 1 },
  problems: [],
};

function project(overrides: Partial<ProjectItem> = {}): ProjectItem {
  return {
    id: "leveling",
    name: "Leveling",
    backlog_dir: "/p/leveling-backend",
    repos: [],
    dirs: ["/p/leveling-backend"],
    summary: null,
    error: null,
    ...overrides,
  };
}

const projects = (...items: ProjectItem[]): ProjectsResponse => ({
  projects: items,
  kanbot_available: true,
});

function banners(input: Partial<BannerInput>) {
  return collectBanners({
    health: healthy,
    healthError: null,
    projects: projects(project()),
    projectsError: null,
    ...input,
  }).map((b) => ({ severity: b.severity, text: message(b.message), detail: b.message.detail ?? null }));
}

describe("collectBanners", () => {
  it("hammasi joyida — banner yo'q", () => {
    expect(banners({})).toEqual([]);
  });

  it("KanBot ishlamayapti", () => {
    const health: Health = {
      ...healthy,
      ok: false,
      kanbot: { url: "http://127.0.0.1:8787", reachable: false },
      problems: [
        { code: "kanbot_unavailable", severity: "error", params: { error: "GET /api/health: refused" } },
      ],
    };
    expect(banners({ health })).toEqual([
      {
        severity: "error",
        text: expect.stringContaining("KanBot ishlamayapti") as string,
        detail: "GET /api/health: refused",
      },
    ]);
  });

  it("runner yo'q", () => {
    const health: Health = {
      ...healthy,
      kanbot: { ...healthy.kanbot, runners_online: 0 },
      problems: [{ code: "no_runner", severity: "warning", params: {} }],
    };
    const [banner, ...rest] = banners({ health });
    expect(rest).toEqual([]);
    expect(banner?.severity).toBe("error");
    expect(banner?.text).toContain("runner ulanmagan");
    expect(banner?.text).toContain("make dev-runner");
  });

  it("xavfsizlik muammolari, takrorlar birlashtiriladi, xatolar oldinda", () => {
    const health: Health = {
      ...healthy,
      ok: false,
      problems: [
        { code: "kanbot_version_unsupported", severity: "warning", params: { version: "0.9.0", supported: "0.8.x" } },
        { code: "shell_enabled", severity: "error", params: { agent: "shell", source: "config" } },
        { code: "shell_enabled", severity: "error", params: { agent: "shell", source: "runner", runner: "mac" } },
        { code: "brand_new_problem", severity: "warning", params: {} },
      ],
    };
    expect(banners({ health }).map((b) => [b.severity, b.text])).toEqual([
      ["error", "Xavfli «shell» agenti yoqilgan. O'chirish: kanbot config --disable shell glm kimi"],
      ["warning", "KanBot 0.9.0 qo'llab-quvvatlanmaydi (kerak: 0.8.x)"],
      ["warning", "Kutilmagan xato (brand_new_problem)"],
    ]);
  });

  it("bekloq topilmadi, CLI yo'q (bitta banner), boshqa bekloq xatosi", () => {
    const cliMissing = { code: "backlog_cli_missing", params: { executable: "backlog" }, detail: "backlog topilmadi" };
    const list = projects(
      project({ error: { code: "backlog_not_found", params: { path: "/p/x" }, detail: "No Backlog.md project found" } }),
      project({ id: "a", name: "A", error: cliMissing }),
      project({ id: "b", name: "B", error: cliMissing }),
      project({ id: "c", name: "C", error: { code: "backlog_timeout", params: {}, detail: null } }),
      project({ id: "d", name: "D", summary: null, error: null }),
    );
    expect(banners({ projects: list })).toEqual([
      { severity: "error", text: "«Leveling» loyihasida bekloq topilmadi: /p/leveling-backend", detail: null },
      { severity: "error", text: "backlog CLI topilmadi — vazifalar o'qilmaydi", detail: "backlog topilmadi" },
      { severity: "error", text: "«C» loyihasining bekloqi o'qilmadi", detail: "backlog_timeout" },
    ]);
  });

  it("backend yo'q — faqat bitta banner, eskirgan ma'lumotlar e'tiborsiz", () => {
    const down = new ApiError(0, "backend_unreachable", {}, "Failed to fetch");
    const stale: Health = { ...healthy, problems: [{ code: "no_runner", severity: "warning", params: {} }] };
    expect(banners({ health: stale, healthError: down, projectsError: down })).toEqual([
      { severity: "error", text: "Agent Hub backend bilan aloqa yo'q. Ma'lumotlar yangilanmayapti.", detail: "Failed to fetch" },
    ]);
  });

  it("boshqa API xatolari tarjima qilinadi", () => {
    const projectsError = new ApiError(500, "registry_invalid", { path: "/c/projects.yaml", error: "bad" });
    expect(banners({ projectsError, projects: undefined })).toEqual([
      { severity: "error", text: "Loyihalar ro'yxati buzilgan: /c/projects.yaml", detail: null },
    ]);
  });
});

describe("errorMessage", () => {
  it("noma'lum kod umumiy xabarga, params kodni ustidan yozmaydi, detail saqlanadi", () => {
    const msg = errorMessage({ code: "weird", params: { code: "boshqa" }, detail: "trace" });
    expect(message(msg)).toBe("Kutilmagan xato (weird)");
    expect(msg.detail).toBe("trace");
  });

  it("ro'yxat parametrlari vergul bilan", () => {
    const msg = errorMessage({ code: "status_invalid", params: { status: "Blah", allowed: ["To Do", "Done"] }, detail: null });
    expect(message(msg)).toBe("Status noto'g'ri: «Blah». Mumkin: To Do, Done");
  });
});
