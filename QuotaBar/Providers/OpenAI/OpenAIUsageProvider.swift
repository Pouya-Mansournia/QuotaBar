import Foundation

/// Reads Codex usage from the rate-limit records the Codex CLI writes to its
/// local session logs.
///
/// Reads no credentials and makes no network requests. It only checks whether
/// `auth.json` exists, never its contents.
struct OpenAIUsageProvider: UsageProvider {
    let provider = AIProvider.codex
    let dataSourceDescription = "Codex CLI session logs (~/.codex/sessions), rate_limits recorded with each response"

    let paths: AppPaths
    let locator: any CLILocating

    /// How many recent session files to inspect.
    var sessionLimit = 8
    /// Rate-limit records are written continuously, so the end of the file is enough.
    var tailBytes: UInt64 = 256 * 1024
    var fullReadLimit: UInt64 = 32 * 1024 * 1024

    func fetchUsage() async throws -> ProviderUsage {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: paths.codexHome.path) else {
            throw ProviderError.cliNotInstalled(tool: "Codex CLI")
        }

        let files = CodexSessionLocator(sessionsDirectory: paths.codexSessionsDirectory)
            .recentRollouts(limit: sessionLimit)
        guard !files.isEmpty else {
            guard await locator.locate(provider.cliName) != nil else {
                throw ProviderError.cliNotInstalled(tool: "Codex CLI")
            }
            guard fileManager.fileExists(atPath: paths.codexAuthFile.path) else {
                throw ProviderError.authenticationRequired(tool: "Codex")
            }
            throw ProviderError.noUsageData("No Codex sessions found yet")
        }

        var latest: (event: CodexRateLimitEvent, date: Date)?
        var firstReadError: Error?
        for file in files {
            let modified = CodexSessionLocator.modificationDate(of: file) ?? .distantPast
            // Files are newest-first; an older file cannot beat a newer reading.
            if let latest, modified < latest.date { continue }
            do {
                guard let event = try Self.latestEvent(in: file, tailBytes: tailBytes, fullReadLimit: fullReadLimit) else {
                    continue
                }
                let date = event.timestamp ?? modified
                if latest == nil || date > latest!.date {
                    latest = (event, date)
                }
            } catch {
                firstReadError = firstReadError ?? error
            }
        }

        guard let latest else {
            if let firstReadError { throw firstReadError }
            throw ProviderError.noUsageData("Codex has not reported usage limits yet")
        }
        return try OpenAIUsageParser.usage(from: latest.event, recordedAt: latest.date)
    }

    static func latestEvent(in file: URL, tailBytes: UInt64, fullReadLimit: UInt64) throws -> CodexRateLimitEvent? {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let offset = size > tailBytes ? size - tailBytes : 0
        try handle.seek(toOffset: offset)
        var data = try handle.readToEnd() ?? Data()
        if offset > 0, let newline = data.firstIndex(of: 0x0A) {
            // The read started mid-line; drop the partial first line.
            data = data.suffix(from: data.index(after: newline))
        }
        if let event = OpenAIUsageParser.latestEvent(inJSONL: data) {
            return event
        }

        guard offset > 0, size <= fullReadLimit else { return nil }
        try handle.seek(toOffset: 0)
        return OpenAIUsageParser.latestEvent(inJSONL: try handle.readToEnd() ?? Data())
    }
}
