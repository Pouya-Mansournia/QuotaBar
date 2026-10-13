import Foundation
import os

/// Unified-log wrapper that redacts every message and keeps a short in-memory
/// tail for the diagnostics report. Nothing is written to disk by QuotaBar.
final class AppLog: Sendable {
    static let shared = AppLog()

    private struct State {
        var debugEnabled = false
        var entries: [String] = []
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "QuotaBar", category: "app")
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let capacity = 200

    func setDebugEnabled(_ enabled: Bool) {
        state.withLock { $0.debugEnabled = enabled }
    }

    func debug(_ message: @autoclosure () -> String) {
        guard state.withLock({ $0.debugEnabled }) else { return }
        let text = record("DEBUG", message())
        logger.debug("\(text, privacy: .public)")
    }

    func info(_ message: String) {
        let text = record("INFO", message)
        logger.info("\(text, privacy: .public)")
    }

    func error(_ message: String) {
        let text = record("ERROR", message)
        logger.error("\(text, privacy: .public)")
    }

    func recentEntries() -> [String] {
        state.withLock { $0.entries }
    }

    func clear() {
        state.withLock { $0.entries.removeAll() }
    }

    private func record(_ level: String, _ message: String) -> String {
        let text = Redactor.redact(message)
        let stamp = Date().formatted(.iso8601)
        state.withLock {
            $0.entries.append("\(stamp) \(level) \(text)")
            if $0.entries.count > capacity {
                $0.entries.removeFirst($0.entries.count - capacity)
            }
        }
        return text
    }
}
