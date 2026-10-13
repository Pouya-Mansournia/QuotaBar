import XCTest
@testable import QuotaBar

final class RedactorTests: XCTestCase {
    func testRedactsCredentialShapedText() {
        let samples = [
            "Authorization: Bearer abcDEF123456.tokenvalue",
            "using key sk-ant-api03-AbCdEfGhIjKlMnOpQrSt",
            #"{"access_token":"super-secret-value","ok":true}"#,
            "refresh_token=abcdef0123456789",
            "Cookie: sessionKey=verysecretcookie",
            "jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV",
            "OPENAI_API_KEY=sk-proj-0123456789abcdefghij",
            "password: hunter2hunter2",
        ]
        for sample in samples {
            let redacted = Redactor.redact(sample)
            XCTAssertTrue(redacted.contains(Redactor.placeholder), sample)
            for secret in ["tokenvalue", "AbCdEfGhIjKlMnOpQrSt", "super-secret-value", "abcdef0123456789",
                           "verysecretcookie", "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV", "0123456789abcdefghij", "hunter2"] {
                XCTAssertFalse(redacted.contains(secret), "\(sample) → \(redacted)")
            }
        }
    }

    func testLeavesOrdinaryTextAlone() {
        for text in ["Claude Code not installed", "claude: refreshed, 2 window(s)", "5h 68% resets 2026-10-13T13:42:00Z",
                     "Codex CLI path: ~/.local/bin/codex", "codex-cli 0.159.3"] {
            XCTAssertEqual(Redactor.redact(text), text)
        }
    }

    func testLogRedactsBeforeStoring() {
        let log = AppLog()
        log.error("request failed: Bearer abcDEF123456.tokenvalue")
        XCTAssertFalse(log.recentEntries().joined().contains("tokenvalue"))
        log.debug("hidden unless enabled")
        XCTAssertEqual(log.recentEntries().count, 1)
        log.setDebugEnabled(true)
        log.debug("now visible")
        XCTAssertEqual(log.recentEntries().count, 2)
    }
}

final class DiagnosticsReportTests: XCTestCase {
    private struct StubExecutor: CLIExecuting {
        func execute(executable: URL, arguments: [String], timeout: Duration) async throws -> CLIResult {
            if executable.lastPathComponent == "codex" { throw CLIError.timedOut }
            return CLIResult(exitCode: 0, stdout: "2.1.270 (Claude Code)\nextra line\n", stderr: "")
        }
    }

    func testReportContents() async throws {
        let directory = try TemporaryDirectory()
        let paths = directory.paths
        let home = paths.homeDirectory.path
        var failing = ProviderSnapshot()
        failing.state = .error
        failing.lastError = .unknown("failed with token=abc123secretvalue reading \(home)/.codex/sessions")

        let report = await DiagnosticsReport.build(
            providers: [
                .init(provider: .claude, enabled: true, dataSource: "status line",
                      snapshot: ProviderSnapshot(usage: makeUsage(fiveHour: 68), state: .connected, lastSuccess: .reference)),
                .init(provider: .codex, enabled: true, dataSource: "session logs", snapshot: failing),
            ],
            paths: paths,
            locator: StubLocator(tools: [
                "claude": URL(fileURLWithPath: "\(home)/.local/bin/claude"),
                "codex": URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            ]),
            executor: StubExecutor(),
            bridgeInstalled: true,
            settingsSummary: ["Refresh interval: 60 sec"],
            logEntries: ["2026-10-13T12:00:00Z ERROR something"],
            now: .reference
        )

        for expected in [
            "App version:", "macOS version:", "CPU architecture:",
            "Claude CLI path: ~/.local/bin/claude", "Claude CLI version: 2.1.270 (Claude Code)",
            "Codex CLI path: /opt/homebrew/bin/codex", "Codex CLI version: unknown (timed out)",
            "Last provider refresh: 2026-10-13T12:00:00Z", "Last provider error:",
            "5-Hour Window: 68%", "Refresh interval: 60 sec", "ERROR something",
        ] {
            XCTAssertTrue(report.contains(expected), "Missing: \(expected)\n\(report)")
        }
        XCTAssertFalse(report.contains("abc123secretvalue"), "Secrets must be redacted")
        XCTAssertFalse(report.contains(home), "Home directory must be abbreviated")
    }
}

final class MenuBarTitleTests: XCTestCase {
    private let both: [(provider: AIProvider, value: Double?)] = [(.claude, 68.9), (.codex, 42)]

    func testStyles() {
        XCTAssertNil(MenuBarTitle.text(style: .iconOnly, percentages: both, highest: 68.9))
        XCTAssertEqual(MenuBarTitle.text(style: .claude, percentages: both, highest: 68.9), "68%")
        XCTAssertEqual(MenuBarTitle.text(style: .codex, percentages: both, highest: 68.9), "42%")
        XCTAssertEqual(MenuBarTitle.text(style: .both, percentages: both, highest: 68.9), "C 68 · O 42")
        XCTAssertEqual(MenuBarTitle.text(style: .highest, percentages: both, highest: 68.9), "68%")
    }

