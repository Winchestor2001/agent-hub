import XCTest
@testable import ClaudeSessions

final class ResetCountdownTests: XCTestCase {
    func testShortestUsefulUnits() {
        let now = 1_000_000.0
        XCTAssertEqual(ResetCountdown.text(until: now + 45 * 60, now: now), "45m")
        XCTAssertEqual(ResetCountdown.text(until: now + 2 * 3_600 + 15 * 60 + 30, now: now), "2h 15m")
        XCTAssertEqual(ResetCountdown.text(until: now + 3 * 3_600, now: now), "3h")
        XCTAssertEqual(ResetCountdown.text(until: now + 3 * 86_400 + 4 * 3_600 + 59 * 60, now: now), "3d 4h")
        XCTAssertEqual(ResetCountdown.text(until: now + 6 * 86_400, now: now), "6d")
    }

    func testUnderAMinuteAndPast() {
        let now = 1_000_000.0
        XCTAssertEqual(ResetCountdown.text(until: now + 20, now: now), "1m")
        XCTAssertEqual(ResetCountdown.text(until: now, now: now), "now")
        XCTAssertEqual(ResetCountdown.text(until: now - 600, now: now), "now")
    }
}
