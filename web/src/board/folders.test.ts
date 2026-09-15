import { describe, expect, it } from "vitest";

import { addUnique, baseName, filterFolders, tildify } from "./folders";

describe("tildify", () => {
  it("uy papkasini ~ bilan qisqartiradi", () => {
    expect(tildify("/Users/me/my-projects/x", "/Users/me")).toBe("~/my-projects/x");
    expect(tildify("/Users/me", "/Users/me")).toBe("~");
    expect(tildify("/Users/meow/x", "/Users/me")).toBe("/Users/meow/x");
    expect(tildify("/opt/x", "")).toBe("/opt/x");
  });
});

describe("filterFolders", () => {
  const folders = [
    { name: "agent-hub", path: "/h/agent-hub", has_backlog: true },
    { name: "Leveling-web", path: "/h/Leveling-web", has_backlog: false },
  ];

  it("nom bo'yicha katta-kichik harfsiz qidiradi", () => {
    expect(filterFolders(folders, " LEVEL ").map((f) => f.name)).toEqual(["Leveling-web"]);
    expect(filterFolders(folders, "")).toEqual(folders);
  });
});

describe("baseName va addUnique", () => {
  it("oxirgi qismni oladi", () => {
    expect(baseName("/h/my-projects/agent-hub/")).toBe("agent-hub");
    expect(baseName("~")).toBe("~");
  });

  it("takror va bo'sh qiymat qo'shilmaydi", () => {
    expect(addUnique(["/a"], "/a")).toEqual(["/a"]);
    expect(addUnique(["/a"], "  ")).toEqual(["/a"]);
    expect(addUnique(["/a"], "/b")).toEqual(["/a", "/b"]);
  });
});
