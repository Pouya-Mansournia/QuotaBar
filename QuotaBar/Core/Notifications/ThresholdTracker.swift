import Foundation

enum ThresholdEvent: Equatable, Sendable {
    /// Usage crossed an alert threshold for the first time in this window.
    case crossed(provider: AIProvider, window: UsageWindow, threshold: Int)
    /// A window that had triggered an alert has started over.
    case reset(provider: AIProvider, window: UsageWindow)
}

/// Decides when a usage alert is due, so each threshold fires once per quota
/// window. Pure value type; persisted between launches.
struct ThresholdTracker: Codable, Equatable, Sendable {
    private struct WindowState: Codable, Equatable, Sendable {
        var lastPercentage: Double
        var resetsAt: Date?
        var fired: Set<Int>
    }

    /// A fall this large without a known reset time is treated as a new window.
    private static let dropTolerance = 10.0
    /// Reset times that move by less than this are the same window.
    private static let resetTolerance: TimeInterval = 60

    private var states: [String: WindowState] = [:]

    mutating func evaluate(_ usage: ProviderUsage, thresholds: [Int], now: Date) -> [ThresholdEvent] {
        usage.windows.flatMap { evaluate($0, provider: usage.provider, thresholds: thresholds, now: now) }
    }

    private mutating func evaluate(
        _ window: UsageWindow,
        provider: AIProvider,
        thresholds: [Int],
        now: Date
    ) -> [ThresholdEvent] {
        let key = "\(provider.rawValue).\(window.id)"
        let percentage = window.effectivePercentage(at: now)
        let resetsAt = window.isExpired(at: now) ? nil : window.resetsAt
        var state = states[key] ?? WindowState(lastPercentage: 0, resetsAt: resetsAt, fired: [])
        var events: [ThresholdEvent] = []

        if Self.isNewWindow(previous: state, percentage: percentage, resetsAt: resetsAt) {
            if !state.fired.isEmpty {
                events.append(.reset(provider: provider, window: window))
            }
            state.fired = []
        }

        // Announce only the highest threshold crossed, and mark the lower ones
        // as done so a jump from 70% to 96% produces one alert, not three.
        let crossed = thresholds.filter { percentage >= Double($0) }
        if let highest = crossed.max(), !state.fired.contains(highest) {
            events.append(.crossed(provider: provider, window: window, threshold: highest))
        }
        state.fired.formUnion(crossed)

        state.lastPercentage = percentage
        state.resetsAt = resetsAt
        states[key] = state
        return events
    }

    private static func isNewWindow(previous: WindowState, percentage: Double, resetsAt: Date?) -> Bool {
        // Usage only falls when a window rolls over. Requiring a fall also
        // protects against providers whose reset time slides while idle.
        guard percentage < previous.lastPercentage else { return false }
        if let old = previous.resetsAt, let new = resetsAt {
            return new.timeIntervalSince(old) > resetTolerance
        }
        return previous.lastPercentage - percentage >= dropTolerance
    }
}
