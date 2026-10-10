import XCTest
@testable import ClaudeSessions

final class ResetCountdownTests: XCTestCase {
    func testShortestUsefulUnits() {
        let now = 1_000_000.0
        XCTAssertEqual(ResetCountdown.text(until: now + 45 * 60, now: now), "45 daq")
        XCTAssertEqual(ResetCountdown.text(until: now + 2 * 3_600 + 15 * 60 + 30, now: now), "2 soat 15 daq")
        XCTAssertEqual(ResetCountdown.text(until: now + 3 * 3_600, now: now), "3 soat")
        XCTAssertEqual(ResetCountdown.text(until: now + 3 * 86_400 + 4 * 3_600 + 59 * 60, now: now), "3 kun 4 soat")
        XCTAssertEqual(ResetCountdown.text(until: now + 6 * 86_400, now: now), "6 kun")
    }

    func testUnderAMinuteAndPast() {
        let now = 1_000_000.0
        XCTAssertEqual(ResetCountdown.text(until: now + 20, now: now), "1 daq")
        XCTAssertEqual(ResetCountdown.text(until: now, now: now), "hozir")
        XCTAssertEqual(ResetCountdown.text(until: now - 600, now: now), "hozir")
    }
}
