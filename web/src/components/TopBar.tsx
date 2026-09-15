import type { ApiError } from "../api/client";
import type { Health } from "../api/types";
import { useI18n } from "../i18n/context";

type Tone = "ok" | "warn" | "bad" | "idle";

function Indicator({ tone, label }: { tone: Tone; label: string }) {
  return (
    <span className="indicator">
      <span className={`dot dot-${tone}`} aria-hidden="true" />
      {label}
    </span>
  );
}

export function TopBar({ health, error }: { health: Health | undefined; error: ApiError | null }) {
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
      {health && (
        <span className="muted topbar-version">
          {t("app.backend_version", { version: health.version })}
        </span>
      )}
    </header>
  );
}
