import type { FolderEntry } from "../api/types";

/** `/Users/me/my-projects/x` → `~/my-projects/x` (faqat ko'rsatish uchun). */
export function tildify(path: string, home: string): string {
  if (!home) return path;
  if (path === home) return "~";
  return path.startsWith(`${home}/`) ? `~${path.slice(home.length)}` : path;
}

/** Nomi bo'yicha (katta-kichik harfsiz) filtr; tartib saqlanadi. */
export function filterFolders(folders: readonly FolderEntry[], query: string): FolderEntry[] {
  const needle = query.trim().toLowerCase();
  return needle ? folders.filter((folder) => folder.name.toLowerCase().includes(needle)) : [...folders];
}

/** Yo'lning oxirgi qismi — papka tanlanganda loyiha nomi uchun. */
export function baseName(path: string): string {
  return path.replace(/\/+$/, "").split("/").pop() ?? "";
}

/** Takrorsiz qo'shish (bo'sh satr qo'shilmaydi). */
export function addUnique(items: readonly string[], item: string): string[] {
  const value = item.trim();
  return !value || items.includes(value) ? [...items] : [...items, value];
}
