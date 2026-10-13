import Foundation

/// Builds the exportable diagnostics text. Contains versions, paths and error
/// descriptions only — QuotaBar holds no credentials to include, and the
/// result is passed through `Redactor` regardless.
enum DiagnosticsReport {
    struct ProviderEntry: Sendable {
        let provider: AIProvider
        let enabled: Bool
        let dataSource: String
        let snapshot: ProviderSnapshot
    }

    static func build(
        providers: [ProviderEntry],
        paths: AppPaths,
        locator: any CLILocating,
        executor: any CLIExecuting,
        bridgeInstalled: Bool,
        settingsSummary: [String],
        logEntries: [String],
        now: Date = Date()
    ) async -> String {
        var lines: [String] = ["QuotaBar Diagnostics", "Generated: \(now.formatted(.iso8601))", ""]

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        lines += [
            "App version: \(version) (\(build))",
            "macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "CPU architecture: \(architecture())",
            "",
        ]

        for provider in AIProvider.allCases {
            let label = provider == .claude ? "Claude CLI" : "Codex CLI"
            if let url = await locator.locate(provider.cliName) {
                lines.append("\(label) path: \(paths.abbreviated(url))")
                lines.append("\(label) version: \(await cliVersion(url, executor: executor))")
            } else {
                lines.append("\(label) path: not found")
                lines.append("\(label) version: n/a")
            }
        }
        lines += ["Claude status line bridge: \(bridgeInstalled ? "installed" : "not installed")", ""]

        for entry in providers {
            let snapshot = entry.snapshot
            lines += [
                "[\(entry.provider.displayName)]",
                "Enabled: \(entry.enabled)",
                "Data source: \(entry.dataSource)",
                "State: \(snapshot.state.displayName)",
                "Last provider refresh: \(snapshot.lastSuccess.map { $0.formatted(.iso8601) } ?? "never")",
                "Last attempt: \(snapshot.lastAttempt.map { $0.formatted(.iso8601) } ?? "never")",
                "Data measured at: \(snapshot.usage.map { $0.updatedAt.formatted(.iso8601) } ?? "n/a")",
                "Last provider error: \(snapshot.lastError?.technicalDetail ?? "none")",
            ]
            for window in snapshot.usage?.windows ?? [] {
                let reset = window.resetsAt.map { $0.formatted(.iso8601) } ?? "unknown"
                lines.append("  \(window.displayName): \(UsageMath.displayPercent(window.usedPercentage))% (resets \(reset))")
            }
            lines.append("")
        }

        lines += ["[Settings]"] + settingsSummary + ["", "[Recent log]"]
        lines += logEntries.isEmpty ? ["(empty — enable Debug logging for more detail)"] : logEntries

        let home = paths.homeDirectory.path
        return Redactor.redact(lines.joined(separator: "\n").replacingOccurrences(of: home, with: "~")) + "\n"
    }

    private static func cliVersion(_ url: URL, executor: any CLIExecuting) async -> String {
        do {
            let result = try await executor.execute(executable: url, arguments: ["--version"], timeout: .seconds(10))
            let output = result.stdout.isEmpty ? result.stderr : result.stdout
            let firstLine = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return firstLine.isEmpty ? "unknown (exit \(result.exitCode))" : firstLine
        } catch CLIError.timedOut {
            return "unknown (timed out)"
        } catch {
            return "unknown (could not run)"
        }
    }

    private static func architecture() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
