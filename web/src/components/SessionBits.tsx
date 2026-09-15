import { isMessageKey } from "../i18n/messages";
import { useI18n } from "../i18n/context";
import { elapsed } from "../sessions/model";
import { useNow } from "../sessions/useNow";

/** Effective holat: rangli nuqta + matn; ekrandan taxminiy aniqlangan bo'lsa «≈». */
export function StateBadge({ state, approximate = false }: { state: string; approximate?: boolean }) {
  const { t, message } = useI18n();
  const key = `state.${state}`;
  return (
    <span
      className={`state state-${state}`}
      title={approximate ? t("sessions.approximate") : undefined}
    >
      <span className="dot" aria-hidden="true" />
      {isMessageKey(key) ? message({ key }) : state}
      {approximate && " ≈"}
    </span>
  );
}

export function Ago({ timestamp }: { timestamp: number | null }) {
  const { t, locale } = useI18n();
  const now = useNow();
  if (timestamp === null) return null;
  const { unit, count } = elapsed(timestamp, now);
  return (
    <time className="muted ago" dateTime={new Date(timestamp * 1000).toISOString()} title={new Date(timestamp * 1000).toLocaleString(locale)}>
      {t(`time.${unit}`, { count })}
    </time>
  );
}
