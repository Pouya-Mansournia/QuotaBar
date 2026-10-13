import Foundation
import Observation

/// The single source of truth for what the UI shows. Owns refresh, the
/// stale-cache policy, history recording and alert evaluation.
@MainActor
@Observable
final class UsageStore {
    private(set) var snapshots: [AIProvider: ProviderSnapshot] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let service: UsageService
    @ObservationIgnored private let providers: @MainActor () -> [any UsageProvider]
    @ObservationIgnored private let cache: UsageCache
    @ObservationIgnored private let trackerStore: JSONFileStore<ThresholdTracker>
    @ObservationIgnored private let history: HistoryStore?
    @ObservationIgnored private let notifier: any UsageNotifying
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var tracker: ThresholdTracker

    init(
        settings: AppSettings,
        service: UsageService = UsageService(),
        providers: @escaping @MainActor () -> [any UsageProvider],
        cache: UsageCache,
        trackerStore: JSONFileStore<ThresholdTracker>,
        history: HistoryStore?,
        notifier: any UsageNotifying,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.service = service
        self.providers = providers
        self.cache = cache
        self.trackerStore = trackerStore
        self.history = history
        self.notifier = notifier
        self.now = now
        self.tracker = trackerStore.load() ?? ThresholdTracker()

        for usage in cache.load() ?? [] {
            snapshots[usage.provider] = ProviderSnapshot(usage: usage, state: .connected, lastSuccess: usage.updatedAt)
        }
    }

    func snapshot(for provider: AIProvider) -> ProviderSnapshot {
        snapshots[provider] ?? ProviderSnapshot()
    }

    /// Percentage shown for a provider in the menu bar title, if known.
    func primaryPercentage(for provider: AIProvider, at date: Date) -> Double? {
        guard settings.isEnabled(provider) else { return nil }
        return snapshots[provider]?.usage?.primaryWindow?.effectivePercentage(at: date)
    }

    /// The most-used window across all enabled providers.
    func highestPercentage(at date: Date) -> Double? {
        settings.enabledProviders
            .flatMap { snapshots[$0]?.usage?.windows ?? [] }
            .map { $0.effectivePercentage(at: date) }
            .max()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let active = providers().filter { settings.isEnabled($0.provider) }
        let results = await service.fetch(from: active)
        let date = now()
        var events: [ThresholdEvent] = []

        for (provider, result) in results {
            var snapshot = snapshots[provider] ?? ProviderSnapshot()
            snapshot.lastAttempt = date
            switch result {
            case .success(let usage):
                snapshot.usage = usage
                snapshot.state = .connected
                snapshot.lastError = nil
                snapshot.lastSuccess = date
                events += tracker.evaluate(usage, thresholds: settings.thresholds(for: provider), now: date)
                await history?.record(usage, at: date)
                AppLog.shared.debug("\(provider.rawValue): refreshed, \(usage.windows.count) window(s)")
            case .failure(let error):
                // Keep the previous reading; the UI marks it as stale.
                snapshot.state = error.connectionState
                snapshot.lastError = error
                AppLog.shared.debug("\(provider.rawValue): \(error.technicalDetail)")
            }
            snapshots[provider] = snapshot
        }
        lastRefresh = date

        persist()
        await notify(events, at: date)
    }

    /// Forgets cached readings, alert state and history, then refreshes.
    func resetCache() async {
        cache.delete()
        trackerStore.delete()
        tracker = ThresholdTracker()
        snapshots = [:]
        lastRefresh = nil
        await history?.clear()
        await refresh()
    }

    private func persist() {
        do {
            try cache.save(snapshots.values.compactMap(\.usage).sorted { $0.provider.rawValue < $1.provider.rawValue })
            try trackerStore.save(tracker)
        } catch {
            AppLog.shared.error("Could not save cache: \(error.localizedDescription)")
        }
    }

    private func notify(_ events: [ThresholdEvent], at date: Date) async {
        guard settings.notificationsEnabled else { return }
        let notifications = events
            .filter { event in
                if case .reset = event { return settings.notifyOnReset }
                return true
            }
            .map { NotificationComposer.compose($0, now: date) }
        await notifier.deliver(notifications)
    }
}
