import { useLimits } from "../api/queries";
import type { AgentLimits } from "../api/types";
import { useI18n } from "../i18n/context";
import type { LimitBadge } from "../limits/model";
import { formatResetTime, limitBadges, limitTone } from "../limits/model";

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
  if (!item.available) {
    const titleKey = agent === "claude" ? "limits.unavailable_title_claude" : "limits.unavailable_title_codex";
    return (
      <span className="indicator muted" title={t(titleKey)}>
        {t("limits.unavailable", { agent })}
      </span>
    );
  }
  return (
    <>
      {limitBadges(item).map((badge) => (
        <LimitBadgeView key={badge.kind} agent={agent} badge={badge} stale={item.stale} />
      ))}
    </>
  );
}

function LimitBadgeView({ agent, badge, stale }: { agent: string; badge: LimitBadge; stale: boolean }) {
  const { t } = useI18n();
  const percent = Math.floor(badge.window.used_percent);
  const tone = limitTone(badge.window.used_percent);
  const label = t(badge.kind === "five_hour" ? "limits.five_hour" : "limits.weekly", { agent, percent });
  const resetTime = formatResetTime(badge.window.resets_at);
  const parts = [label];
  if (resetTime) parts.push(t("limits.resets_at", { time: resetTime }));
  if (stale) parts.push(t("limits.stale"));
  return (
    <span className="indicator" title={parts.join(" · ")}>
      <span className={`dot dot-${tone}`} aria-hidden="true" />
      {label}
    </span>
  );
}
