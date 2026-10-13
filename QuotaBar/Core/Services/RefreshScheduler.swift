import Foundation

/// Runs the refresh action on a fixed interval using a single sleeping task —
/// no timers firing between refreshes, and nothing on the main thread while idle.
@MainActor
final class RefreshScheduler {
    private var task: Task<Void, Never>?

    /// Replaces any running schedule. A nil interval means manual refresh only.
    func start(every interval: Duration?, action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = nil
        guard let interval else { return }
        task = Task {
            while !Task.isCancelled {
                do {
                    // Tolerance lets the system coalesce wake-ups to save energy.
                    try await Task.sleep(for: interval, tolerance: interval / 10)
                } catch {
                    return
                }
                await action()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    var isRunning: Bool { task != nil }
}
