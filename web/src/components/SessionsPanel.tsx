import type { ReactNode } from "react";

import type { ApiError } from "../api/client";
import { useLiveSessions, usePastSessions } from "../api/queries";
import { useI18n } from "../i18n/context";
import { ErrorText } from "./ErrorText";
import { Panel } from "./Panel";

interface Row {
  key: string;
  title: string;
  meta: string;
}

function Section({
  title,
  rows,
  error,
}: {
  title: string;
  rows: Row[] | undefined;
  error: ApiError | null;
}) {
  const { t } = useI18n();
  let body: ReactNode;
  if (error?.code === "kanbot_unavailable") {
    body = <p className="muted">{t("sessions.unavailable")}</p>;
  } else if (error && !rows) {
    body = <ErrorText error={error} />;
  } else if (!rows) {
    body = <p className="muted">{t("sessions.loading")}</p>;
  } else if (rows.length === 0) {
    body = <p className="muted">{t("sessions.none")}</p>;
  } else {
    body = (
      <ul className="list">
        {rows.map((row) => (
          <li key={row.key} className="list-item list-item-static">
            <span className="list-item-title">{row.title}</span>
            <span className="muted">{row.meta}</span>
          </li>
        ))}
      </ul>
    );
  }
  return (
    <div className="section">
      <h3 className="section-title">
        {title}
        {rows && !error && <span className="count">{rows.length}</span>}
      </h3>
      {body}
    </div>
  );
}

export function SessionsPanel() {
  const { t } = useI18n();
  const live = useLiveSessions();
  const past = usePastSessions();

  const liveRows = live.data?.map((pane) => ({
    key: pane.id,
    title: pane.title || pane.agent,
    meta: `${pane.agent} · ${pane.state}${pane.approximate ? " ≈" : ""}`,
  }));
  const pastRows = past.data?.map((session) => ({
    key: `${session.agent}:${session.session_id}`,
    title: session.title || session.name || session.session_id,
    meta: session.agent,
  }));

  return (
    <Panel title={t("panel.sessions")} className="panel-sessions">
      <Section title={t("sessions.live")} rows={liveRows} error={live.error} />
      <Section title={t("sessions.past")} rows={pastRows} error={past.error} />
    </Panel>
  );
}
