import Foundation
import Observation

enum MenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case iconOnly
    case claude
    case codex
    case both
    case highest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iconOnly: "Icon only"
        case .claude: "Claude percentage"
        case .codex: "Codex percentage"
        case .both: "Claude + Codex"
        case .highest: "Highest utilization"
        }
    }
}

enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case manual = 0

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .thirtySeconds: "30 sec"
        case .oneMinute: "60 sec"
        case .twoMinutes: "2 min"
        case .fiveMinutes: "5 min"
        case .tenMinutes: "10 min"
        case .manual: "Manual only"
        }
    }

    /// nil means no automatic refresh.
    var duration: Duration? {
        self == .manual ? nil : .seconds(rawValue)
    }
}

enum HistoryRetention: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var displayName: String { "\(rawValue) days" }
}

/// User preferences, persisted in UserDefaults. Holds no secrets.
@MainActor
@Observable
final class AppSettings {
    static let availableThresholds = [80, 90, 95]

    @ObservationIgnored private let defaults: UserDefaults

    var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: Key.menuBarStyle) } }
    var refreshInterval: RefreshInterval { didSet { defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval) } }
    var showResetCountdown: Bool { didSet { defaults.set(showResetCountdown, forKey: Key.showResetCountdown) } }
    var showWeeklyQuota: Bool { didSet { defaults.set(showWeeklyQuota, forKey: Key.showWeeklyQuota) } }
    var showProviderIcons: Bool { didSet { defaults.set(showProviderIcons, forKey: Key.showProviderIcons) } }
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }
    var notifyOnReset: Bool { didSet { defaults.set(notifyOnReset, forKey: Key.notifyOnReset) } }
    var historyRetention: HistoryRetention { didSet { defaults.set(historyRetention.rawValue, forKey: Key.historyRetention) } }
    var debugLogging: Bool { didSet { defaults.set(debugLogging, forKey: Key.debugLogging) } }
    /// Opt-in: read Claude usage from the Anthropic account endpoint.
    var claudeUseAccountAPI: Bool { didSet { defaults.set(claudeUseAccountAPI, forKey: Key.claudeUseAccountAPI) } }
    /// False until the first-run setup window has been dismissed.
    var hasCompletedSetup: Bool { didSet { defaults.set(hasCompletedSetup, forKey: Key.hasCompletedSetup) } }
    /// Only honoured in DEBUG builds; see `AppEnvironment`.
    var mockMode: Bool { didSet { defaults.set(mockMode, forKey: Key.mockMode) } }

    private var disabledProviders: Set<String> {
        didSet { defaults.set(disabledProviders.sorted(), forKey: Key.disabledProviders) }
    }
    private var thresholdsByProvider: [String: [Int]] {
        didSet { defaults.set(thresholdsByProvider, forKey: Key.thresholds) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarStyle = defaults.string(forKey: Key.menuBarStyle).flatMap(MenuBarStyle.init) ?? .both
        refreshInterval = (defaults.object(forKey: Key.refreshInterval) as? Int).flatMap(RefreshInterval.init) ?? .oneMinute
        showResetCountdown = defaults.object(forKey: Key.showResetCountdown) as? Bool ?? true
        showWeeklyQuota = defaults.object(forKey: Key.showWeeklyQuota) as? Bool ?? true
        showProviderIcons = defaults.object(forKey: Key.showProviderIcons) as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        notifyOnReset = defaults.object(forKey: Key.notifyOnReset) as? Bool ?? false
        historyRetention = (defaults.object(forKey: Key.historyRetention) as? Int).flatMap(HistoryRetention.init) ?? .week
        debugLogging = defaults.bool(forKey: Key.debugLogging)
        claudeUseAccountAPI = defaults.bool(forKey: Key.claudeUseAccountAPI)
        hasCompletedSetup = defaults.bool(forKey: Key.hasCompletedSetup)
        mockMode = defaults.bool(forKey: Key.mockMode)
        disabledProviders = Set(defaults.stringArray(forKey: Key.disabledProviders) ?? [])
        thresholdsByProvider = defaults.dictionary(forKey: Key.thresholds) as? [String: [Int]] ?? [:]
    }

    func isEnabled(_ provider: AIProvider) -> Bool {
        !disabledProviders.contains(provider.rawValue)
    }

    func setEnabled(_ enabled: Bool, for provider: AIProvider) {
        if enabled {
            disabledProviders.remove(provider.rawValue)
        } else {
            disabledProviders.insert(provider.rawValue)
        }
    }

    var enabledProviders: [AIProvider] {
        AIProvider.allCases.filter(isEnabled)
    }

    /// Alert thresholds for a provider, ascending. Defaults to 80/90/95.
    func thresholds(for provider: AIProvider) -> [Int] {
        (thresholdsByProvider[provider.rawValue] ?? Self.availableThresholds).sorted()
    }

    func setThreshold(_ threshold: Int, enabled: Bool, for provider: AIProvider) {
        var current = Set(thresholds(for: provider))
        if enabled {
            current.insert(threshold)
        } else {
            current.remove(threshold)
        }
        thresholdsByProvider[provider.rawValue] = current.sorted()
    }

    private enum Key {
        static let menuBarStyle = "menuBarStyle"
        static let refreshInterval = "refreshInterval"
        static let showResetCountdown = "showResetCountdown"
        static let showWeeklyQuota = "showWeeklyQuota"
        static let showProviderIcons = "showProviderIcons"
        static let notificationsEnabled = "notificationsEnabled"
        static let notifyOnReset = "notifyOnReset"
        static let historyRetention = "historyRetention"
        static let debugLogging = "debugLogging"
        static let claudeUseAccountAPI = "claudeUseAccountAPI"
        static let hasCompletedSetup = "hasCompletedSetup"
        static let mockMode = "mockMode"
        static let disabledProviders = "disabledProviders"
        static let thresholds = "thresholdsByProvider"
    }
}
