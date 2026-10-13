import Foundation

/// Every file location QuotaBar touches, in one place so tests can redirect them.
struct AppPaths: Sendable {
    /// `~/Library/Application Support/QuotaBar`
    let supportDirectory: URL
    let homeDirectory: URL
    /// `~/.codex`, or `$CODEX_HOME` when set.
    let codexHome: URL

    init(supportDirectory: URL, homeDirectory: URL, codexHome: URL? = nil) {
        self.supportDirectory = supportDirectory
        self.homeDirectory = homeDirectory
        self.codexHome = codexHome ?? homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    static func live() -> AppPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        return AppPaths(
            supportDirectory: support.appendingPathComponent("QuotaBar", isDirectory: true),
            homeDirectory: home,
            codexHome: codexHome
        )
    }

    var cacheFile: URL { supportDirectory.appendingPathComponent("usage-cache.json") }
    var historyFile: URL { supportDirectory.appendingPathComponent("history.jsonl") }
    var notificationStateFile: URL { supportDirectory.appendingPathComponent("notification-state.json") }

    // Claude status line bridge
    var claudeSnapshotFile: URL { supportDirectory.appendingPathComponent("claude-statusline.json") }
    var bridgeScriptFile: URL { supportDirectory.appendingPathComponent("quotabar-statusline.sh") }
    var bridgeChainFile: URL { supportDirectory.appendingPathComponent("statusline-chain-command") }
    var bridgeOriginalFile: URL { supportDirectory.appendingPathComponent("statusline-original.json") }
    var claudeSettingsFile: URL { homeDirectory.appendingPathComponent(".claude/settings.json") }

    // Codex
    var codexSessionsDirectory: URL { codexHome.appendingPathComponent("sessions", isDirectory: true) }
    var codexAuthFile: URL { codexHome.appendingPathComponent("auth.json") }

    func ensureSupportDirectory() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }

    /// Replaces the home directory prefix with `~` for display and diagnostics.
    func abbreviated(_ url: URL) -> String {
        let path = url.path
        let home = homeDirectory.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
