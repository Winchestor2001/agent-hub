import { errorMessage } from "../api/banners";
import type { ApiError } from "../api/client";
import type { ApiErrorBody } from "../api/types";
import { useI18n } from "../i18n/context";

/** Panel ichidagi qisqa xato matni (batafsil — title'da). */
export function ErrorText({ error }: { error: ApiError | ApiErrorBody }) {
  const { message } = useI18n();
  const msg = errorMessage(error);
  return (
    <p className="error-text" title={msg.detail ?? undefined}>
      {message(msg)}
    </p>
  );
}
