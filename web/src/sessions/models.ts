import type { LivePane, SessionModel, SessionModelGroup } from "../api/types";

/** `<select>` dagi «o'z ID sini kiritaman» qatori; `@` bilan boshlanadi, shuning uchun haqiqiy ID emas. */
export const CUSTOM_MODEL = "@custom";

/** Backend `services/models.py` dagi `MODEL_ID_RE` va `MAX_MODEL_LENGTH` bilan mos. */
const MODEL_ID = /^[A-Za-z0-9][A-Za-z0-9._:/-]*(\[[A-Za-z0-9]{1,8}\])?$/;
export const MAX_MODEL_LENGTH = 200;

export function isValidModelId(value: string): boolean {
  return value.length <= MAX_MODEL_LENGTH && MODEL_ID.test(value);
}

const GROUP_ORDER: readonly SessionModelGroup[] = ["current", "legacy", "alias"];

/** `t()` parametrsiz kalitni talab qiladi, shuning uchun bu yerda `MessageKey` emas, aniq kalitlar. */
export const GROUP_TITLES = {
  current: "model.group_current",
  legacy: "model.group_legacy",
  alias: "model.group_alias",
} as const satisfies Record<SessionModelGroup, string>;

export interface ModelGroup {
  group: SessionModelGroup;
  models: SessionModel[];
}

/** Katalog tartibini saqlagan holda guruhlar; bo'sh guruh tushirib qoldiriladi. */
export function groupModels(models: readonly SessionModel[]): ModelGroup[] {
  return GROUP_ORDER.map((group) => ({ group, models: models.filter((model) => model.group === group) })).filter(
    (entry) => entry.models.length > 0,
  );
}

/** Model faqat tirik va kutayotgan (idle) sessiyada almashtiriladi; aks holda sabab kaliti. */
export function modelBlockedReason(pane: Pick<LivePane, "alive" | "state">): "model.ended" | "model.busy" | null {
  if (!pane.alive) return "model.ended";
  if (pane.state !== "idle") return "model.busy";
  return null;
}

/** Tanlangan qator yoki qo'lda kiritilgan ID; hali tanlanmagan/yaroqsiz bo'lsa null. */
export function chosenModel(selected: string, custom: string): string | null {
  const value = selected === CUSTOM_MODEL ? custom.trim() : selected;
  return value !== "" && isValidModelId(value) ? value : null;
}
