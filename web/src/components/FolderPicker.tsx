import { useState } from "react";

import { useFolder } from "../api/queries";
import { tildify } from "../board/folders";
import { useI18n } from "../i18n/context";
import { ErrorText } from "./ErrorText";

interface FolderPickerProps {
  /** Bo'sh bo'lsa server ~/my-projects (yoki uy papkasi)ni ochadi. */
  initialPath: string;
  onSelect: (path: string) => void;
  onCancel: () => void;
}

/** Uy papkasi ichidagi papka brauzeri: faqat papkalar, uydan yuqoriga chiqib bo'lmaydi. */
export function FolderPicker({ initialPath, onSelect, onCancel }: FolderPickerProps) {
  const { t } = useI18n();
  const [path, setPath] = useState(initialPath);
  const folder = useFolder(path);
  const data = folder.data;

  // Boshlang'ich yo'l noto'g'ri bo'lsa (masalan, qo'lda xato yozilgan) standart papkaga qaytamiz.
  if (folder.isError && path !== "" && path === initialPath) {
    setPath("");
  }

  return (
    <div className="picker">
      <div className="picker-bar">
        <button
          type="button"
          className="button button-small"
          disabled={!data?.parent}
          onClick={() => {
            if (data?.parent) setPath(data.parent);
          }}
        >
          ↑ {t("picker.up")}
        </button>
        <span className="mono picker-path" title={data?.path}>
          {data ? tildify(data.path, data.home) : t("picker.loading")}
        </span>
        {data?.has_backlog && <span className="chip chip-ok">{t("projects.backlog_yes")}</span>}
      </div>
      {folder.error && <ErrorText error={folder.error} />}
      <ul className="list picker-list" aria-busy={folder.isFetching}>
        {data?.entries.map((entry) => (
          <li key={entry.path}>
            <button
              type="button"
              className="list-item picker-entry"
              onClick={() => {
                setPath(entry.path);
              }}
            >
              <span className="list-item-title">📁 {entry.name}</span>
              {entry.has_backlog && <span className="chip chip-ok">{t("projects.backlog_yes")}</span>}
            </button>
          </li>
        ))}
      </ul>
      {data && data.entries.length === 0 && <p className="muted">{t("picker.empty")}</p>}
      {data?.truncated && <p className="muted">{t("picker.truncated")}</p>}
      <div className="form-actions">
        <button type="button" className="button button-small" onClick={onCancel}>
          {t("common.cancel")}
        </button>
        <button
          type="button"
          className="button button-small button-primary"
          disabled={!data || folder.isPlaceholderData}
          onClick={() => {
            if (data) onSelect(data.path);
          }}
        >
          {t("picker.select")}
        </button>
      </div>
    </div>
  );
}
