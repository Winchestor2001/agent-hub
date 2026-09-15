import { describe, expect, it } from "vitest";

import { closeMessage, decodeBase64, parseServerMessage, QUICK_KEYS, terminalUrl } from "./protocol";

describe("terminalUrl", () => {
  it("uses ws/wss, escapes pane id and adds size", () => {
    expect(terminalUrl({ protocol: "http:", host: "127.0.0.1:8700" }, "p1", { rows: 30, cols: 100 })).toBe(
      "ws://127.0.0.1:8700/ws/panes/p1?rows=30&cols=100",
    );
    expect(terminalUrl({ protocol: "https:", host: "hub" }, "a/b", null)).toBe("wss://hub/ws/panes/a%2Fb");
  });
});

describe("parseServerMessage", () => {
  it("accepts data and error messages", () => {
    expect(parseServerMessage('{"type":"data","data":"aGk=","replay":true}')).toEqual({
      type: "data",
      data: "aGk=",
      replay: true,
    });
    expect(parseServerMessage('{"type":"data","data":"aGk="}')).toEqual({ type: "data", data: "aGk=", replay: false });
    expect(parseServerMessage('{"type":"error","code":"invalid_keys"}')).toEqual({
      type: "error",
      code: "invalid_keys",
    });
  });

  it("ignores anything else", () => {
    for (const raw of ["nope", "null", "[]", '{"type":"data","data":1}', '{"type":"hello"}']) {
      expect(parseServerMessage(raw)).toBeNull();
    }
    expect(parseServerMessage(new ArrayBuffer(2))).toBeNull();
  });
});

describe("decodeBase64", () => {
  it("returns raw bytes (not UTF-16 text)", () => {
    // "ё\x1b[0m" UTF-8 baytlari: xterm o'zi dekodlaydi.
    expect(Array.from(decodeBase64("0ZEbWzBt"))).toEqual([0xd1, 0x91, 0x1b, 0x5b, 0x30, 0x6d]);
  });
});

describe("closeMessage", () => {
  it("maps backend close reasons", () => {
    expect(closeMessage("pane_gone")).toEqual({ key: "terminal.closed_gone", retry: false });
    expect(closeMessage("kanbot_unavailable")).toEqual({ key: "terminal.closed_kanbot", retry: true });
    expect(closeMessage("slow_client").retry).toBe(true);
    expect(closeMessage("bad_request").retry).toBe(false);
    expect(closeMessage("")).toEqual({ key: "terminal.closed", retry: true });
  });
});

it("quick keys use KanBot key names", () => {
  expect(QUICK_KEYS.map((k) => k.keys)).toEqual([["Enter"], ["y"], ["n"], ["Escape"], ["C-c"]]);
});
