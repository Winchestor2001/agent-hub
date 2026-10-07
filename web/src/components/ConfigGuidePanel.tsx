import { useConfigGuide, useConfigGuides } from "../api/queries";
import { useI18n } from "../i18n/context";
import { ErrorText } from "./ErrorText";
import { Markdown } from "./Markdown";

interface ConfigGuidePanelProps {
  guideId: string;
  onSelect: (id: string) => void;
  onClose: () => void;
}

/** O'zbekcha qo'llanmalar (backend paketidagi markdown). */
export function ConfigGuidePanel({ guideId, onSelect, onClose }: ConfigGuidePanelProps) {
  const { t } = useI18n();
  const guides = useConfigGuides();
  const guide = useConfigGuide(guideId);

  return (
    <aside className="config-guide" aria-label={t("config.guide")}>
      <header className="config-guide-header">
        <select
          aria-label={t("config.guide_choose")}
          value={guideId}
          onChange={(event) => {
            onSelect(event.target.value);
          }}
        >
          {(guides.data?.guides ?? [{ id: guideId, title: guideId, kinds: [] }]).map((item) => (
            <option key={item.id} value={item.id}>
              {item.title}
            </option>
          ))}
        </select>
        <button type="button" className="icon-button" aria-label={t("common.close")} onClick={onClose}>
          ×
        </button>
      </header>
      <div className="config-guide-body">
        {guide.error ? (
          <ErrorText error={guide.error} />
        ) : guide.data ? (
          <Markdown source={guide.data.content} />
        ) : (
          <p className="muted">{t("config.loading")}</p>
        )}
      </div>
    </aside>
  );
}
