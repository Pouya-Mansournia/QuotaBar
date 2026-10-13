import XCTest
@testable import QuotaBar

final class UsageModelTests: XCTestCase {
    func testPercentageNormalization() {
        XCTAssertEqual(UsageMath.normalizedPercentage(68.4), 68.4)
        XCTAssertEqual(UsageMath.normalizedPercentage(0), 0)
        XCTAssertEqual(UsageMath.normalizedPercentage(-5), 0)
        XCTAssertEqual(UsageMath.normalizedPercentage(140), 100)
        XCTAssertNil(UsageMath.normalizedPercentage(nil))
        XCTAssertNil(UsageMath.normalizedPercentage(.nan))
        XCTAssertNil(UsageMath.normalizedPercentage(.infinity))
    }

    func testDisplayPercentRoundsDown() {
        XCTAssertEqual(UsageMath.displayPercent(89.9), 89)
        XCTAssertEqual(UsageMath.displayPercent(90), 90)
        XCTAssertEqual(UsageMath.displayPercent(0.4), 0)
    }

    func testUsageLevels() {
        XCTAssertEqual(UsageLevel(percentage: 0), .normal)
        XCTAssertEqual(UsageLevel(percentage: 69.9), .normal)
        XCTAssertEqual(UsageLevel(percentage: 70), .warning)
        XCTAssertEqual(UsageLevel(percentage: 84.9), .warning)
        XCTAssertEqual(UsageLevel(percentage: 85), .high)
        XCTAssertEqual(UsageLevel(percentage: 94.9), .high)
        XCTAssertEqual(UsageLevel(percentage: 95), .critical)
        XCTAssertEqual(UsageLevel(percentage: 100), .critical)
    }

    func testExpiredWindowReportsZero() {
        let window = UsageWindow(type: .fiveHour, usedPercentage: 80, resetsAt: .reference)
        XCTAssertFalse(window.isExpired(at: Date.reference.addingTimeInterval(-1)))
        XCTAssertEqual(window.effectivePercentage(at: Date.reference.addingTimeInterval(-1)), 80)
        XCTAssertTrue(window.isExpired(at: .reference))
        XCTAssertEqual(window.effectivePercentage(at: .reference), 0)
        let open = UsageWindow(type: .fiveHour, usedPercentage: 80, resetsAt: nil)
        XCTAssertFalse(open.isExpired(at: .distantFuture))
    }

    func testPrimaryWindowPrefersShortWindow() {
        XCTAssertEqual(makeUsage(fiveHour: 10, weekly: 90).primaryWindow?.type, .fiveHour)
        let weeklyOnly = ProviderUsage(
            provider: .codex,
            windows: [UsageWindow(type: .weekly, usedPercentage: 5, resetsAt: nil)],
            updatedAt: .reference
        )
        XCTAssertEqual(weeklyOnly.primaryWindow?.type, .weekly)
    }

    // MARK: Reset date parsing

    private func decodeDate(_ json: String) throws -> Date {
        try JSONDecoder().decode([LenientDate].self, from: Data("[\(json)]".utf8))[0].value
    }

    func testResetDateParsing() throws {
        let expected = Date(timeIntervalSince1970: 1_738_425_600)
        XCTAssertEqual(try decodeDate("1738425600"), expected)
        XCTAssertEqual(try decodeDate("1738425600.0"), expected)
        XCTAssertEqual(try decodeDate("1738425600000"), expected, "Milliseconds")
        XCTAssertEqual(try decodeDate("\"1738425600\""), expected)
        XCTAssertEqual(try decodeDate("\"2025-02-01T16:00:00Z\""), expected)
        XCTAssertEqual(try decodeDate("\"2025-02-01T16:00:00.000Z\""), expected)
        XCTAssertEqual(try decodeDate("\"2025-02-01T17:00:00+01:00\""), expected)
    }

    func testInvalidResetDatesAreRejected() {
        XCTAssertThrowsError(try decodeDate("\"next friday\""))
        XCTAssertThrowsError(try decodeDate("0"))
        XCTAssertThrowsError(try decodeDate("-5"))
        XCTAssertThrowsError(try decodeDate("true"))
    }
}
