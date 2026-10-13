import XCTest
@testable import QuotaBar

final class ClaudeAccountUsageParserTests: XCTestCase {
    private func parse(_ json: String) throws -> ProviderUsage {
        try ClaudeUsageParser.parseAccountUsage(Data(json.utf8), fetchedAt: .reference)
    }

    func testClassicShape() throws {
        let usage = try parse("""
        {"five_hour":{"utilization":33.0,"resets_at":"2026-10-13T16:00:00.123456+00:00"},
         "seven_day":{"utilization":5,"resets_at":"2026-10-13T17:00:00+00:00"},
         "seven_day_opus":{"utilization":80,"resets_at":null},"seven_day_oauth_apps":null}
        """)
        XCTAssertEqual(usage.windows.map(\.type), [.fiveHour, .weekly])
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 33)
        XCTAssertEqual(usage.window(.weekly)?.usedPercentage, 5, "The per-model limit must not replace the weekly one")
        XCTAssertEqual(try XCTUnwrap(usage.window(.fiveHour)?.resetsAt).timeIntervalSince(.reference), 4 * 3600, accuracy: 1)
        XCTAssertEqual(usage.updatedAt, .reference)
    }

    func testClosedWindowIsOmittedNotZero() throws {
        let usage = try parse(#"{"five_hour":null,"seven_day":{"utilization":5,"resets_at":null}}"#)
        XCTAssertEqual(usage.windows.map(\.type), [.weekly])
        XCTAssertNil(usage.window(.weekly)?.resetsAt)
    }

    func testNoOpenWindow() {
        XCTAssertThrowsProviderError(try parse(#"{"five_hour":null,"seven_day":null}"#)) { error in
            XCTAssertEqual(error.connectionState, .unavailable)
        }
    }

    func testLimitsListShape() throws {
        let usage = try parse("""
        {"limits":[{"type":"seven_day_sonnet","percent":90,"resets":1791900000},
                   {"type":"seven_day","percent":"12","resets":1791900000},
                   {"type":"five_hour","percent":41.5,"resets":null}]}
        """)
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 41.5)
        XCTAssertNil(usage.window(.fiveHour)?.resetsAt)
        XCTAssertEqual(usage.window(.weekly)?.usedPercentage, 12)
        XCTAssertEqual(usage.window(.weekly)?.resetsAt, Date(timeIntervalSince1970: 1_791_900_000))
    }

    func testUnknownShapeIsUnsupportedAndNamesOnlyKeys() {
        XCTAssertThrowsProviderError(try parse(#"{"quota":{"used":"secret-value"},"account":"me@example.com"}"#)) { error in
            XCTAssertEqual(error.connectionState, .unsupported)
            XCTAssertTrue(error.technicalDetail.contains("account, quota"))
            XCTAssertFalse(error.technicalDetail.contains("secret-value"))
            XCTAssertFalse(error.technicalDetail.contains("example.com"))
        }
        XCTAssertThrowsProviderError(try parse("<html>")) { error in
            XCTAssertEqual(error.connectionState, .unsupported)
        }
    }

    func testBooleansAreNotNumbers() {
        XCTAssertThrowsProviderError(try parse(#"{"five_hour":{"utilization":true}}"#)) { error in
            XCTAssertEqual(error.connectionState, .unavailable)
        }
    }
}

final class ClaudeAccountUsageSourceTests: XCTestCase {
    private final class StubCredentials: ClaudeCredentialProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<ClaudeCredential, ProviderError>
        private(set) var reads = 0

        init(_ result: Result<ClaudeCredential, ProviderError>) { self.result = result }

        func set(_ result: Result<ClaudeCredential, ProviderError>) { lock.withLock { self.result = result } }

        func claudeCredential() async throws -> ClaudeCredential {
            try lock.withLock {
                reads += 1
                return result
            }.get()
        }
    }

    private final class StubTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var status: Int
        private var body: String
        private(set) var requests: [URLRequest] = []

        init(status: Int = 200, body: String = #"{"five_hour":{"utilization":33,"resets_at":1791900000}}"#) {
            self.status = status
            self.body = body
        }

        func set(status: Int) { lock.withLock { self.status = status } }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            lock.withLock {
                requests.append(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (Data(body.utf8), response)
            }
        }
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date.reference
        var now: Date { lock.withLock { date } }
        func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
    }

    private let valid = ClaudeCredential(accessToken: "test-token", expiresAt: Date.reference.addingTimeInterval(3600))

    private func assertError(_ source: ClaudeAccountUsageSource, _ expected: ProviderError, line: UInt = #line) async {
        do {
            _ = try await source.fetch()
            XCTFail("Expected an error", line: line)
        } catch {
            XCTAssertEqual(error as? ProviderError, expected, line: line)
        }
    }

    func testRequestGoesOnlyToAnthropicWithBearerToken() async throws {
        let transport = StubTransport()
        let source = ClaudeAccountUsageSource(credentials: StubCredentials(.success(valid)), transport: transport, now: { .reference })
        let usage = try await source.fetch()

        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 33)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
    }

    func testDoesNotPollFasterThanMinimumInterval() async throws {
        let clock = Clock()
        let transport = StubTransport()
        let credentials = StubCredentials(.success(valid))
        let source = ClaudeAccountUsageSource(credentials: credentials, transport: transport, minimumInterval: 120, now: { clock.now })

        _ = try await source.fetch()
        clock.advance(60)
        _ = try await source.fetch()
        XCTAssertEqual(transport.requests.count, 1)

        clock.advance(61)
        _ = try await source.fetch()
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(credentials.reads, 1, "The token is kept in memory until it expires")
    }

    func testExpiredTokenIsNeverSent() async {
        let transport = StubTransport()
        let expired = ClaudeCredential(accessToken: "old", expiresAt: Date.reference.addingTimeInterval(-1))
        let source = ClaudeAccountUsageSource(credentials: StubCredentials(.success(expired)), transport: transport, now: { .reference })
        await assertError(source, .sessionExpired(tool: "Claude Code"))
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testRejectedTokenIsDroppedAndReRead() async throws {
        let transport = StubTransport(status: 401)
        let credentials = StubCredentials(.success(valid))
        let source = ClaudeAccountUsageSource(credentials: credentials, transport: transport, now: { .reference })
        await assertError(source, .sessionExpired(tool: "Claude Code"))

        // Claude Code renews its sign-in; the next attempt picks up the new token.
        credentials.set(.success(ClaudeCredential(accessToken: "renewed", expiresAt: nil)))
        transport.set(status: 200)
        _ = try await source.fetch()
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer renewed")
    }

    func testKeychainDenialBacksOffInsteadOfPromptingEveryRefresh() async throws {
        let clock = Clock()
        let credentials = StubCredentials(.failure(.permissionDenied(path: "Keychain")))
        let source = ClaudeAccountUsageSource(credentials: credentials, transport: StubTransport(), denialBackoff: 900, now: { clock.now })

        await assertError(source, .permissionDenied(path: "Keychain"))
        clock.advance(60)
        await assertError(source, .permissionDenied(path: "Keychain"))
        XCTAssertEqual(credentials.reads, 1)

        // Switching the source off and on asks again straight away.
        await source.reset()
        credentials.set(.success(valid))
        _ = try await source.fetch()
        XCTAssertEqual(credentials.reads, 2)
    }

    func testHTTPErrors() async {
        let limited = ClaudeAccountUsageSource(credentials: StubCredentials(.success(valid)), transport: StubTransport(status: 429), now: { .reference })
        do {
            _ = try await limited.fetch()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual((error as? ProviderError)?.connectionState, .unavailable)
        }
        let broken = ClaudeAccountUsageSource(credentials: StubCredentials(.success(valid)), transport: StubTransport(status: 500), now: { .reference })
        await assertError(broken, .unsupportedResponse("Usage endpoint returned HTTP 500"))
    }

    func testStoredCredentialParsing() throws {
        let stored = #"{"claudeAiOauth":{"accessToken":"abc","refreshToken":"r","expiresAt":1791896400000,"scopes":["user:inference"]}}"#
        let credential = try KeychainReader.parseCredential(Data(stored.utf8))
        XCTAssertEqual(credential.accessToken, "abc")
        XCTAssertEqual(credential.expiresAt, Date.reference.addingTimeInterval(3600))

        for bad in [#"{"claudeAiOauth":{"accessToken":""}}"#, #"{"other":1}"#, "not json abc-secret"] {
            XCTAssertThrowsProviderError(try KeychainReader.parseCredential(Data(bad.utf8))) { error in
                XCTAssertEqual(error, .authenticationRequired(tool: "Claude Code"))
                XCTAssertFalse(error.technicalDetail.contains("abc-secret"))
            }
        }
    }

    func testErrorMessages() {
        XCTAssertEqual(ProviderError.sessionExpired(tool: "Claude Code").connectionState, .authenticationRequired)
        XCTAssertEqual(ProviderError.permissionDenied(path: "Keychain").userMessage, "Keychain access was not allowed")
    }
}
