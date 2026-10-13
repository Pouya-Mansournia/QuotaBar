import Foundation
import Observation

/// Composition root: builds the object graph once and hands it to the views.
@MainActor
@Observable
final class AppEnvironment {
    @ObservationIgnored let paths: AppPaths
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let store: UsageStore
    @ObservationIgnored let history: HistoryStore
    @ObservationIgnored let bridge: ClaudeStatusLineBridge
    @ObservationIgnored let locator: any CLILocating
    @ObservationIgnored let executor: any CLIExecuting
    @ObservationIgnored let claudeAccountSource: ClaudeAccountUsageSource
    @ObservationIgnored let notifications = NotificationManager()
    @ObservationIgnored let launchAtLogin = LaunchAtLogin()
    @ObservationIgnored private let scheduler = RefreshScheduler()

    /// Unit tests are hosted by the app; they must not trigger real refreshes,
    /// notification prompts or timers.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Mock data is a development aid and cannot be switched on in Release builds.
    var isMockModeActive: Bool {
        #if DEBUG
        settings.mockMode
        #else
        false
        #endif
    }

    init(paths: AppPaths = .live(), defaults: UserDefaults = .standard) {
        let settings = AppSettings(defaults: defaults)
        let locator = CLILocator()
        let bridge = ClaudeStatusLineBridge(paths: paths)
        let history = HistoryStore(file: paths.historyFile)
        let accountSource = ClaudeAccountUsageSource()

        self.paths = paths
        self.settings = settings
        self.locator = locator
        self.executor = CLIExecutor()
        self.bridge = bridge
        self.history = history
        self.claudeAccountSource = accountSource
        self.store = UsageStore(
            settings: settings,
            providers: { Self.makeProviders(settings: settings, paths: paths, bridge: bridge, locator: locator, accountSource: accountSource) },
            cache: UsageCache(url: paths.cacheFile),
            trackerStore: JSONFileStore(url: paths.notificationStateFile),
            history: history,
            notifier: notifications
        )
    }

    func start() {
        guard !Self.isRunningTests else { return }
        AppLog.shared.setDebugEnabled(settings.debugLogging)
        observeSettings()
        reschedule()
        // Separate task: the permission prompt waits for the user and must not
        // hold up the first refresh.
        Task {
            if settings.notificationsEnabled, await notifications.authorization() == .notDetermined {
                await notifications.requestAuthorization()
            }
        }
        Task {
            await history.prune(retentionDays: settings.historyRetention.rawValue, now: Date())
            await store.refresh()
        }
    }

    /// Switches Claude to the account source and tries it straight away.
    /// Also used to ask for Keychain access again after it was declined.
    func connectClaudeAccount() async {
        settings.claudeUseAccountAPI = true
        await claudeAccountSource.reset()
        await store.refresh()
    }

    func dataSource(for provider: AIProvider) -> String {
        Self.makeProviders(settings: settings, paths: paths, bridge: bridge, locator: locator, accountSource: claudeAccountSource)
            .first { $0.provider == provider }?
            .dataSourceDescription ?? "None"
    }

    func diagnosticsReport() async -> String {
        let entries = AIProvider.allCases.map {
            DiagnosticsReport.ProviderEntry(
                provider: $0,
                enabled: settings.isEnabled($0),
                dataSource: dataSource(for: $0),
                snapshot: store.snapshot(for: $0)
            )
        }
        let summary = [
            "Menu bar style: \(settings.menuBarStyle.displayName)",
            "Refresh interval: \(settings.refreshInterval.displayName)",
            "Notifications: \(settings.notificationsEnabled)",
            "Claude account usage source: \(settings.claudeUseAccountAPI)",
            "History retention: \(settings.historyRetention.displayName)",
            "Mock mode: \(isMockModeActive)",
        ]
        return await DiagnosticsReport.build(
            providers: entries,
            paths: paths,
            locator: locator,
            executor: executor,
            bridgeInstalled: bridge.isInstalled(),
            settingsSummary: summary,
            logEntries: AppLog.shared.recentEntries()
        )
    }

    private static func makeProviders(
        settings: AppSettings,
        paths: AppPaths,
        bridge: ClaudeStatusLineBridge,
        locator: any CLILocating,
        accountSource: ClaudeAccountUsageSource
    ) -> [any UsageProvider] {
        #if DEBUG
        if settings.mockMode {
            return AIProvider.allCases.map { MockUsageProvider(provider: $0) }
        }
        #endif
        return [
            ClaudeUsageProvider(
                paths: paths,
                bridge: bridge,
                locator: locator,
                accountSource: settings.claudeUseAccountAPI ? accountSource : nil
            ),
            OpenAIUsageProvider(paths: paths, locator: locator),
        ]
    }

    private func reschedule() {
        scheduler.start(every: settings.refreshInterval.duration) { [store] in
            await store.refresh()
        }
    }

    /// Re-arms after every change: Observation delivers one callback per registration.
    private func observeSettings() {
        withObservationTracking {
            _ = settings.refreshInterval
            _ = settings.mockMode
            _ = settings.claudeUseAccountAPI
            _ = settings.enabledProviders
            _ = settings.debugLogging
            _ = settings.historyRetention
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                AppLog.shared.setDebugEnabled(self.settings.debugLogging)
                self.reschedule()
                self.observeSettings()
                // Clears any Keychain back-off so a re-enabled source asks again.
                await self.claudeAccountSource.reset()
                await self.history.prune(retentionDays: self.settings.historyRetention.rawValue, now: Date())
                await self.store.refresh()
            }
        }
    }
}
