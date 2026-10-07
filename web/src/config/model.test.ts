import { describe, expect, it } from "vitest";

import { filterItems, firstKind, kindFits, nameFromFile, nameProblem, orderKinds } from "./model";
import { parseMarkdown } from "./markdown";
import type { ConfigItem, ConfigKind, ConfigScope } from "../api/types";

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

const skills = kind("skills", { layout: "skill" });
const hooks = kind("hooks", { format: "script", extensions: [".sh", ".js", ".mjs", ".cjs", ".py"] });
const mcp = kind("mcp", { format: "json", collection: false, extensions: [], scopes: ["project"], fixed: { project: ["mcp"] } });

const globalScope: ConfigScope = {
  id: "global",
  kind: "global",
  root: "/home/u/.claude",
  label: "Global",
  project_id: null,
  exists: true,
};

function item(name: string, path = `skills/${name}/SKILL.md`): ConfigItem {
  return { name, path, exists: true, size: 1, mtime: 1, symlink: false, shadow: [] };
}

describe("filterItems", () => {
  const many = Array.from({ length: 120 }, (_, i) => item(`skill-${String(i)}`));

  it("searches 90+ items by name, case-insensitively", () => {
    expect(filterItems(many, "SKILL-11")).toHaveLength(11); // 11, 110..119
    expect(filterItems(many, "  ")).toHaveLength(120);
  });

  it("also matches the path", () => {
    expect(filterItems([item("a", "rules/frontend/a.md")], "frontend")).toHaveLength(1);
  });
});

describe("nameProblem", () => {
  it("accepts catalog names and rejects bad ones", () => {
    expect(nameProblem(skills, "db-migrate")).toBeNull();
    expect(nameProblem(skills, "")).toBe("empty");
    expect(nameProblem(skills, "Deploy")).toBe("invalid");
    expect(nameProblem(skills, "../x")).toBe("invalid");
  });

  it("requires a known extension for hooks", () => {
    expect(nameProblem(hooks, "guard.sh")).toBeNull();
    expect(nameProblem(hooks, "guard")).toBe("extension");
    expect(nameProblem(hooks, "guard.exe")).toBe("extension");
    expect(nameProblem(hooks, "Bad.sh")).toBe("invalid");
  });

  it("does not check fixed kinds", () => {
    expect(nameProblem(mcp, "")).toBeNull();
  });
});

describe("nameFromFile", () => {
  it("derives a slug from an uploaded file", () => {
    expect(nameFromFile(kind("rules"), "Code Style.md")).toBe("code-style");
    expect(nameFromFile(hooks, "Guard.SH")).toBe("guard.sh");
    expect(nameFromFile(skills, "SKILL.md")).toBe("");
  });
});

describe("kinds", () => {
  it("orders kinds and picks the first one that fits the scope", () => {
    expect(orderKinds([skills, mcp, kind("claude_md")]).map((k) => k.id)).toEqual(["claude_md", "mcp", "skills"]);
    expect(kindFits(mcp, globalScope)).toBe(false);
    expect(firstKind([mcp, skills], globalScope)).toBe("skills");
  });
});

describe("parseMarkdown", () => {
  it("parses the block types used by the guides", () => {
    const blocks = parseMarkdown(
      [
        "# Skill'lar",
        "",
        "Matn `kod` bilan",
        "davomi.",
        "",
        "```markdown",
        "---",
        "name: x",
        "```",
        "",
        "- bir",
        "  - ichki",
        "1. birinchi",
        "",
        "| Tur | Global |",
        "| --- | --- |",
        "| Skill | `~/.claude/skills` |",
      ].join("\n"),
    );
    expect(blocks.map((block) => block.type)).toEqual(["heading", "paragraph", "code", "list", "list", "table"]);
    expect(blocks[1]).toEqual({ type: "paragraph", text: "Matn `kod` bilan davomi." });
    expect(blocks[2]).toEqual({ type: "code", lang: "markdown", text: "---\nname: x" });
    expect(blocks[3]).toEqual({
      type: "list",
      ordered: false,
      items: [
        { text: "bir", depth: 0 },
        { text: "ichki", depth: 1 },
      ],
    });
    expect(blocks[5]).toEqual({ type: "table", head: ["Tur", "Global"], rows: [["Skill", "`~/.claude/skills`"]] });
  });
});
