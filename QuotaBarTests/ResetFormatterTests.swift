import XCTest
@testable import QuotaBar

final class ResetFormatterTests: XCTestCase {
    private var formatter: ResetFormatter {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        return ResetFormatter(calendar: calendar, locale: Locale(identifier: "en_GB"))
    }

    // Date.reference is Tuesday 2026-10-13 12:00 UTC.
    private func after(_ seconds: TimeInterval) -> Date {
        Date.reference.addingTimeInterval(seconds)
    }

    func testCountdown() {
        XCTAssertEqual(formatter.short(to: after(102 * 60), now: .reference), "1h 42m")
        XCTAssertEqual(formatter.short(to: after(48 * 60 + 30), now: .reference), "48m")
        XCTAssertEqual(formatter.short(to: after(2 * 3600), now: .reference), "2h")
        XCTAssertEqual(formatter.short(to: after(30), now: .reference), "<1m")
        XCTAssertEqual(formatter.short(to: after(-10), now: .reference), "now")
    }

    func testAbsoluteTimes() {
        XCTAssertEqual(formatter.short(to: after(21 * 3600), now: .reference), "Tomorrow 09:00")
        XCTAssertEqual(formatter.short(to: after(3 * 86400 + 5 * 3600), now: .reference), "Fri 17:00")
        XCTAssertEqual(formatter.short(to: after(20 * 86400), now: .reference), "2 Nov")
    }

    func testLaterTodayUsesClockTime() {
        let morning = Date.reference.addingTimeInterval(-11 * 3600) // 01:00
        XCTAssertEqual(formatter.short(to: after(3600), now: morning), "Today 13:00")
    }

    func testResetLabel() {
        XCTAssertEqual(formatter.resetLabel(to: after(102 * 60), now: .reference), "Resets in 1h 42m")
        XCTAssertEqual(formatter.resetLabel(to: after(3 * 86400 + 5 * 3600), now: .reference), "Resets Fri 17:00")
    }

    func testSpokenForm() {
        XCTAssertEqual(formatter.spoken(to: after(102 * 60), now: .reference), "in 1 hour, 42 minutes")
        XCTAssertEqual(formatter.spoken(to: after(48 * 60), now: .reference), "in 48 minutes")
        XCTAssertEqual(formatter.spoken(to: after(20), now: .reference), "in less than a minute")
        XCTAssertEqual(formatter.spoken(to: after(3 * 86400 + 5 * 3600), now: .reference), "on Friday 17:00")
        XCTAssertEqual(formatter.spoken(to: after(21 * 3600), now: .reference), "tomorrow 09:00")
    }

    func testAgo() {
        XCTAssertEqual(formatter.ago(after(-2), now: .reference), "just now")
        XCTAssertEqual(formatter.ago(after(-24), now: .reference), "24 sec ago")
        XCTAssertEqual(formatter.ago(after(-7 * 60), now: .reference), "7 min ago")
        XCTAssertEqual(formatter.ago(after(-3 * 3600), now: .reference), "3h ago")
        XCTAssertEqual(formatter.ago(after(-2 * 86400), now: .reference), "2d ago")
    }

    func testAccessibilityLabel() {
        let window = UsageWindow(type: .fiveHour, usedPercentage: 68.9, resetsAt: after(102 * 60))
        XCTAssertEqual(
            UsageAccessibility.label(provider: .claude, window: window, now: .reference, formatter: formatter),
            "Claude five-hour usage, 68 percent, resets in 1 hour, 42 minutes"
        )
        let expired = UsageWindow(type: .weekly, usedPercentage: 50, resetsAt: after(-60))
        XCTAssertEqual(
            UsageAccessibility.label(provider: .codex, window: expired, now: .reference, formatter: formatter),
            "Codex weekly usage, window has reset, waiting for new data"
        )
    }
}
