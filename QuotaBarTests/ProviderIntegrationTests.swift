import XCTest
@testable import QuotaBar

final class ClaudeStatusLineBridgeTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var paths: AppPaths!
    private var bridge: ClaudeStatusLineBridge!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        paths = directory.paths
        bridge = ClaudeStatusLineBridge(paths: paths)
    }

    private func writeSettings(_ json: String) throws {
        try FileManager.default.createDirectory(
            at: paths.claudeSettingsFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: paths.claudeSettingsFile)
    }

    private func readSettings() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.claudeSettingsFile))
        return try XCTUnwrap(object as? [String: Any])
    }

    /// Runs the installed script the way Claude Code does: JSON on stdin.
    private func runScript(input: String) throws -> String {
        let process = Process()
        process.executableURL = paths.bridgeScriptFile
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(decoding: output, as: UTF8.self)
    }

    func testInstallIntoFreshSetup() throws {
        XCTAssertFalse(bridge.isInstalled())
        try bridge.install()
        XCTAssertTrue(bridge.isInstalled())

        let statusLine = try XCTUnwrap(readSettings()["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["type"] as? String, "command")
        XCTAssertEqual(statusLine["command"] as? String, bridge.command)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: paths.bridgeScriptFile.path))
    }

    func testInstallPreservesOtherSettingsAndChainsExistingStatusLine() throws {
        try writeSettings(#"{"model":"opus","theme":"dark","statusLine":{"type":"command","command":"echo custom-line","padding":2}}"#)
        try bridge.install()

        let settings = try readSettings()
        XCTAssertEqual(settings["model"] as? String, "opus")
        XCTAssertEqual(settings["theme"] as? String, "dark")
        let statusLine = try XCTUnwrap(settings["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, bridge.command)
        XCTAssertEqual(statusLine["padding"] as? Int, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bridge.backupFile.path))

        // The user's own status line still renders.
        let output = try runScript(input: #"{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":1738425600}}}"#)
        XCTAssertEqual(output, "custom-line\n")
    }

    func testUninstallRestoresPreviousStatusLine() throws {
        try writeSettings(#"{"model":"opus","statusLine":{"type":"command","command":"echo custom-line","padding":2}}"#)
        try bridge.install()
        try bridge.uninstall()

        XCTAssertFalse(bridge.isInstalled())
        let settings = try readSettings()
        XCTAssertEqual(settings["model"] as? String, "opus")
        let statusLine = try XCTUnwrap(settings["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, "echo custom-line")
        XCTAssertEqual(statusLine["padding"] as? Int, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.bridgeScriptFile.path))
    }

    func testUninstallRemovesKeyWhenThereWasNoStatusLine() throws {
        try writeSettings(#"{"model":"opus"}"#)
        try bridge.install()
        try bridge.uninstall()
        let settings = try readSettings()
        XCTAssertNil(settings["statusLine"])
        XCTAssertEqual(settings["model"] as? String, "opus")
    }

    func testUninstallLeavesAForeignStatusLineAlone() throws {
        try bridge.install()
        try writeSettings(#"{"statusLine":{"type":"command","command":"echo someone-else"}}"#)
        try bridge.uninstall()
        let statusLine = try XCTUnwrap(readSettings()["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, "echo someone-else")
    }

    func testInvalidSettingsFileIsLeftUntouched() throws {
        let original = "{ this is not json"
        try writeSettings(original)
        XCTAssertThrowsError(try bridge.install()) { error in
            XCTAssertEqual(error as? ClaudeStatusLineBridge.BridgeError, .settingsNotJSON)
        }
        XCTAssertEqual(try String(contentsOf: paths.claudeSettingsFile, encoding: .utf8), original)
    }

    func testReinstallIsIdempotent() throws {
        try writeSettings(#"{"statusLine":{"type":"command","command":"echo custom-line"}}"#)
        try bridge.install()
        try bridge.install()
        try bridge.uninstall()
        let statusLine = try XCTUnwrap(readSettings()["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, "echo custom-line", "A second install must not chain to itself")
    }

    func testScriptStoresOnlyRateLimitsAndPrintsDefaultLine() throws {
        try bridge.install()
        let output = try runScript(input: """
        {"session_id":"secret-session","cwd":"/Users/me/private-project","model":{"display_name":"Opus"},
         "rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},
                        "seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}
        """)
        XCTAssertEqual(output, "Opus · 5h 24% · 7d 41%\n")

        let snapshot = try String(contentsOf: paths.claudeSnapshotFile, encoding: .utf8)
        XCTAssertFalse(snapshot.contains("secret-session"))
        XCTAssertFalse(snapshot.contains("private-project"))

        let usage = try ClaudeUsageParser.parse(Data(snapshot.utf8), capturedAt: .reference)
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 23.5)
        XCTAssertEqual(try XCTUnwrap(usage.window(.weekly)?.usedPercentage), 41.2, accuracy: 0.001)
        XCTAssertEqual(usage.window(.weekly)?.resetsAt, Date(timeIntervalSince1970: 1_738_857_600))
    }

    func testScriptKeepsPreviousSnapshotWhenLimitsAreAbsent() throws {
        try bridge.install()
        _ = try runScript(input: #"{"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":1738425600}}}"#)
        let before = try Data(contentsOf: paths.claudeSnapshotFile)

        // Start of a new session: no rate_limits yet.
        let output = try runScript(input: #"{"model":{"display_name":"Sonnet"}}"#)
        XCTAssertEqual(output, "Sonnet\n")
        XCTAssertEqual(try Data(contentsOf: paths.claudeSnapshotFile), before)

        // No temp files left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: paths.supportDirectory.path)
            .filter { $0.hasSuffix(".tmp") }
        XCTAssertEqual(leftovers, [])
    }
}

final class ClaudeUsageProviderTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var paths: AppPaths!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        paths = directory.paths
    }

    private func provider(cliInstalled: Bool = true) -> ClaudeUsageProvider {
        let tools = cliInstalled ? ["claude": URL(fileURLWithPath: "/opt/homebrew/bin/claude")] : [:]
        return ClaudeUsageProvider(paths: paths, bridge: ClaudeStatusLineBridge(paths: paths), locator: StubLocator(tools: tools))
    }

    private func assertError(_ provider: ClaudeUsageProvider, _ expected: ProviderError, line: UInt = #line) async {
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected an error", line: line)
        } catch {
            XCTAssertEqual(ProviderError.map(error), expected, line: line)
        }
    }

    func testCLINotInstalled() async {
        await assertError(provider(cliInstalled: false), .cliNotInstalled(tool: "Claude Code"))
    }

    func testBridgeNotInstalled() async {
        await assertError(provider(), .notConfigured("Claude isn't connected yet"))
    }

    func testWaitingForFirstSnapshot() async throws {
        try ClaudeStatusLineBridge(paths: paths).install()
        await assertError(provider(), .noUsageData("Waiting for Claude Code — send a message in a terminal session"))
    }

    func testReadsSnapshotWithItsTimestamp() async throws {
        try ClaudeStatusLineBridge(paths: paths).install()
        try Data(#"{"rate_limits":{"five_hour":{"used_percentage":68,"resets_at":1738425600}}}"#.utf8)
            .write(to: paths.claudeSnapshotFile)
        try FileManager.default.setAttributes([.modificationDate: Date.reference], ofItemAtPath: paths.claudeSnapshotFile.path)

        let usage = try await provider().fetchUsage()
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 68)
        XCTAssertEqual(usage.updatedAt, .reference, "Reports when Claude Code measured it, not when it was read")
    }

    func testCorruptSnapshotIsUnsupportedNotZero() async throws {
        try ClaudeStatusLineBridge(paths: paths).install()
        try Data("<<<".utf8).write(to: paths.claudeSnapshotFile)
        do {
            _ = try await provider().fetchUsage()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(ProviderError.map(error).connectionState, .unsupported)
        }
    }
}

final class OpenAIUsageProviderTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var paths: AppPaths!
    private let codexTools = ["codex": URL(fileURLWithPath: "/opt/homebrew/bin/codex")]

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        paths = directory.paths
    }

    private func line(percent: Double, timestamp: String) -> String {
        OpenAIUsageParserTests.validLine
            .replacingOccurrences(of: "\"used_percent\":42.0", with: "\"used_percent\":\(percent)")
            .replacingOccurrences(of: "2026-10-11T08:32:52.796Z", with: timestamp)
    }

    @discardableResult
    private func writeSession(day: String, name: String, content: String, modified: Date) throws -> URL {
        let folder = paths.codexSessionsDirectory.appendingPathComponent(day, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("rollout-\(name).jsonl")
        try Data(content.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        return file
    }

    private func assertError(_ provider: OpenAIUsageProvider, _ expected: ProviderError, line: UInt = #line) async {
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected an error", line: line)
        } catch {
            XCTAssertEqual(ProviderError.map(error), expected, line: line)
        }
    }

    func testCodexNotInstalled() async {
        await assertError(OpenAIUsageProvider(paths: paths, locator: StubLocator()), .cliNotInstalled(tool: "Codex CLI"))
    }

    func testNotSignedIn() async throws {
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        await assertError(
            OpenAIUsageProvider(paths: paths, locator: StubLocator(tools: codexTools)),
            .authenticationRequired(tool: "Codex")
        )
    }

    func testNoSessionsYet() async throws {
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: paths.codexAuthFile)
        await assertError(
            OpenAIUsageProvider(paths: paths, locator: StubLocator(tools: codexTools)),
            .noUsageData("No Codex sessions found yet")
        )
    }

    func testSessionsWithoutRateLimits() async throws {
        try writeSession(day: "2026/10/11", name: "a", content: #"{"type":"session_meta"}"# + "\n", modified: .reference)
        await assertError(
            OpenAIUsageProvider(paths: paths, locator: StubLocator()),
            .noUsageData("Codex has not reported usage limits yet")
        )
    }

    func testUsesMostRecentReadingAcrossSessions() async throws {
        try writeSession(
            day: "2026/10/10", name: "old",
            content: line(percent: 11, timestamp: "2026-10-10T08:00:00.000Z") + "\n",
            modified: Date.reference.addingTimeInterval(-3 * 86400)
        )
        try writeSession(
            day: "2026/10/11", name: "new",
            content: line(percent: 22, timestamp: "2026-10-11T08:00:00.000Z") + "\n"
                + line(percent: 33, timestamp: "2026-10-11T09:00:00.000Z") + "\n",
            modified: Date.reference.addingTimeInterval(-2 * 86400)
        )
        // Newest file on disk, but it never reached the API.
        try writeSession(day: "2026/10/12", name: "empty", content: "{\"type\":\"session_meta\"}\n", modified: .reference)

        let usage = try await OpenAIUsageProvider(paths: paths, locator: StubLocator()).fetchUsage()
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 33)
        XCTAssertEqual(usage.window(.weekly)?.usedPercentage, 18.5)
        XCTAssertEqual(usage.planName, "Plus")
    }

    func testReadsOnlyTheTailOfLargeFiles() async throws {
        let padding = String(repeating: #"{"type":"response_item","payload":{"text":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}}"# + "\n", count: 400)
        let content = line(percent: 5, timestamp: "2026-10-11T07:00:00.000Z") + "\n" + padding
            + line(percent: 64, timestamp: "2026-10-11T09:00:00.000Z") + "\n"
        try writeSession(day: "2026/10/11", name: "big", content: content, modified: .reference)

        var provider = OpenAIUsageProvider(paths: paths, locator: StubLocator())
        provider.tailBytes = 2048
        let usage = try await provider.fetchUsage()
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 64)
    }

    func testFallsBackToFullFileWhenTailHasNoReading() async throws {
        let padding = String(repeating: #"{"type":"response_item","payload":{"text":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}}"# + "\n", count: 400)
        try writeSession(
            day: "2026/10/11", name: "long-tail",
            content: line(percent: 47, timestamp: "2026-10-11T07:00:00.000Z") + "\n" + padding,
            modified: .reference
        )
        var provider = OpenAIUsageProvider(paths: paths, locator: StubLocator())
        provider.tailBytes = 2048
        let usage = try await provider.fetchUsage()
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 47)
    }

    func testLocatorReturnsNewestFilesFirst() throws {
        for (index, day) in ["2026/09/30", "2026/10/01", "2026/10/02"].enumerated() {
            try writeSession(day: day, name: "s\(index)", content: "{}\n", modified: Date.reference.addingTimeInterval(Double(index) * 86400))
        }
        // Not a session log; must be ignored.
        try Data("x".utf8).write(to: paths.codexSessionsDirectory.appendingPathComponent("2026/10/02/notes.txt"))

        let files = CodexSessionLocator(sessionsDirectory: paths.codexSessionsDirectory).recentRollouts(limit: 2)
        XCTAssertEqual(files.map(\.lastPathComponent), ["rollout-s2.jsonl", "rollout-s1.jsonl"])
        XCTAssertEqual(CodexSessionLocator(sessionsDirectory: paths.codexHome.appendingPathComponent("nope")).recentRollouts(limit: 5), [])
    }
}
