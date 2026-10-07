import { QueryClientProvider } from "@tanstack/react-query";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { LimitBadges } from "./LimitBadges";
import { createQueryClient, queryKeys } from "../api/queries";
import type { LimitsResponse } from "../api/types";
import { I18nContext } from "../i18n/context";
import { createTranslator } from "../i18n/messages";

function renderLimits(data: LimitsResponse): string {
  const client = createQueryClient();
  client.setQueryData(queryKeys.limits, data);
  return renderToStaticMarkup(
    <QueryClientProvider client={client}>
      <I18nContext value={{ ...createTranslator("uz"), setLocale: () => undefined }}>
        <LimitBadges />
      </I18nContext>
    </QueryClientProvider>,
  );
}

describe("LimitBadges", () => {
  it("renders one compact primary badge per agent with a detailed popover", () => {
    const html = renderLimits({
      claude: {
        agent: "claude",
        available: true,
        five_hour: { used_percent: 18.9, resets_at: 1_800_000_000 },
        weekly: { used_percent: 42.2, resets_at: 1_800_360_000 },
        updated_at: 1_799_999_700,
        stale: true,
      },
      codex: {
        agent: "codex",
        available: true,
        five_hour: { used_percent: 89.1, resets_at: 1_800_000_000 },
        weekly: { used_percent: 14.8, resets_at: 1_800_360_000 },
        updated_at: 1_799_999_990,
        stale: false,
      },
    });

    expect(html).toContain("aria-describedby=\"limits-claude\"");
    expect(html).toContain("aria-describedby=\"limits-codex\"");
    expect(html).toContain("role=\"tooltip\"");
    expect(html).toContain("claude 7k 42%");
    expect(html).toContain("codex 5s 89%");
    expect(html).not.toContain("claude 5s 18%");
    expect(html).not.toContain("codex 7k 14%");
    expect(html).toContain("5 soatlik limit");
    expect(html).toContain("7 kunlik limit");
    expect(html).toContain("reset:");
    expect(html).toContain("yangilangan:");
    expect(html).toContain("Ma&#x27;lumot eski bo&#x27;lishi mumkin");
  });

  it("renders an unavailable card when agent limit data is missing", () => {
    const html = renderLimits({
      claude: {
        agent: "claude",
        available: false,
        five_hour: null,
        weekly: null,
        updated_at: null,
        stale: false,
      },
      codex: {
        agent: "codex",
        available: true,
        five_hour: null,
        weekly: { used_percent: 14, resets_at: null },
        updated_at: null,
        stale: false,
      },
    });

    expect(html).toContain("claude: ma&#x27;lumot yo&#x27;q");
    expect(html).toContain("Claude limitini ko&#x27;rish uchun");
    expect(html).toContain("5 soatlik limit");
    expect(html).toContain("ma&#x27;lumot yo&#x27;q");
    expect(html).toContain("7 kunlik limit");
    expect(html).toContain("codex 7k 14%");
  });
});
