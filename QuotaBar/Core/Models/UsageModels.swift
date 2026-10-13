import Foundation

enum UsageWindowType: String, Codable, CaseIterable, Sendable {
    case session
    case fiveHour
    case daily
    case weekly
    case monthly
    case apiBudget
    case custom

    var displayName: String {
        switch self {
        case .session: "Session"
        case .fiveHour: "5-Hour Window"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .apiBudget: "Spend Limit"
        case .custom: "Usage"
        }
    }

    var shortName: String {
        switch self {
        case .session: "Session"
        case .fiveHour: "5h"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .apiBudget: "Spend"
        case .custom: "Usage"
        }
    }

    /// Spoken form used in accessibility labels and notifications.
    var spokenName: String {
        switch self {
        case .session: "session"
        case .fiveHour: "five-hour"
        case .daily: "daily"
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .apiBudget: "spend limit"
        case .custom: "usage"
        }
    }
}

struct UsageWindow: Codable, Hashable, Sendable, Identifiable {
    let type: UsageWindowType
    /// Normalized to 0...100.
    let usedPercentage: Double
    let resetsAt: Date?
    var consumedTokens: Int?
    var tokenLimit: Int?
    var estimatedCost: Double?
    /// Overrides the type's name for `custom` windows.
    var label: String?

    var id: String { type.rawValue + (label ?? "") }

    var displayName: String { label ?? type.displayName }
    var shortName: String { label ?? type.shortName }

    /// A window whose reset time has passed no longer describes current usage:
    /// the quota has rolled over and nothing has been reported since.
    func isExpired(at now: Date) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }

    /// The percentage to display: zero once the window has rolled over.
    func effectivePercentage(at now: Date) -> Double {
        isExpired(at: now) ? 0 : usedPercentage
    }
}

struct ProviderUsage: Codable, Hashable, Sendable {
    let provider: AIProvider
    let windows: [UsageWindow]
    /// When the provider measured these values — not when QuotaBar read them.
    let updatedAt: Date
    var planName: String?

    func window(_ type: UsageWindowType) -> UsageWindow? {
        windows.first { $0.type == type }
    }

    /// The window shown in the menu bar title: the short rolling window when
    /// the provider has one, otherwise whatever it reports first.
    var primaryWindow: UsageWindow? {
        window(.fiveHour) ?? window(.session) ?? windows.first
    }
}

enum UsageLevel: Int, Comparable, Sendable {
    case normal
    case warning
    case high
    case critical

    init(percentage: Double) {
        switch percentage {
        case ..<70: self = .normal
        case ..<85: self = .warning
        case ..<95: self = .high
        default: self = .critical
        }
    }

    static func < (lhs: UsageLevel, rhs: UsageLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .normal: "normal"
        case .warning: "warning"
        case .high: "high"
        case .critical: "critical"
        }
    }
}

enum UsageMath {
    /// Clamps a provider-reported percentage to 0...100.
    /// Returns nil for values that carry no information (missing, NaN, infinite).
    static func normalizedPercentage(_ raw: Double?) -> Double? {
        guard let raw, raw.isFinite else { return nil }
        return min(max(raw, 0), 100)
    }

    /// Whole-number percentage for display. Rounds down so the UI never
    /// shows a threshold as reached before it actually is.
    static func displayPercent(_ percentage: Double) -> Int {
        Int(percentage.rounded(.down))
    }
}
