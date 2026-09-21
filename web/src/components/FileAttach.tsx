import { useRef, useState, type ClipboardEvent, type DragEvent } from "react";

import { useUploadFiles } from "../api/queries";
import type { UploadedFile } from "../api/types";
import { useI18n } from "../i18n/context";
import { formatSize } from "../uploads/model";
import { ErrorText } from "./ErrorText";

const FILE_ICONS: Record<UploadedFile["kind"], string> = { image: "🖼", video: "🎬", file: "📄" };

interface FileAttachProps {
  projectId: string;
  /** Qaysi loyiha papkasiga yuklanadi (bo'sh — birinchisi). */
  cwd?: string | undefined;
  /** Ma'lum bo'lsa fayllar `uploads/<task-id>/` ga tushadi, aks holda `uploads/inbox/` ga. */
  taskId?: string | undefined;
  files: UploadedFile[];
  onChange: (files: UploadedFile[]) => void;
}

/**
 * Fayl biriktirish: tanlash, sudrab tashlash va Ctrl+V bilan skrinshot qo'yish.
 *
 * Fayl darhol yuklanadi — forma yuborilganda faqat yo'llar ketadi. Ro'yxatdan olib tashlash
 * yo'lni formadan chiqaradi, diskdagi faylga tegmaydi.
 */
export function FileAttach({ projectId, cwd, taskId, files, onChange }: FileAttachProps) {
  const { t } = useI18n();
  const upload = useUploadFiles(projectId);
  const inputRef = useRef<HTMLInputElement>(null);
  const [over, setOver] = useState(false);

  function add(picked: FileList | File[] | null) {
    const list = Array.from(picked ?? []);
    if (list.length === 0) return;
    upload.mutate(
      { files: list, cwd, taskId },
      { onSuccess: (data) => { onChange([...files, ...data.files]); } },
    );
  }

  function onDrop(event: DragEvent<HTMLDivElement>) {
    event.preventDefault();
    setOver(false);
    add(event.dataTransfer.files);
  }

  function onPaste(event: ClipboardEvent<HTMLDivElement>) {
    // Brauzer skrinshotni `image.png` nomli fayl sifatida beradi.
    const pasted = Array.from(event.clipboardData.files);
    if (pasted.length === 0) return;
    event.preventDefault();
    add(pasted);
  }

  return (
    <div className="field">
      <span className="field-label">{t("files.label")}</span>
      <div
        className={over ? "file-drop file-drop-over" : "file-drop"}
        onPaste={onPaste}
        onDragOver={(event) => {
          event.preventDefault();
          setOver(true);
        }}
        onDragLeave={() => {
          setOver(false);
        }}
        onDrop={onDrop}
      >
        <button
          type="button"
          className="button button-small"
          disabled={upload.isPending}
          onClick={() => inputRef.current?.click()}
        >
          {upload.isPending ? t("files.uploading") : t("files.pick")}
        </button>
        <span className="muted">{over ? t("files.drop") : t("files.hint")}</span>
        <input
          ref={inputRef}
          type="file"
          multiple
          hidden
          onChange={(event) => {
            add(event.target.files);
            // Bir xil faylni qayta tanlash ham `change` chiqarsin.
            event.target.value = "";
          }}
        />
      </div>
      {files.length > 0 && (
        <ul className="file-list">
          {files.map((file) => (
            <li key={file.path}>
              <span className="file-kind" aria-hidden="true">
                {FILE_ICONS[file.kind]}
              </span>
              <span className="file-name mono">{file.name}</span>
              <span className="muted">{formatSize(file.size)}</span>
              <button
                type="button"
                className="icon-button"
                aria-label={t("files.remove")}
                title={t("files.remove")}
                onClick={() => {
                  onChange(files.filter((item) => item.path !== file.path));
                }}
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      )}
      {upload.error && <ErrorText error={upload.error} />}
    </div>
  );
}
