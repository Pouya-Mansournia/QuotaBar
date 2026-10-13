import Foundation

/// Reads Claude usage from one of two sources:
///
/// - the snapshot written by the status line bridge (default; no credentials,
///   no network), or
/// - the Anthropic account endpoint, when the user has opted in. That source
///   also covers the VS Code extension, which does not run a status line.
struct ClaudeUsageProvider: UsageProvider {
    let provider = AIProvider.claude
    var dataSourceDescription: String {
        accountSource == nil
            ? "Claude Code status line data (rate_limits), captured locally by the QuotaBar bridge script"
            : "Anthropic account usage (api.anthropic.com), using Claude Code's sign-in"
    }

    let paths: AppPaths
    let bridge: ClaudeStatusLineBridge
    let locator: any CLILocating
    /// Set when the user has enabled the account usage source.
    var accountSource: ClaudeAccountUsageSource?

    func fetchUsage() async throws -> ProviderUsage {
        if let accountSource {
            return try await accountSource.fetch()
        }

        guard bridge.isInstalled() else {
            guard await locator.locate(provider.cliName) != nil else {
                throw ProviderError.cliNotInstalled(tool: "Claude Code")
            }
            throw ProviderError.notConfigured("Claude isn't connected yet")
        }

        let snapshot = paths.claudeSnapshotFile
        guard FileManager.default.fileExists(atPath: snapshot.path) else {
            guard await locator.locate(provider.cliName) != nil else {
                throw ProviderError.cliNotInstalled(tool: "Claude Code")
            }
            throw ProviderError.noUsageData("Waiting for Claude Code — send a message in a terminal session")
        }

        let data = try Data(contentsOf: snapshot)
        let attributes = try FileManager.default.attributesOfItem(atPath: snapshot.path)
        let capturedAt = attributes[.modificationDate] as? Date ?? Date()
        return try ClaudeUsageParser.parse(data, capturedAt: capturedAt)
    }
}
