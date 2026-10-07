import type { ApiError } from "../api/client";
import type { Health } from "../api/types";
import { useI18n } from "../i18n/context";
import { isLocale, LOCALE_NAMES, LOCALES } from "../i18n/messages";
import { useNotificationPermission } from "../sessions/alerts";
import { LimitBadges } from "./LimitBadges";
import { UpdateButtons } from "./UpdateButtons";

type Tone = "ok" | "warn" | "bad" | "idle";

function Indicator({ tone, label }: { tone: Tone; label: string }) {
  return (
    <span className="indicator">
      <span className={`dot dot-${tone}`} aria-hidden="true" />
      {label}
    </span>
  );
}

interface TopBarProps {
  health: Health | undefined;
  error: ApiError | null;
  onOpenConfig: () => void;
}

export function TopBar({ health, error, onOpenConfig }: TopBarProps) {
  const { t } = useI18n();
  const kanbot = health?.kanbot;
  const runners = kanbot?.runners_online ?? 0;

  let indicators;
  if (error) {
    indicators = <Indicator tone="bad" label={t("status.backend_offline")} />;
  } else if (!health) {
    indicators = <Indicator tone="idle" label={t("status.checking")} />;
  } else if (!kanbot?.reachable) {
    indicators = <Indicator tone="bad" label={t("status.kanbot_offline")} />;
  } else {
    const agents = kanbot.agents?.length ? kanbot.agents.join(", ") : t("status.agents_none");
    indicators = (
      <>
        <Indicator tone="ok" label={t("status.kanbot_online", { version: kanbot.version ?? "?" })} />
        <Indicator tone={runners > 0 ? "ok" : "bad"} label={t("status.runners", { count: runners })} />
        <span className="muted">{agents}</span>
      </>
    );
  }

  return (
    <header className="topbar">
      <h1>{t("app.title")}</h1>
      <div className="indicators">{indicators}</div>
      <button type="button" className="button button-small" title={t("config.open_title")} onClick={onOpenConfig}>
        {t("config.open")}
      </button>
      <LimitBadges />
      <UpdateButtons />
      <NotifyToggle />
      <LocaleSelect />
      {health && (
        <span className="muted topbar-version">
          {t("app.backend_version", { version: health.version })}
        </span>
      )}
    </header>
  );
}

function NotifyToggle() {
  const { t } = useI18n();
  const { permission, request } = useNotificationPermission();
  if (permission === "default") {
    return (
      <button type="button" className="button button-small topbar-notify" title={t("notify.enable_title")} onClick={request}>
        {t("notify.enable")}
      </button>
    );
  }
  if (permission === "denied") {
    return (
      <span className="muted topbar-notify" title={t("notify.denied_title")}>
        {t("notify.denied")}
      </span>
    );
  }
  return null;
}

function LocaleSelect() {
  const { t, locale, setLocale } = useI18n();
  return (
    <select
      className="topbar-locale"
      aria-label={t("app.language")}
      title={t("app.language")}
      value={locale}
      onChange={(event) => {
        if (isLocale(event.target.value)) setLocale(event.target.value);
      }}
    >
      {LOCALES.map((option) => (
        <option key={option} value={option} lang={option}>
          {LOCALE_NAMES[option]}
        </option>
      ))}
    </select>
  );
}
