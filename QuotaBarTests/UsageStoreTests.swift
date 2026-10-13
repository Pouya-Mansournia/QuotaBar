import XCTest
@testable import QuotaBar

@MainActor
final class UsageStoreTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var notifier: SpyNotifier!
    private var suiteName: String!

    override func setUp() async throws {
        directory = try TemporaryDirectory()
        suiteName = "QuotaBarTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        settings = AppSettings(defaults: defaults)
        notifier = SpyNotifier()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore(_ providers: [any UsageProvider], now: Date = .reference) -> UsageStore {
        UsageStore(
            settings: settings,
            providers: { providers },
            cache: UsageCache(url: directory.paths.cacheFile),
            trackerStore: JSONFileStore(url: directory.paths.notificationStateFile),
            history: nil,
            notifier: notifier,
            now: { now }
        )
    }

    func testSuccessfulRefresh() async {
        let store = makeStore([StubProvider(provider: .claude, result: .success(makeUsage(fiveHour: 68, weekly: 31)))])
        await store.refresh()

        let snapshot = store.snapshot(for: .claude)
        XCTAssertEqual(snapshot.state, .connected)
        XCTAssertEqual(snapshot.usage?.window(.fiveHour)?.usedPercentage, 68)
        XCTAssertEqual(snapshot.lastSuccess, .reference)
        XCTAssertFalse(snapshot.isStale)
        XCTAssertEqual(store.lastRefresh, .reference)
        XCTAssertEqual(store.primaryPercentage(for: .claude, at: .reference), 68)
    }

    func testFailureKeepsPreviousValueAndMarksItStale() async {
        let provider = StubProvider(provider: .claude, result: .success(makeUsage(fiveHour: 68)))
        let store = makeStore([provider])
        await store.refresh()

        provider.set(.failure(ProviderError.networkUnavailable))
        await store.refresh()

        let snapshot = store.snapshot(for: .claude)
        XCTAssertEqual(snapshot.usage?.window(.fiveHour)?.usedPercentage, 68, "Valid data must not be replaced")
        XCTAssertTrue(snapshot.isStale)
        XCTAssertEqual(snapshot.state, .error)
        XCTAssertEqual(snapshot.lastError, .networkUnavailable)

        provider.set(.success(makeUsage(fiveHour: 70)))
        await store.refresh()
        XCTAssertFalse(store.snapshot(for: .claude).isStale)
        XCTAssertEqual(store.snapshot(for: .claude).usage?.window(.fiveHour)?.usedPercentage, 70)
    }

    func testFailureWithoutCacheShowsNoValue() async {
        let store = makeStore([StubProvider(provider: .codex, result: .failure(ProviderError.cliNotInstalled(tool: "Codex CLI")))])
        await store.refresh()

        let snapshot = store.snapshot(for: .codex)
        XCTAssertNil(snapshot.usage, "No data must stay unavailable, never zero")
        XCTAssertEqual(snapshot.state, .unavailable)
        XCTAssertFalse(snapshot.isStale)
        XCTAssertNil(store.primaryPercentage(for: .codex, at: .reference))
        XCTAssertNil(store.highestPercentage(at: .reference))
    }

    func testCacheSurvivesRelaunchAndLaterFailure() async {
        let first = makeStore([StubProvider(provider: .claude, result: .success(makeUsage(fiveHour: 68)))])
        await first.refresh()

        let relaunched = makeStore([StubProvider(provider: .claude, result: .failure(ProviderError.timedOut))])
        XCTAssertEqual(relaunched.snapshot(for: .claude).usage?.window(.fiveHour)?.usedPercentage, 68)
        await relaunched.refresh()
        XCTAssertEqual(relaunched.snapshot(for: .claude).usage?.window(.fiveHour)?.usedPercentage, 68)
        XCTAssertTrue(relaunched.snapshot(for: .claude).isStale)
    }

    func testUnknownErrorsAreMapped() async {
        struct Unexpected: Error {}
        let store = makeStore([StubProvider(provider: .claude, result: .failure(Unexpected()))])
        await store.refresh()
        XCTAssertEqual(store.snapshot(for: .claude).state, .error)
    }

    func testDisabledProviderIsNotFetched() async {
        settings.setEnabled(false, for: .codex)
        let store = makeStore([
            StubProvider(provider: .claude, result: .success(makeUsage(.claude, fiveHour: 10))),
            StubProvider(provider: .codex, result: .success(makeUsage(.codex, fiveHour: 99))),
        ])
        await store.refresh()
        XCTAssertNil(store.snapshot(for: .codex).usage)
        XCTAssertEqual(store.highestPercentage(at: .reference), 10)
    }

    func testHighestPercentageIgnoresExpiredWindows() async {
        let expired = makeUsage(fiveHour: 95, weekly: 40, resetsAt: Date.reference.addingTimeInterval(-60))
        let store = makeStore([StubProvider(provider: .claude, result: .success(expired))])
        await store.refresh()
        XCTAssertEqual(store.primaryPercentage(for: .claude, at: .reference), 0)
        XCTAssertEqual(store.highestPercentage(at: .reference), 40)
    }

    func testThresholdNotificationsAreDeliveredOnce() async {
        let provider = StubProvider(provider: .claude, result: .success(makeUsage(fiveHour: 91)))
        let store = makeStore([provider])
        await store.refresh()
        await store.refresh()

        let delivered = await notifier.delivered
        XCTAssertEqual(delivered.map(\.title), ["Claude usage reached 90%"])

        // Alert state is persisted, so a relaunch does not repeat it.
        let relaunched = makeStore([provider])
        await relaunched.refresh()
        let afterRelaunch = await notifier.delivered
        XCTAssertEqual(afterRelaunch.count, 1)
    }

    func testPerProviderThresholds() async {
        settings.setThreshold(80, enabled: false, for: .codex)
        let store = makeStore([
            StubProvider(provider: .claude, result: .success(makeUsage(.claude, fiveHour: 82))),
            StubProvider(provider: .codex, result: .success(makeUsage(.codex, fiveHour: 82))),
        ])
        await store.refresh()
        let delivered = await notifier.delivered
        XCTAssertEqual(delivered.map(\.title), ["Claude usage reached 80%"])
    }

    func testNotificationsCanBeDisabled() async {
        settings.notificationsEnabled = false
        let store = makeStore([StubProvider(provider: .claude, result: .success(makeUsage(fiveHour: 99)))])
        await store.refresh()
        let delivered = await notifier.delivered
        XCTAssertTrue(delivered.isEmpty)
    }

    func testResetCacheForgetsEverything() async {
        let provider = StubProvider(provider: .claude, result: .success(makeUsage(fiveHour: 68)))
        let store = makeStore([provider])
        await store.refresh()
        provider.set(.failure(ProviderError.timedOut))
        await store.resetCache()
        XCTAssertNil(store.snapshot(for: .claude).usage)
        XCTAssertNil(makeStore([provider]).snapshot(for: .claude).usage)
    }

    func testSettingsPersist() {
        settings.menuBarStyle = .highest
        settings.refreshInterval = .fiveMinutes
        settings.showWeeklyQuota = false
        settings.setEnabled(false, for: .codex)
        settings.setThreshold(90, enabled: false, for: .claude)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.menuBarStyle, .highest)
        XCTAssertEqual(reloaded.refreshInterval, .fiveMinutes)
        XCTAssertFalse(reloaded.showWeeklyQuota)
        XCTAssertEqual(reloaded.enabledProviders, [.claude])
        XCTAssertEqual(reloaded.thresholds(for: .claude), [80, 95])
        XCTAssertEqual(reloaded.thresholds(for: .codex), [80, 90, 95])
    }

    func testDefaultSettings() {
        XCTAssertEqual(settings.refreshInterval, .oneMinute)
        XCTAssertEqual(settings.refreshInterval.duration, .seconds(60))
        XCTAssertNil(RefreshInterval.manual.duration)
        XCTAssertEqual(settings.thresholds(for: .claude), [80, 90, 95])
        XCTAssertFalse(settings.mockMode)
        XCTAssertEqual(settings.historyRetention, .week)
    }
}
