import { describe, expect, it } from "vitest";

import { ALL_TOPICS, keysForTopics, parseTopics } from "./events";
import { queryKeys } from "./queries";

describe("parseTopics", () => {
  it("keeps known topics only", () => {
    expect(parseTopics('{"topics":["health","sessions"]}')).toEqual(["health", "sessions"]);
    expect(parseTopics('{"topics":["sessions","cards",5]}')).toEqual(["sessions"]);
  });

  it("ignores malformed data", () => {
    expect(parseTopics("not json")).toEqual([]);
    expect(parseTopics("null")).toEqual([]);
    expect(parseTopics('{"topics":"sessions"}')).toEqual([]);
    expect(parseTopics("{}")).toEqual([]);
  });
});

describe("keysForTopics", () => {
  it("maps pane changes to sessions, project counters, board and task detail", () => {
    expect(keysForTopics(["sessions"])).toEqual([["sessions"], queryKeys.projects, ["board"], ["task"]]);
  });

  it("maps runner changes to health", () => {
    expect(keysForTopics(["health"])).toEqual([queryKeys.health]);
  });

  it("deduplicates topics and covers every query prefix for a full refresh", () => {
    expect(keysForTopics(["health", "health"])).toEqual([queryKeys.health]);
    const keys = keysForTopics(ALL_TOPICS);
    for (const key of [
      queryKeys.liveSessions,
      queryKeys.pastSessions("p"),
      queryKeys.projects,
      queryKeys.board("p"),
      queryKeys.task("p", "TASK-1"),
      queryKeys.health,
    ]) {
      expect(keys.some((prefix) => prefix.every((part, i) => key[i] === part))).toBe(true);
    }
  });
});
