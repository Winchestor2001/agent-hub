import { useState, type ClipboardEvent } from "react";

import { useUploadFiles } from "../api/queries";
import type { LivePane, Project } from "../api/types";
import { panePastePath, paneUploadDir } from "../uploads/model";

interface PasteUploadOptions {
  /** Jonli ro'yxatdagi ma'lumot; hali kelmagan bo'lsa undefined. */
  pane: LivePane | undefined;
  /** Pane tegishli loyiha (`pane.project_id`); papkasi hech qaysi loyihaga kirmasa undefined. */
  project: Project | undefined;
  /** Faqat pane tirik va ulanish ochiq bo'lganda fayl ushlanadi. */
  active: boolean;
  /** Matnni terminalga paste qiladi (bracketed paste rejimi hurmat qilinadi). */
  paste: (text: string) => void;
}

/**
 * Terminalga fayl/rasm paste qilish: clipboard'dagi fayllar pane loyihasiga yuklanadi, keyin
 * yo'llari pane'ga matn bo'lib yoziladi — agent ularni o'zi o'qiydi.
 *
 * xterm paste hodisasini `stopPropagation` qiladi va clipboard'dan faqat `text/plain` oladi,
 * shuning uchun `onPasteCapture` (capture fazasi) ishlatiladi. Clipboard'da fayl bo'lmasa
 * hodisaga tegilmaydi — oddiy matn paste'i xterm'da qoladi.
 */
export function usePasteUpload({ pane, project, active, paste }: PasteUploadOptions) {
  const upload = useUploadFiles(project?.id ?? "");
  const [noProject, setNoProject] = useState(false);

  function onPasteCapture(event: ClipboardEvent<HTMLElement>) {
    const files = Array.from(event.clipboardData.files);
    if (files.length === 0 || !active) return;
    // Finder'dan nusxalangan faylda text/plain ham bo'ladi (fayl nomi) — u aralashmasin.
    event.preventDefault();
    event.stopPropagation();

    const dir = pane && project ? paneUploadDir(pane.cwd, project.dirs) : null;
    if (!pane || !dir) {
      setNoProject(true);
      return;
    }
    setNoProject(false);
    upload.mutate(
      { files, cwd: dir, taskId: pane.task?.id },
      {
        onSuccess: (data) => {
          // Oxiridagi bo'shliq: foydalanuvchi shu zahoti yozishda davom etadi.
          paste(`${data.files.map((file) => panePastePath(pane.cwd, dir, file.path)).join(" ")} `);
        },
      },
    );
  }

  return { onPasteCapture, uploading: upload.isPending, error: upload.error, noProject };
}
