import XCTest
@testable import QuotaBar

final class ThresholdTrackerTests: XCTestCase {
    private let thresholds = [80, 90, 95]
    private let reset = Date.reference.addingTimeInterval(3600)

    private func crossed(_ events: [ThresholdEvent]) -> [Int] {
        events.compactMap {
            if case .crossed(_, _, let threshold) = $0 { return threshold }
            return nil
        }
    }

    func testFiresOncePerThreshold() {
        var tracker = ThresholdTracker()
        XCTAssertEqual(tracker.evaluate(makeUsage(fiveHour: 50), thresholds: thresholds, now: .reference), [])
        XCTAssertEqual(crossed(tracker.evaluate(makeUsage(fiveHour: 81), thresholds: thresholds, now: .reference)), [80])
        // Still above 80: no repeat.
        XCTAssertEqual(tracker.evaluate(makeUsage(fiveHour: 84), thresholds: thresholds, now: .reference), [])
        XCTAssertEqual(tracker.evaluate(makeUsage(fiveHour: 84), thresholds: thresholds, now: .reference), [])
        XCTAssertEqual(crossed(tracker.evaluate(makeUsage(fiveHour: 90), thresholds: thresholds, now: .reference)), [90])
        XCTAssertEqual(crossed(tracker.evaluate(makeUsage(fiveHour: 99), thresholds: thresholds, now: .reference)), [95])
        XCTAssertEqual(tracker.evaluate(makeUsage(fiveHour: 100), thresholds: thresholds, now: .reference), [])
    }

    func testJumpAcrossSeveralThresholdsAlertsOnce() {
        var tracker = ThresholdTracker()
        XCTAssertEqual(crossed(tracker.evaluate(makeUsage(fiveHour: 96), thresholds: thresholds, now: .reference)), [95])
        XCTAssertEqual(tracker.evaluate(makeUsage(fiveHour: 97), thresholds: thresholds, now: .reference), [])
    }

    func testNewWindowResetsState() {
        var tracker = ThresholdTracker()
        _ = tracker.evaluate(makeUsage(fiveHour: 92, resetsAt: reset), thresholds: thresholds, now: .reference)

        let nextReset = reset.addingTimeInterval(5 * 3600)
        let later = reset.addingTimeInterval(60)
        let events = tracker.evaluate(makeUsage(fiveHour: 4, resetsAt: nextReset), thresholds: thresholds, now: later)
        XCTAssertEqual(events.count, 1)
        guard case .reset(let provider, let window) = events[0] else { return XCTFail("Expected reset event") }
        XCTAssertEqual(provider, .claude)
        XCTAssertEqual(window.type, .fiveHour)

        // Thresholds fire again in the new window.
        XCTAssertEqual(crossed(tracker.evaluate(makeUsage(fiveHour: 85, resetsAt: nextReset), thresholds: thresholds, now: later)), [80])
    }

    func testExpiredWindowCountsAsReset() {
        var tracker = ThresholdTracker()
        _ = tracker.evaluate(makeUsage(fiveHour: 92, resetsAt: reset), thresholds: thresholds, now: .reference)
        // No new data, but the reset time has passed.
        let events = tracker.evaluate(makeUsage(fiveHour: 92, resetsAt: reset), thresholds: thresholds, now: reset.addingTimeInterval(1))
        XCTAssertEqual(events.count, 1)
        if case .reset = events[0] {} else { XCTFail("Expected reset event") }
        XCTAssertEqual(tracker.evaluate(makeUsage(fiveHour: 92, resetsAt: reset), thresholds: thresholds, now: reset.addingTimeInterval(120)), [])
    }

    func testSlidingResetTimeDoesNotRepeatAlerts() {
        // Some providers move the reset time forward while usage is unchanged.
        var tracker = ThresholdTracker()
        _ = tracker.evaluate(makeUsage(fiveHour: 91, resetsAt: reset), thresholds: thresholds, now: .reference)
        let slid = tracker.evaluate(makeUsage(fiveHour: 91, resetsAt: reset.addingTimeInterval(600)), thresholds: thresholds, now: .reference)
        XCTAssertEqual(slid, [])
    }

    func testSmallDropWithinWindowIsNotAReset() {
        var tracker = ThresholdTracker()
        _ = tracker.evaluate(makeUsage(fiveHour: 91, resetsAt: reset), thresholds: thresholds, now: .reference)
        XCTAssertEqual(tracker.evaluate(makeUsage(fiveHour: 89, resetsAt: reset), thresholds: thresholds, now: .reference), [])
        XCTAssertEqual(tracker.evaluate(makeUsage(fiveHour: 91, resetsAt: reset), thresholds: thresholds, now: .reference), [])
    }

    func testResetWithoutPriorAlertIsSilent() {
        var tracker = ThresholdTracker()
        _ = tracker.evaluate(makeUsage(fiveHour: 40, resetsAt: reset), thresholds: thresholds, now: .reference)
        let events = tracker.evaluate(makeUsage(fiveHour: 1, resetsAt: reset.addingTimeInterval(18000)), thresholds: thresholds, now: reset)
        XCTAssertEqual(events, [])
    }

    func testWindowsAndProvidersAreIndependent() {
        var tracker = ThresholdTracker()
        let claude = tracker.evaluate(makeUsage(.claude, fiveHour: 85, weekly: 91), thresholds: thresholds, now: .reference)
        XCTAssertEqual(crossed(claude), [80, 90])
        let codex = tracker.evaluate(makeUsage(.codex, fiveHour: 85), thresholds: thresholds, now: .reference)
        XCTAssertEqual(crossed(codex), [80])
    }

    func testCustomThresholds() {
        var tracker = ThresholdTracker()
        XCTAssertEqual(tracker.evaluate(makeUsage(fiveHour: 85), thresholds: [95], now: .reference), [])
        XCTAssertEqual(tracker.evaluate(makeUsage(fiveHour: 99), thresholds: [], now: .reference), [])
    }

    func testStateSurvivesEncoding() throws {
        var tracker = ThresholdTracker()
        _ = tracker.evaluate(makeUsage(fiveHour: 85), thresholds: thresholds, now: .reference)
        var restored = try JSONDecoder().decode(ThresholdTracker.self, from: JSONEncoder().encode(tracker))
        XCTAssertEqual(restored.evaluate(makeUsage(fiveHour: 86), thresholds: thresholds, now: .reference), [])
    }

    func testNotificationText() {
        let window = UsageWindow(type: .fiveHour, usedPercentage: 90.4, resetsAt: Date.reference.addingTimeInterval(48 * 60))
        let notification = NotificationComposer.compose(
            .crossed(provider: .claude, window: window, threshold: 90),
            now: .reference
        )
        XCTAssertEqual(notification.title, "Claude usage reached 90%")
        XCTAssertEqual(notification.body, "Your current five-hour usage window is at 90%.\nReset expected in 48 minutes.")

        let reset = NotificationComposer.compose(.reset(provider: .codex, window: window), now: .reference)
        XCTAssertEqual(reset.title, "Codex five-hour window reset")
        XCTAssertNotEqual(reset.identifier, notification.identifier)
    }
}
