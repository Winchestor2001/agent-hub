function trimSlash(path: string): string {
  return path.length > 1 ? path.replace(/\/+$/, "") : path;
}

/**
 * Pane papkasini o'z ichiga olgan eng ichki loyiha papkasi (yo'q bo'lsa `null`).
 *
 * Backend ham shunday hal qiladi (`project_for_path`): pane loyiha papkasining ichki papkasida
 * ishlayotgan bo'lishi mumkin. Segment bo'yicha solishtiriladi — `/a/app` `/a/app-web` ga mos emas.
 */
export function paneUploadDir(paneCwd: string, dirs: readonly string[]): string | null {
  const cwd = trimSlash(paneCwd);
  let best: string | null = null;
  for (const dir of dirs) {
    const root = trimSlash(dir);
    const inside = cwd === root || cwd.startsWith(`${root}/`);
    if (inside && (best === null || root.length > trimSlash(best).length)) best = dir;
  }
  return best;
}

/** Bo'shliq va shell uchun maxsus belgilar backslash bilan (Terminal.app sudrab tashlashdagi kabi). */
function escapePath(path: string): string {
  return path.replace(/[^A-Za-z0-9_@%+=:,./~-]/g, "\\$&");
}

/**
 * Pane'ga yoziladigan yo'l. Pane papkasi yuklash papkasi bilan bir xil bo'lsa nisbiy (agent
 * qo'shimcha ruxsatsiz o'qiydi), ichki papkada bo'lsa absolyut — nisbiy yo'l noto'g'ri joyga
 * ishora qilardi.
 */
export function panePastePath(paneCwd: string, uploadDir: string, path: string): string {
  const root = trimSlash(uploadDir);
  return escapePath(trimSlash(paneCwd) === root ? path : `${root}/${path}`);
}

/** Fayl hajmi: 1 KB dan kichigi baytda, qolgani KB/MB da. */
export function formatSize(bytes: number): string {
  if (bytes < 1024) return `${String(bytes)} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
