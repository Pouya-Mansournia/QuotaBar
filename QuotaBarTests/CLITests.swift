import XCTest
@testable import QuotaBar

final class CLILocatorTests: XCTestCase {
    private func locator(
        existing: Set<String>,
        shell: @escaping @Sendable (String) async -> String? = { _ in nil }
    ) -> CLILocator {
        CLILocator(
            searchDirectories: ["/opt/homebrew/bin", "/usr/local/bin", "/Users/me/.local/bin"],
            isExecutable: { existing.contains($0) },
            shellLookup: shell
        )
    }

    func testFindsToolInSearchDirectory() async {
        let url = await locator(existing: ["/usr/local/bin/claude"]).locate("claude")
        XCTAssertEqual(url?.path, "/usr/local/bin/claude")
    }

    func testSearchOrderIsRespected() async {
        let url = await locator(existing: ["/Users/me/.local/bin/codex", "/opt/homebrew/bin/codex"]).locate("codex")
        XCTAssertEqual(url?.path, "/opt/homebrew/bin/codex")
    }

    func testFallsBackToLoginShell() async {
        let url = await locator(existing: ["/custom/bin/claude"], shell: { _ in "/custom/bin/claude" }).locate("claude")
        XCTAssertEqual(url?.path, "/custom/bin/claude")
    }

    func testShellResultMustBeAnExecutableAbsolutePath() async {
        let missing = await locator(existing: [], shell: { _ in "/custom/bin/claude" }).locate("claude")
        XCTAssertNil(missing)
        let alias = await locator(existing: ["claude"], shell: { _ in "claude" }).locate("claude")
        XCTAssertNil(alias, "Shell aliases and builtins are not executables")
    }

    func testNotFound() async {
        let url = await locator(existing: []).locate("claude")
        XCTAssertNil(url)
    }

    func testRejectsPathLikeNames() async {
        let locator = locator(existing: ["/opt/homebrew/bin/../../etc/x", "/opt/homebrew/bin/a;b"], shell: { $0 })
        for name in ["../../etc/x", "a;b", "", "..", "claude code", "$(whoami)"] {
            let url = await locator.locate(name)
            XCTAssertNil(url, name)
        }
    }

    func testRealSystemTool() async {
        // /usr/bin is part of the default search path on every Mac.
        let url = await CLILocator(shellLookup: { _ in nil }).locate("plutil")
        XCTAssertEqual(url?.path, "/usr/bin/plutil")
    }
}

final class CLIExecutorTests: XCTestCase {
    private let executor = CLIExecutor()

    func testCapturesStdout() async throws {
        let result = try await executor.execute(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello", "$HOME; ls"],
            timeout: .seconds(5)
        )
        XCTAssertEqual(result.exitCode, 0)
        // Arguments are passed verbatim: no shell expansion or command chaining.
        XCTAssertEqual(result.stdout, "hello $HOME; ls\n")
        XCTAssertEqual(result.stderr, "")
    }

    func testCapturesStderrAndExitCode() async throws {
        let result = try await executor.execute(
            executable: URL(fileURLWithPath: "/bin/ls"),
            arguments: ["/definitely/not/here"],
            timeout: .seconds(5)
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("No such file"))
    }

    func testTimeout() async {
        let start = ContinuousClock.now
        do {
            _ = try await executor.execute(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"],
                timeout: .milliseconds(300)
            )
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertEqual(error as? CLIError, .timedOut)
        }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5), "The process must be terminated, not awaited")
    }

    func testLargeOutputDoesNotDeadlock() async throws {
        // Far more than a pipe buffer on both streams.
        let result = try await executor.execute(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' 'a'; head -c 300000 /dev/zero | tr '\\0' 'b' >&2"],
            timeout: .seconds(10)
        )
        XCTAssertEqual(result.stdout.count, 300_000)
        XCTAssertEqual(result.stderr.count, 300_000)
    }

    func testLaunchFailure() async {
        do {
            _ = try await executor.execute(
                executable: URL(fileURLWithPath: "/definitely/not/a/binary"),
                arguments: [],
                timeout: .seconds(5)
            )
            XCTFail("Expected a launch failure")
        } catch {
            guard case .launchFailed = error as? CLIError else {
                return XCTFail("Expected launchFailed, got \(error)")
            }
        }
    }
}

final class ProviderErrorTests: XCTestCase {
    func testMapping() {
        XCTAssertEqual(ProviderError.map(ProviderError.timedOut), .timedOut)
        XCTAssertEqual(ProviderError.map(CLIError.timedOut), .timedOut)
        XCTAssertEqual(ProviderError.map(CLIError.launchFailed("boom")), .unknown("boom"))
        XCTAssertEqual(ProviderError.map(URLError(.notConnectedToInternet)), .networkUnavailable)
        XCTAssertEqual(
            ProviderError.map(CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: "/x/y"])),
            .permissionDenied(path: "/x/y")
        )
        XCTAssertEqual(ProviderError.map(POSIXError(.EACCES)).connectionState, .error)
        XCTAssertEqual(ProviderError.map(CocoaError(.fileReadNoSuchFile)).connectionState, .unavailable)

        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        XCTAssertEqual(ProviderError.map(decoding).connectionState, .unsupported)
    }

    func testConnectionStates() {
        XCTAssertEqual(ProviderError.cliNotInstalled(tool: "Codex CLI").connectionState, .unavailable)
        XCTAssertEqual(ProviderError.authenticationRequired(tool: "Codex").connectionState, .authenticationRequired)
        XCTAssertEqual(ProviderError.unsupportedResponse("x").connectionState, .unsupported)
        XCTAssertEqual(ProviderError.networkUnavailable.connectionState, .error)
    }

    func testUserMessagesAreReadable() {
        XCTAssertEqual(ProviderError.cliNotInstalled(tool: "Claude Code").userMessage, "Claude Code not installed")
        XCTAssertEqual(ProviderError.cliNotInstalled(tool: "Codex CLI").userMessage, "Codex CLI not installed")
        XCTAssertEqual(ProviderError.permissionDenied(path: "/secret/path").userMessage, "Permission denied")
        XCTAssertEqual(ProviderError.unsupportedResponse("DecodingError(...)").userMessage, "Unsupported provider response")
        XCTAssertFalse(ProviderError.unknown("Swift.Error at 0x123").userMessage.contains("0x"))
    }
}
