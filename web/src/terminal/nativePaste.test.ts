import { describe, expect, it } from "vitest";

import { nativePasteFiles } from "./nativePaste";

describe("nativePasteFiles", () => {
  it("turns native base64 payloads into File objects", async () => {
    const [file] = nativePasteFiles({
      files: [{ name: "shot.png", type: "image/png", dataBase64: "aGVsbG8=" }],
    });

    expect(file?.name).toBe("shot.png");
    expect(file?.type).toBe("image/png");
    expect(await file?.text()).toBe("hello");
  });

  it("drops malformed entries", () => {
    const files = nativePasteFiles({
      files: [
        { name: "", type: "image/png", dataBase64: "aGVsbG8=" },
        { name: "bad.png", dataBase64: "$$$" },
        { name: "ok.txt", dataBase64: "b2s=" },
      ],
    });

    expect(files.map((file) => file.name)).toEqual(["ok.txt"]);
  });

  it("returns an empty list for non-native events", () => {
    expect(nativePasteFiles(null)).toEqual([]);
    expect(nativePasteFiles({ files: "nope" })).toEqual([]);
  });
});
