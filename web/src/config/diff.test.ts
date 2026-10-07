import { describe, expect, it } from "vitest";

import { diffLines, diffStats, withContext } from "./diff";

function ops(before: string, after: string): string[] {
  return diffLines(before, after).map((line) => `${line.op === "same" ? " " : line.op === "add" ? "+" : "-"}${line.text}`);
}

describe("diffLines", () => {
  it("returns only same lines for equal texts", () => {
    expect(ops("a\nb\n", "a\nb\n")).toEqual([" a", " b"]);
  });

  it("marks a changed line as removed then added", () => {
    expect(ops("a\nb\nc\n", "a\nB\nc\n")).toEqual([" a", "-b", "+B", " c"]);
  });

  it("handles creation and deletion of the whole file", () => {
    expect(ops("", "x\ny")).toEqual(["+x", "+y"]);
    expect(ops("x\n", "")).toEqual(["-x"]);
  });

  it("finds the longest common subsequence in the middle", () => {
    expect(ops("h\na\nb\nc\nt", "h\nb\nc\nd\nt")).toEqual([" h", "-a", " b", " c", "+d", " t"]);
  });

  it("numbers lines on both sides", () => {
    const lines = diffLines("a\nb\n", "a\nx\nb\n");
    expect(lines.map((line) => [line.oldNo, line.newNo])).toEqual([
      [1, 1],
      [null, 2],
      [2, 3],
    ]);
  });

  it("falls back to remove-all/add-all for huge middles without hanging", () => {
    const before = Array.from({ length: 3000 }, (_, i) => `a${String(i)}`).join("\n");
    const after = Array.from({ length: 3000 }, (_, i) => `b${String(i)}`).join("\n");
    expect(diffStats(diffLines(before, after))).toEqual({ added: 3000, removed: 3000 });
  });
});

describe("withContext", () => {
  it("collapses unchanged runs outside the context window", () => {
    const before = Array.from({ length: 20 }, (_, i) => String(i)).join("\n");
    const after = before.replace("10", "ten");
    const rows = withContext(diffLines(before, after), 2);
    expect(rows[0]).toEqual({ op: "skip", count: 8 });
    expect(rows.filter((row) => row.op !== "skip")).toHaveLength(6);
    expect(rows.at(-1)).toEqual({ op: "skip", count: 7 });
  });
});
