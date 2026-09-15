import { uz } from "./uz";

export type MessageKey = keyof typeof uz;

/** Har bir til lug'ati: aynan `uz` dagi kalitlar, qiymati — matn. */
export type Dictionary = { readonly [K in MessageKey]: string };

/** Yangi til: `Dictionary` turidagi fayl va shu xaritada bitta qator. */
export const dictionaries = { uz } as const satisfies Record<string, Dictionary>;

export type Locale = keyof typeof dictionaries;

export const DEFAULT_LOCALE: Locale = "uz";

type Placeholders<S extends string> = S extends `${string}{${infer P}}${infer Rest}`
  ? P | Placeholders<Rest>
  : never;

type ParamValue = string | number;

/** O'rinbosarsiz kalit — parametrsiz, aks holda barcha o'rinbosarlar majburiy. */
export type MessageArgs<K extends MessageKey> = [Placeholders<(typeof uz)[K]>] extends [never]
  ? []
  : [params: Record<Placeholders<(typeof uz)[K]>, ParamValue>];

/** Runtime xabar (masalan, backend xato kodidan): parametrlar tur bilan tekshirilmaydi. */
export interface Message {
  key: MessageKey;
  params?: Readonly<Record<string, unknown>>;
  /** Diagnostika matni (CLI yoki KanBot chiqishi) — tarjima qilinmaydi. */
  detail?: string | null;
}

export interface Translator {
  locale: Locale;
  t: <K extends MessageKey>(key: K, ...args: MessageArgs<K>) => string;
  message: (message: Message) => string;
}

export function isMessageKey(key: string): key is MessageKey {
  return Object.hasOwn(uz, key);
}

function formatValue(value: unknown): string {
  if (Array.isArray(value)) return value.map(formatValue).join(", ");
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return "…";
}

export function format(template: string, params: Readonly<Record<string, unknown>> = {}): string {
  return template.replace(/\{(\w+)\}/g, (_, name: string) =>
    Object.hasOwn(params, name) ? formatValue(params[name]) : "…",
  );
}

export function createTranslator(locale: Locale): Translator {
  const dictionary: Dictionary = dictionaries[locale];
  return {
    locale,
    t: (key, ...args) => format(dictionary[key], args[0]),
    message: ({ key, params }) => format(dictionary[key], params),
  };
}
