import { afterEach, describe, expect, it, vi } from "vitest";

import { ApiError, apiFetch } from "./client";

function mockFetch(impl: (input: string, init: RequestInit) => Promise<Response>) {
  const fn = vi.fn(impl);
  vi.stubGlobal("fetch", fn);
  return fn;
}

const json = (status: number, body: unknown) =>
  Promise.resolve(
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } }),
  );

async function rejection(promise: Promise<unknown>): Promise<ApiError> {
  try {
    await promise;
  } catch (err) {
    if (err instanceof ApiError) return err;
    throw err;
  }
  throw new Error("xato kutilgan edi");
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("apiFetch", () => {
  it("JSON javobni qaytaradi", async () => {
    const fetch = mockFetch(() => json(200, { ok: true }));
    await expect(apiFetch("/api/health")).resolves.toEqual({ ok: true });
    expect(fetch).toHaveBeenCalledWith("/api/health", {
      method: "GET",
      headers: { Accept: "application/json" },
    });
  });

  it("body JSON bo'lib yuboriladi", async () => {
    const fetch = mockFetch(() => json(201, { id: "TASK-1" }));
    await apiFetch("/api/projects/p/tasks", { method: "POST", body: { title: "X" } });
    expect(fetch.mock.calls[0]?.[1]).toMatchObject({
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: '{"title":"X"}',
    });
  });

  it("backend xatosi {code, params, detail} → ApiError", async () => {
    mockFetch(() =>
      json(503, { code: "kanbot_unavailable", params: {}, detail: "GET /api/panes: refused" }),
    );
    const err = await rejection(apiFetch("/api/sessions"));
    expect(err).toMatchObject({
      status: 503,
      code: "kanbot_unavailable",
      params: {},
      detail: "GET /api/panes: refused",
    });
    expect(err.body).toEqual({ code: "kanbot_unavailable", params: {}, detail: "GET /api/panes: refused" });
  });

  it("tarmoq xatosi va JSON bo'lmagan javob — backend_unreachable", async () => {
    mockFetch(() => Promise.reject(new TypeError("Failed to fetch")));
    expect(await rejection(apiFetch("/api/health"))).toMatchObject({
      status: 0,
      code: "backend_unreachable",
      detail: "Failed to fetch",
    });

    mockFetch(() => Promise.resolve(new Response("proxy error", { status: 500 })));
    expect(await rejection(apiFetch("/api/health"))).toMatchObject({
      status: 500,
      code: "backend_unreachable",
    });

    mockFetch(() => json(502, { message: "boshqa format" }));
    expect(await rejection(apiFetch("/api/health"))).toMatchObject({ code: "backend_unreachable" });
  });

  it("bekor qilingan so'rov ApiError'ga aylanmaydi", async () => {
    mockFetch(() => Promise.reject(new DOMException("aborted", "AbortError")));
    await expect(apiFetch("/api/health")).rejects.toMatchObject({ name: "AbortError" });
  });
});
