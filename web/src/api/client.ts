import type { ApiErrorBody } from "./types";

/** Backend xatosi `{code, params, detail}`; tarmoq yoki JSON bo'lmagan javob — `backend_unreachable`. */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly params: Readonly<Record<string, unknown>>;
  readonly detail: string | null;

  constructor(
    status: number,
    code: string,
    params: Record<string, unknown> = {},
    detail: string | null = null,
  ) {
    super(detail ?? code);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.params = params;
    this.detail = detail;
  }

  get body(): ApiErrorBody {
    return { code: this.code, params: { ...this.params }, detail: this.detail };
  }
}

export const BACKEND_UNREACHABLE = "backend_unreachable";

function isErrorBody(value: unknown): value is ApiErrorBody {
  if (typeof value !== "object" || value === null) return false;
  const body = value as Record<string, unknown>;
  return (
    typeof body.code === "string" &&
    typeof body.params === "object" &&
    body.params !== null &&
    (body.detail === null || typeof body.detail === "string")
  );
}

export interface RequestOptions {
  method?: "GET" | "POST" | "PUT" | "DELETE";
  body?: unknown;
  /** Multipart yuklama; `body` o'rniga beriladi (Content-Type'ni brauzer o'zi qo'yadi). */
  form?: FormData;
  signal?: AbortSignal;
}

export async function apiFetch<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: "application/json" };
  const init: RequestInit = { method: options.method ?? "GET", headers };
  if (options.signal) init.signal = options.signal;
  if (options.form !== undefined) {
    // Content-Type qo'lda qo'yilmaydi: brauzer `boundary` bilan birga o'zi yozadi.
    init.body = options.form;
  } else if (options.body !== undefined) {
    headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(options.body);
  }

  let resp: Response;
  try {
    resp = await fetch(path, init);
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") throw err;
    throw new ApiError(0, BACKEND_UNREACHABLE, {}, err instanceof Error ? err.message : String(err));
  }

  let data: unknown;
  try {
    data = await resp.json();
  } catch {
    // Agent Hub doim JSON qaytaradi; JSON emas — oradagi proxy (Vite) backend'ga yetolmagan.
    throw new ApiError(resp.status, BACKEND_UNREACHABLE, {}, `HTTP ${String(resp.status)}`);
  }
  if (!resp.ok) {
    if (isErrorBody(data)) throw new ApiError(resp.status, data.code, data.params, data.detail);
    throw new ApiError(resp.status, BACKEND_UNREACHABLE, {}, `HTTP ${String(resp.status)}`);
  }
  return data as T;
}
