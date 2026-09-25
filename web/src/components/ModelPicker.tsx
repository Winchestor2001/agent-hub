import { useState, type SubmitEvent } from "react";

import { useSessionModels, useSetSessionModel } from "../api/queries";
import type { LivePane } from "../api/types";
import { useI18n } from "../i18n/context";
import {
  chosenModel,
  CUSTOM_MODEL,
  GROUP_TITLES,
  groupModels,
  MAX_MODEL_LENGTH,
  modelBlockedReason,
} from "../sessions/models";
import { ErrorText } from "./ErrorText";

/**
 * Ishlab turgan Claude sessiyasida modelni tanlash: pane'ga `/model <id>` yuboriladi.
 * Terminaldagi picker Opus 4.7/4.8 kabi eski modellarni ko'rsatmaydi — bu yerda ular bor va
 * ixtiyoriy ID ham kiritsa bo'ladi.
 */
export function ModelPicker({ pane }: { pane: LivePane }) {
  const { t } = useI18n();
  const models = useSessionModels();
  const setModel = useSetSessionModel(pane.id);
  const [selected, setSelected] = useState("");
  const [custom, setCustom] = useState("");

  const blocked = modelBlockedReason(pane);
  const model = chosenModel(selected, custom);
  const groups = groupModels(models.data?.models ?? []);

  function submit(event: SubmitEvent) {
    event.preventDefault();
    if (model && !blocked) setModel.mutate(model);
  }

  return (
    <form className="model-picker" onSubmit={submit}>
      <label className="model-picker-label">
        <span className="muted">{t("model.label")}</span>
        <select
          value={selected}
          disabled={blocked !== null}
          onChange={(event) => {
            setSelected(event.target.value);
            setModel.reset();
          }}
        >
          <option value="">{t("model.choose")}</option>
          {groups.map(({ group, models: items }) => (
            <optgroup key={group} label={t(GROUP_TITLES[group])}>
              {items.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.label === item.id ? item.id : `${item.label} · ${item.id}`}
                </option>
              ))}
            </optgroup>
          ))}
          <option value={CUSTOM_MODEL}>{t("model.custom")}</option>
        </select>
      </label>
      {selected === CUSTOM_MODEL && (
        <input
          className="mono"
          value={custom}
          maxLength={MAX_MODEL_LENGTH}
          placeholder={t("model.custom_placeholder")}
          aria-label={t("model.custom")}
          disabled={blocked !== null}
          onChange={(event) => {
            setCustom(event.target.value);
            setModel.reset();
          }}
        />
      )}
      <button
        type="submit"
        className="button button-small"
        disabled={blocked !== null || model === null || setModel.isPending}
      >
        {setModel.isPending ? t("model.applying") : t("model.apply")}
      </button>
      {blocked && <span className="muted">{t(blocked)}</span>}
      {!blocked && model && <span className="muted">{t("model.default_hint")}</span>}
      {setModel.isSuccess && <span className="muted">{t("model.sent", { model: setModel.data.model })}</span>}
      {setModel.error && <ErrorText error={setModel.error} />}
    </form>
  );
}
