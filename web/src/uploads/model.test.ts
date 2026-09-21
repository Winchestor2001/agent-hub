import { describe, expect, it } from "vitest";

import { formatSize, paneUploadDir, panePastePath } from "./model";

describe("paneUploadDir", () => {
  const dirs = ["/w/app", "/w/app-web", "/w/app/packages/ui"];

  it("pane papkasi loyiha papkasining o'zi yoki ichki papkasi bo'lsa shu papka", () => {
    expect(paneUploadDir("/w/app", dirs)).toBe("/w/app");
    expect(paneUploadDir("/w/app/src/deep", dirs)).toBe("/w/app");
    expect(paneUploadDir("/w/app-web/src", dirs)).toBe("/w/app-web");
  });

  it("bir nechtasiga mos kelsa — eng ichkisi", () => {
    expect(paneUploadDir("/w/app/packages/ui/src", dirs)).toBe("/w/app/packages/ui");
  });

  it("segment bo'yicha solishtiradi va oxirgi `/` ni e'tiborsiz qoldiradi", () => {
    expect(paneUploadDir("/w/application", dirs)).toBeNull();
    expect(paneUploadDir("/w/app/", ["/w/app/"])).toBe("/w/app/");
  });

  it("hech biriga tegishli bo'lmasa yoki pane papkasi bo'sh bo'lsa null", () => {
    expect(paneUploadDir("/elsewhere", dirs)).toBeNull();
    expect(paneUploadDir("", dirs)).toBeNull();
    expect(paneUploadDir("/w/app", [])).toBeNull();
  });
});

describe("panePastePath", () => {
  const stored = ".agent-hub/uploads/inbox/20260921-shot.png";

  it("pane papkasi yuklash papkasi bilan bir xil — nisbiy yo'l", () => {
    expect(panePastePath("/w/app", "/w/app", stored)).toBe(stored);
    expect(panePastePath("/w/app/", "/w/app", stored)).toBe(stored);
  });

  it("pane ichki papkada — absolyut yo'l", () => {
    expect(panePastePath("/w/app/src", "/w/app", stored)).toBe(`/w/app/${stored}`);
  });

  it("bo'shliq va maxsus belgilar backslash bilan escape qilinadi", () => {
    expect(panePastePath("/w/My App/src", "/w/My App", stored)).toBe(`/w/My\\ App/${stored}`);
    expect(panePastePath("/w/a&b(1)", "/w/a&b(1)", "x.png")).toBe("x.png");
    expect(panePastePath("/w/a&b(1)/s", "/w/a&b(1)", "x.png")).toBe("/w/a\\&b\\(1\\)/x.png");
  });
});

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
