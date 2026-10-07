import type { ConfigItem, ConfigKind, ConfigScope } from "../api/types";
import { isMessageKey, type Translator } from "../i18n/messages";

/** Backend `NAME_RE` bilan bir xil: kichik harf, raqam, tire; 64 belgigacha. */
export const NAME_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;

/** Ekrandagi turlar tartibi: avval yo'riqnoma va sozlamalar, keyin to'plamlar. */
export const KIND_ORDER = [
  "claude_md",
  "claude_local_md",
  "settings",
  "mcp",
  "rules",
  "commands",
  "skills",
  "agents",
  "hooks",
] as const;

export function orderKinds(kinds: ConfigKind[]): ConfigKind[] {
  const rank = (id: string) => {
    const at = (KIND_ORDER as readonly string[]).indexOf(id);
    return at === -1 ? KIND_ORDER.length : at;
  };
  return [...kinds].sort((a, b) => rank(a.id) - rank(b.id));
}

export function kindFits(kind: ConfigKind, scope: ConfigScope): boolean {
  return kind.scopes.includes(scope.kind);
}

/** Nom yoki yo'l bo'yicha, katta-kichik harfsiz; bo'sh so'rov — hammasi. */
export function filterItems(items: ConfigItem[], query: string): ConfigItem[] {
  const needle = query.trim().toLowerCase();
  if (!needle) return items;
  return items.filter((item) => item.name.toLowerCase().includes(needle) || item.path.toLowerCase().includes(needle));
}

/**
 * To'plam turidagi nom tekshiruvi (backend ham tekshiradi — bu faqat darhol ko'rsatish uchun).
 * Bir nechta kengaytmali tur (hooks) uchun nom kengaytma bilan yoziladi: `guard.sh`.
 */
export function nameProblem(kind: ConfigKind, name: string): "empty" | "invalid" | "extension" | null {
  if (!kind.collection) return null;
  if (!name) return "empty";
  if (kind.layout === "file" && kind.extensions.length > 1) {
    const dot = name.lastIndexOf(".");
    if (dot === -1 || !kind.extensions.includes(name.slice(dot))) return "extension";
    return NAME_RE.test(name.slice(0, dot)) ? null : "invalid";
  }
  return NAME_RE.test(name) ? null : "invalid";
}

/** Yuklangan fayl nomidan element nomi: `Deploy.md` → `deploy`, `guard.sh` (hooks) o'zgarmaydi. */
export function nameFromFile(kind: ConfigKind, fileName: string): string {
  const base = fileName.split(/[\\/]/).pop() ?? fileName;
  if (kind.collection && kind.layout === "file" && kind.extensions.length > 1) return base.toLowerCase();
  const stem = base.replace(/\.[^.]+$/, "");
  // SKILL.md yuklansa papka nomini foydalanuvchi yozadi.
  if (kind.layout === "skill" && stem.toUpperCase() === "SKILL") return "";
  return stem
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64);
}

export function scopeLabel(scopes: ConfigScope[] | undefined, id: string): string {
  return scopes?.find((scope) => scope.id === id)?.label ?? id;
}

/** Qamrov ochilganda boshlang'ich tur: shu qamrovda ishlaydigan birinchisi. */
export function firstKind(kinds: ConfigKind[], scope: ConfigScope | undefined): string | null {
  if (!scope) return null;
  return orderKinds(kinds).find((kind) => kindFits(kind, scope))?.id ?? null;
}

/** Backend id'si (tur, shablon) uchun tarjima; lug'atda yo'q bo'lsa — id'ning o'zi. */
export function lookup(message: Translator["message"], key: string, fallback: string): string {
  return isMessageKey(key) ? message({ key }) : fallback;
}
