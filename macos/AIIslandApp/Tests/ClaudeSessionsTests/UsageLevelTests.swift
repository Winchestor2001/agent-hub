import XCTest
@testable import ClaudeSessions

final class UsageLevelTests: XCTestCase {
    func testThresholdsAreSeventyAndNinety() {
        XCTAssertEqual(UsageLevel.warningThreshold, 70)
        XCTAssertEqual(UsageLevel.criticalThreshold, 90)
    }

    func testLevelBoundaries() {
        XCTAssertEqual(UsageLevel(percent: 0), .normal)
        XCTAssertEqual(UsageLevel(percent: 50), .normal)
        XCTAssertEqual(UsageLevel(percent: 69.9), .normal)
        XCTAssertEqual(UsageLevel(percent: 70), .warning)
        XCTAssertEqual(UsageLevel(percent: 80), .warning)
        XCTAssertEqual(UsageLevel(percent: 89.9), .warning)
        XCTAssertEqual(UsageLevel(percent: 90), .critical)
        XCTAssertEqual(UsageLevel(percent: 95), .critical)
        XCTAssertEqual(UsageLevel(percent: 120), .critical)
    }
}
