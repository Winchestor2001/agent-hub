import { describe, expect, it } from "vitest";

import { formatSize } from "./model";

describe("formatSize", () => {
  it("1 KB gacha — bayt", () => {
    expect(formatSize(0)).toBe("0 B");
    expect(formatSize(1023)).toBe("1023 B");
  });

  it("kilobayt va megabayt bir kasr xonasi bilan", () => {
    expect(formatSize(1024)).toBe("1.0 KB");
    expect(formatSize(1536)).toBe("1.5 KB");
    expect(formatSize(1024 * 1024)).toBe("1.0 MB");
    expect(formatSize(10 * 1024 * 1024)).toBe("10.0 MB");
  });
});
