import { useLimits } from "../api/queries";
import type { AgentLimits, LimitWindow } from "../api/types";
import { useI18n } from "../i18n/context";
import type { LimitBadge } from "../limits/model";
import {
  formatAge,
  formatLimitPercent,
  formatResetDateTime,
  formatResetTime,
  limitBadges,
  limitTone,
} from "../limits/model";

const AGENTS = ["claude", "codex"] as const;

/** TopBar'dagi Claude/Codex rate-limit foizlari — statusline keshi va Codex sessiyasidan. */
export function LimitBadges() {
  const limits = useLimits();
  if (!limits.data) return null;
  return (
    <div className="topbar-limits">
      {AGENTS.map((agent) => (
        <AgentLimits key={agent} agent={agent} item={limits.data[agent]} />
      ))}
    </div>
  );
}

function AgentLimits({ agent, item }: { agent: "claude" | "codex"; item: AgentLimits }) {
  const { t } = useI18n();
  const popoverId = `limits-${agent}`;
  if (!item.available) {
    const titleKey = agent === "claude" ? "limits.unavailable_title_claude" : "limits.unavailable_title_codex";
    return (
      <span className="limit-agent">
        <button type="button" className="indicator limit-trigger muted" aria-describedby={popoverId}>
          {t("limits.unavailable", { agent })}
        </button>
        <span id={popoverId} className="limit-popover" role="tooltip">
          <span className="limit-popover-title">{t("limits.card_title", { agent })}</span>
          <span className="limit-note">{t(titleKey)}</span>
        </span>
      </span>
    );
  }
  const badges = limitBadges(item);
  return (
    <span className="limit-agent">
      {badges.map((badge) => (
        <LimitBadgeView key={badge.kind} agent={agent} badge={badge} stale={item.stale} popoverId={popoverId} />
      ))}
      <span id={popoverId} className="limit-popover" role="tooltip">
        <span className="limit-popover-title">{t("limits.card_title", { agent })}</span>
        <LimitWindowRow label={t("limits.window_five_hour")} window={item.five_hour} />
        <LimitWindowRow label={t("limits.window_weekly")} window={item.weekly} />
        <span className="limit-meta">
          {t("limits.updated", { age: formatAge(item.updated_at) ?? t("limits.unknown") })}
        </span>
        {item.stale && <span className="limit-note">{t("limits.stale_detail")}</span>}
      </span>
    </span>
  );
}

function LimitBadgeView({
  agent,
  badge,
  stale,
  popoverId,
}: {
  agent: string;
  badge: LimitBadge;
  stale: boolean;
  popoverId: string;
}) {
  const { t } = useI18n();
  const percent = Math.floor(badge.window.used_percent);
  const tone = limitTone(badge.window.used_percent);
  const label = t(badge.kind === "five_hour" ? "limits.five_hour" : "limits.weekly", { agent, percent });
  const resetTime = formatResetTime(badge.window.resets_at);
  const parts = [label];
  if (resetTime) parts.push(t("limits.resets_at", { time: resetTime }));
  if (stale) parts.push(t("limits.stale"));
  return (
    <button type="button" className="indicator limit-trigger" title={parts.join(" · ")} aria-describedby={popoverId}>
      <span className={`dot dot-${tone}`} aria-hidden="true" />
      {label}
    </button>
  );
}

function LimitWindowRow({ label, window }: { label: string; window: LimitWindow | null }) {
  const { t } = useI18n();
  if (!window) {
    return (
      <span className="limit-row">
        <span>{label}</span>
        <span className="muted">{t("limits.no_window")}</span>
      </span>
    );
  }
  const tone = limitTone(window.used_percent);
  return (
    <span className="limit-row">
      <span className="limit-row-label">
        <span className={`dot dot-${tone}`} aria-hidden="true" />
        {label}
      </span>
      <span className="limit-row-value">{formatLimitPercent(window.used_percent)}</span>
      <span className="limit-row-reset">
        {t("limits.card_resets", { time: formatResetDateTime(window.resets_at) ?? t("limits.unknown") })}
      </span>
    </span>
  );
}
