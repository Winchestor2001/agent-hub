import XCTest
import Foundation
@testable import ClaudeSessions

final class ClaudeRateLimitsTests: XCTestCase {
    let now: Double = 1_800_000_000
    var file: URL!

    override func setUpWithError() throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("rate-limits-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file)
    }

    private func write(_ text: String) throws { try Data(text.utf8).write(to: file) }

    func testReadsBothWindows() throws {
        try write(#"{"captured_at":\#(Int(now) - 60),"rate_limits":{"five_hour":{"used_percentage":3,"resets_at":\#(Int(now) + 3600)},"seven_day":{"used_percentage":7.5,"resets_at":\#(Int(now) + 86400)}}}"#)
        let limits = try XCTUnwrap(ClaudeRateLimitCache.read(file, now: now))
        XCTAssertEqual(limits.fiveHour, ClaudeRateLimitWindow(usedPercent: 3, resetsAt: now + 3600))
        XCTAssertEqual(limits.sevenDay?.usedPercent, 7.5)
        XCTAssertEqual(limits.maxPercent, 7.5)
        XCTAssertFalse(limits.stale)
    }

    func testMissingBrokenOrEmptyCacheIsUnavailable() throws {
        XCTAssertNil(ClaudeRateLimitCache.read(file, now: now))
        try write("not json")
        XCTAssertNil(ClaudeRateLimitCache.read(file, now: now))
        try write(#"{"captured_at":\#(Int(now)),"rate_limits":{}}"#)
        XCTAssertNil(ClaudeRateLimitCache.read(file, now: now))
    }

    func testOutOfRangePercentIsDropped() throws {
        try write(#"{"captured_at":\#(Int(now)),"rate_limits":{"five_hour":{"used_percentage":140},"seven_day":{"used_percentage":"9"}}}"#)
        XCTAssertNil(ClaudeRateLimitCache.read(file, now: now))
    }

    func testExpiredWindowIsNotShown() throws {
        try write(#"{"captured_at":\#(Int(now) - 7200),"rate_limits":{"five_hour":{"used_percentage":90,"resets_at":\#(Int(now) - 1)},"seven_day":{"used_percentage":20,"resets_at":\#(Int(now) + 86400)}}}"#)
        let limits = try XCTUnwrap(ClaudeRateLimitCache.read(file, now: now))
        XCTAssertNil(limits.fiveHour)
        XCTAssertEqual(limits.maxPercent, 20)
    }

    func testOldOrUndatedSnapshotIsStale() throws {
        try write(#"{"captured_at":\#(Int(now) - 21 * 60),"rate_limits":{"five_hour":{"used_percentage":5}}}"#)
        XCTAssertEqual(ClaudeRateLimitCache.read(file, now: now)?.stale, true)
        try write(#"{"rate_limits":{"five_hour":{"used_percentage":5}}}"#)
        XCTAssertEqual(ClaudeRateLimitCache.read(file, now: now)?.stale, true)
        try write(#"{"captured_at":\#(Int(now) - 19 * 60),"rate_limits":{"five_hour":{"used_percentage":5}}}"#)
        XCTAssertEqual(ClaudeRateLimitCache.read(file, now: now)?.stale, false)
    }
}