    func testMissingDataIsNeverShownAsZero() {
        let partial: [(provider: AIProvider, value: Double?)] = [(.claude, nil), (.codex, 42)]
        XCTAssertEqual(MenuBarTitle.text(style: .claude, percentages: partial, highest: 42), "–")
        XCTAssertEqual(MenuBarTitle.text(style: .both, percentages: partial, highest: 42), "C – · O 42")
        XCTAssertEqual(MenuBarTitle.text(style: .highest, percentages: [], highest: nil), "–")
    }

    func testDisabledProvidersAreOmitted() {
        let claudeOnly: [(provider: AIProvider, value: Double?)] = [(.claude, 5)]
        XCTAssertEqual(MenuBarTitle.text(style: .both, percentages: claudeOnly, highest: 5), "C 5")
        XCTAssertNil(MenuBarTitle.text(style: .codex, percentages: claudeOnly, highest: 5))
        XCTAssertNil(MenuBarTitle.text(style: .both, percentages: [], highest: nil))
    }

    func testSymbolTracksUsage() {
        XCTAssertEqual(MenuBarTitle.symbolName(highest: nil), "gauge.with.dots.needle.0percent")
        XCTAssertEqual(MenuBarTitle.symbolName(highest: 68), "gauge.with.dots.needle.67percent")
        XCTAssertEqual(MenuBarTitle.symbolName(highest: 97), "gauge.with.dots.needle.100percent")
    }
}

final class HistoryStoreTests: XCTestCase {
    func testRecordsAndFilters() async throws {
        let directory = try TemporaryDirectory()
        let store = HistoryStore(file: directory.paths.historyFile)

        await store.record(makeUsage(.claude, fiveHour: 10, weekly: 5), at: .reference)
        await store.record(makeUsage(.claude, fiveHour: 20, weekly: 5), at: Date.reference.addingTimeInterval(60))

        let all = await store.samples(since: .distantPast)
        // Unchanged weekly value within the minimum interval is not repeated.
        XCTAssertEqual(all.map(\.usedPercentage), [10, 5, 20])
        XCTAssertEqual(all.first?.seriesName, "Claude 5h")

        let recent = await store.samples(since: Date.reference.addingTimeInterval(30))
        XCTAssertEqual(recent.map(\.usedPercentage), [20])
    }

    func testUnchangedValueIsRecordedAgainAfterInterval() async throws {
        let directory = try TemporaryDirectory()
        let store = HistoryStore(file: directory.paths.historyFile, minimumInterval: 900)
        await store.record(makeUsage(fiveHour: 10), at: .reference)
        await store.record(makeUsage(fiveHour: 10), at: Date.reference.addingTimeInterval(300))
        await store.record(makeUsage(fiveHour: 10), at: Date.reference.addingTimeInterval(1000))
        let count = await store.samples(since: .distantPast).count
        XCTAssertEqual(count, 2)
    }

    func testPruneAndPersistence() async throws {
        let directory = try TemporaryDirectory()
        let file = directory.paths.historyFile
        let store = HistoryStore(file: file)
        await store.record(makeUsage(fiveHour: 10), at: Date.reference.addingTimeInterval(-10 * 86400))
        await store.record(makeUsage(fiveHour: 30), at: .reference)

        await store.prune(retentionDays: 7, now: .reference)
        // A new instance reads what was written to disk.
        let reloaded = await HistoryStore(file: file).samples(since: .distantPast)
        XCTAssertEqual(reloaded.map(\.usedPercentage), [30])

        await store.clear()
        let cleared = await store.samples(since: .distantPast)
        XCTAssertTrue(cleared.isEmpty)
    }

    func testExpiredWindowIsRecordedAsZero() async throws {
        let directory = try TemporaryDirectory()
        let store = HistoryStore(file: directory.paths.historyFile)
        await store.record(makeUsage(fiveHour: 80, resetsAt: Date.reference.addingTimeInterval(-1)), at: .reference)
        let samples = await store.samples(since: .distantPast)
        XCTAssertEqual(samples.map(\.usedPercentage), [0])
    }
}

@MainActor
final class SetupTests: XCTestCase {
    func testInstallCommandIsOnePastableLine() {
        let command = SetupView.installCommand
        XCTAssertFalse(command.contains("\n"), "A line break would run the command early when pasted")
        XCTAssertTrue(command.hasPrefix("curl -fsSL https://claude.ai/install.sh | bash;"))
        XCTAssertTrue(command.contains(#"export PATH="$HOME/.local/bin:$PATH";"#))
        XCTAssertTrue(command.hasSuffix("claude"))
    }
}
