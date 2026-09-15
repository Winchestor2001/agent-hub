import { useEffect, useRef, type ReactNode } from "react";

import { useI18n } from "../i18n/context";

interface ModalProps {
  title: string;
  onClose: () => void;
  children: ReactNode;
}

/** Native `<dialog>`: fokus ichida qoladi, Escape yopadi. */
export function Modal({ title, onClose, children }: ModalProps) {
  const { t } = useI18n();
  const ref = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    dialog.showModal();
    // showModal fokusni birinchi tugmaga (Yopish) beradi — formaning birinchi maydoniga o'tkazamiz.
    dialog.querySelector<HTMLElement>("form input, form textarea, form select")?.focus();
    return () => {
      dialog.close();
    };
  }, []);

  return (
    <dialog
      ref={ref}
      className="modal"
      aria-label={title}
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
    >
      <header className="modal-header">
        <h2>{title}</h2>
        <button type="button" className="icon-button" aria-label={t("common.close")} onClick={onClose}>
          ×
        </button>
      </header>
      {children}
    </dialog>
  );
}

interface FieldProps {
  label: string;
  hint?: string;
  children: ReactNode;
}

export function Field({ label, hint, children }: FieldProps) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      {children}
      {hint && <span className="field-hint">{hint}</span>}
    </label>
  );
}
