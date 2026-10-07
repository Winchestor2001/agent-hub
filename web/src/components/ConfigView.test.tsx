import { QueryClientProvider } from "@tanstack/react-query";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { ConfigEditor } from "./ConfigEditor";
import { ConfigView } from "./ConfigView";
import { Markdown } from "./Markdown";
import { createQueryClient, queryKeys } from "../api/queries";
import type { ConfigFile, ConfigItem, ConfigKind, ConfigScope, ConfigScopesResponse } from "../api/types";
import { I18nContext } from "../i18n/context";
import { createTranslator } from "../i18n/messages";
import type { QueryClient } from "@tanstack/react-query";
import type { ReactNode } from "react";

const scopes: ConfigScope[] = [
  { id: "global", kind: "global", root: "/home/u/.claude", label: "Global", project_id: null, exists: true },
  { id: "project:shop", kind: "project", root: "/w/shop", label: "Shop", project_id: "shop", exists: true },
];

function kind(id: string, extra: Partial<ConfigKind> = {}): ConfigKind {
  return {
    id,
    format: "frontmatter",
    collection: true,
    layout: "file",
    extensions: [".md"],
    scopes: ["global", "project"],
    fixed: {},
    required: [],
    winner: null,
    ...extra,
  };
}

const skills = kind("skills", { layout: "skill", required: ["description"], winner: "global" });
const kinds: ConfigKind[] = [
  kind("mcp", { format: "json", collection: false, extensions: [], scopes: ["project"], fixed: { project: ["mcp"] } }),
  skills,
  kind("claude_local_md", { format: "markdown", collection: false, extensions: [], scopes: ["project"], fixed: { project: ["claude-local-md"] } }),
];

function item(name: string, extra: Partial<ConfigItem> = {}): ConfigItem {
  return { name, path: `skills/${name}/SKILL.md`, exists: true, size: 10, mtime: 1, symlink: false, shadow: [], ...extra };
}

function render(client: QueryClient, node: ReactNode, locale: "uz" | "ru" = "uz"): string {
  return renderToStaticMarkup(
    <QueryClientProvider client={client}>
      <I18nContext value={{ ...createTranslator(locale), setLocale: () => undefined }}>{node}</I18nContext>
    </QueryClientProvider>,
  );
}

function seeded(): QueryClient {
  const client = createQueryClient();
  client.setQueryData<ConfigScopesResponse>(queryKeys.configScopes, { scopes, kinds });
  client.setQueryData(queryKeys.configItems("global", "skills"), {
    items: [item("deploy", { shadow: [{ scope: "project:shop", winner: "this" }] }), item("review")],
    skipped: ["Bad_Name"],
  });
  return client;
}

describe("ConfigView", () => {
  it("shows scopes, kinds for the scope and a searchable item list", () => {
    const html = render(seeded(), <ConfigView initialScope="global" initialKind="skills" onClose={() => undefined} />);
    expect(html).toContain("Global (~/.claude)");
    expect(html).toContain("<optgroup label=\"Loyihalar\"><option value=\"project:shop\">Shop</option>");
    // MCP faqat loyiha qamrovida — globalda o'chirilgan.
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*title="Bu tur faqat shu qamrovlarda: project"/);
    expect(html).toContain('placeholder="Qidirish (2 ta)…"');
    expect(html).toContain("deploy");
    expect(html).toContain(">ustun<");
    expect(html).toContain("Nomi qoidaga mos kelmagan 1 ta element ko&#x27;rsatilmadi");
    expect(html).toContain("Chapdagi ro&#x27;yxatdan element tanlang");
  });

  it("is translated to Russian", () => {
    const html = render(seeded(), <ConfigView initialScope="global" initialKind="skills" onClose={() => undefined} />, "ru");
    expect(html).toContain("Конфигурация Claude");
    expect(html).toContain('placeholder="Поиск (всего: 2)…"');
  });
});

describe("ConfigEditor", () => {
  function file(extra: Partial<ConfigFile>): ConfigFile {
    return {
      scope: "project:shop",
      kind: "skills",
      name: "deploy",
      path: ".claude/skills/deploy/SKILL.md",
      abs_path: "/w/shop/.claude/skills/deploy/SKILL.md",
      exists: true,
      content: "---\ndescription: d\n---\n",
      etag: "e".repeat(64),
      mode: "644",
      warnings: [],
      ...extra,
    };
  }

  it("warns when a project item is shadowed by the global one", () => {
    const client = createQueryClient();
    client.setQueryData(queryKeys.configFile("project:shop", "skills", "deploy"), file({}));
    const html = render(
      client,
      <ConfigEditor
        scope={scopes[1] as ConfigScope}
        kind={skills}
        scopes={scopes}
        name="deploy"
        item={item("deploy", { shadow: [{ scope: "global", winner: "other" }] })}
        onSaved={() => undefined}
        onDeleted={() => undefined}
        onDirtyChange={() => undefined}
      />,
    );
    expect(html).toContain("Global da bir xil nomli element bor va u ustun");
    expect(html).toContain("/w/shop/.claude/skills/deploy/SKILL.md");
    expect(html).toContain(">O&#x27;chirish<");
  });

  it("warns when CLAUDE.local.md is not git-ignored", () => {
    const client = createQueryClient();
    const local = kinds[2] as ConfigKind;
    client.setQueryData(
      queryKeys.configFile("project:shop", "claude_local_md", "claude-local-md"),
      file({ kind: "claude_local_md", name: "claude-local-md", warnings: ["local_not_ignored"] }),
    );
    const html = render(
      client,
      <ConfigEditor
        scope={scopes[1] as ConfigScope}
        kind={local}
        scopes={scopes}
        name="claude-local-md"
        item={undefined}
        onSaved={() => undefined}
        onDeleted={() => undefined}
        onDirtyChange={() => undefined}
      />,
    );
    expect(html).toContain("CLAUDE.local.md .gitignore&#x27;da emas");
  });

  it("offers a name field for a new collection item", () => {
    const html = render(
      createQueryClient(),
      <ConfigEditor
        scope={scopes[0] as ConfigScope}
        kind={skills}
        scopes={scopes}
        name={null}
        item={undefined}
        onSaved={() => undefined}
        onDeleted={() => undefined}
        onDirtyChange={() => undefined}
      />,
    );
    expect(html).toContain("yangi fayl");
    expect(html).toContain(">Yaratish…<");
    expect(html).toContain("Fayl yuklash");
  });
});

describe("Markdown", () => {
  it("renders guide blocks as elements and never as raw HTML", () => {
    const html = renderToStaticMarkup(
      <Markdown source={"# Sarlavha\n\n**Qalin** va `kod` <script>x</script>\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n[docs](https://code.claude.com) [bad](javascript:alert(1))"} />,
    );
    expect(html).toContain("<h3>Sarlavha</h3>");
    expect(html).toContain("<strong>Qalin</strong>");
    expect(html).toContain("<code>kod</code>");
    expect(html).toContain("&lt;script&gt;");
    expect(html).toContain("<td>1</td>");
    expect(html).toContain('href="https://code.claude.com"');
    expect(html).not.toContain('href="javascript:');
    expect(html).toContain("[bad](javascript:alert(1))");
  });
});
