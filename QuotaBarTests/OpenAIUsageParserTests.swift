import XCTest
@testable import QuotaBar

final class OpenAIUsageParserTests: XCTestCase {
    /// Shape recorded by codex-cli 0.159.
    static let validLine = """
    {"timestamp":"2026-10-11T08:32:52.796Z","ordinal":41,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200}},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":42.0,"window_minutes":300,"resets_at":1791722190},"secondary":{"used_percent":18.5,"window_minutes":10080,"resets_at":1792308990},"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"plan_type":"plus","rate_limit_reached_type":null}}}
    """

    private func usage(fromJSONL text: String) throws -> ProviderUsage {
        let event = try XCTUnwrap(OpenAIUsageParser.latestEvent(inJSONL: Data(text.utf8)))
        return try OpenAIUsageParser.usage(from: event, recordedAt: .reference)
    }

    func testValidResponse() throws {
        let usage = try usage(fromJSONL: Self.validLine)
        XCTAssertEqual(usage.provider, .codex)
        XCTAssertEqual(usage.planName, "Plus")
        XCTAssertEqual(usage.windows.map(\.type), [.fiveHour, .weekly])
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 42)
        XCTAssertEqual(usage.window(.fiveHour)?.resetsAt, Date(timeIntervalSince1970: 1_791_722_190))
        XCTAssertEqual(usage.window(.weekly)?.usedPercentage, 18.5)
        XCTAssertEqual(usage.updatedAt.timeIntervalSince1970, 1_791_707_572.796, accuracy: 0.01)
    }

    func testMissingWeeklyValue() throws {
        let usage = try usage(fromJSONL: """
        {"timestamp":"2026-10-11T08:32:52Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":7,"window_minutes":300,"resets_at":1791722190},"secondary":null}}}
        """)
        XCTAssertEqual(usage.windows.map(\.type), [.fiveHour])
    }

    func testMalformedLinesAreSkipped() throws {
        let log = [
            #"{"type":"session_meta","payload":{"id":"x"}}"#,
            Self.validLine,
            #"{"timestamp":"2026-10-11T09:00:00Z","payload":{"type":"token_count","rate_limits": {"primary": "#,
            "not json at all \"rate_limits\"",
            #"{"timestamp":"2026-10-11T09:01:00Z","payload":{"type":"token_count","rate_limits":null}}"#,
        ].joined(separator: "\n")
        XCTAssertEqual(try usage(fromJSONL: log).window(.fiveHour)?.usedPercentage, 42)
    }

    func testNoRateLimitsAnywhere() {
        let log = #"{"type":"response_item","payload":{"type":"message"}}"# + "\n" + "garbage"
        XCTAssertNil(OpenAIUsageParser.latestEvent(inJSONL: Data(log.utf8)))
        XCTAssertNil(OpenAIUsageParser.latestEvent(inJSONL: Data()))
    }

    func testLatestEventWins() throws {
        let older = Self.validLine
        let newer = older
            .replacingOccurrences(of: "\"used_percent\":42.0", with: "\"used_percent\":57.0")
            .replacingOccurrences(of: "08:32:52.796Z", with: "08:40:00.000Z")
        XCTAssertEqual(try usage(fromJSONL: older + "\n" + newer + "\n").window(.fiveHour)?.usedPercentage, 57)
    }

    func testGeneralLimitPreferredOverModelSpecificLimit() throws {
        let modelSpecific = Self.validLine
            .replacingOccurrences(of: "\"limit_id\":\"codex\"", with: "\"limit_id\":\"codex_other_model\"")
            .replacingOccurrences(of: "\"used_percent\":42.0", with: "\"used_percent\":3.0")
        XCTAssertEqual(try usage(fromJSONL: Self.validLine + "\n" + modelSpecific).window(.fiveHour)?.usedPercentage, 42)
        // …but a model-specific limit is better than nothing.
        XCTAssertEqual(try usage(fromJSONL: modelSpecific).window(.fiveHour)?.usedPercentage, 3)
    }

    func testFormatVariation() throws {
        // Reordered fields, string numbers and the legacy relative reset field.
        let usage = try usage(fromJSONL: """
        {"payload":{"rate_limits":{"secondary":{"resets_in_seconds":"3600","window_minutes":"10080","used_percent":"18"},"primary":{"window_minutes":300,"used_percent":42,"resets_in_seconds":600},"plan_type":"pro"},"type":"token_count"},"timestamp":"2026-10-13T12:00:00Z","type":"event_msg"}
        """)
        XCTAssertEqual(usage.windows.map(\.type), [.fiveHour, .weekly])
        XCTAssertEqual(usage.window(.fiveHour)?.resetsAt, Date.reference.addingTimeInterval(600))
        XCTAssertEqual(usage.window(.weekly)?.resetsAt, Date.reference.addingTimeInterval(3600))
        XCTAssertEqual(usage.window(.weekly)?.usedPercentage, 18)
    }

    func testUnexpectedFieldsAndMissingTimestamp() throws {
        let usage = try usage(fromJSONL: """
        {"brand_new":true,"payload":{"type":"token_count","x":[1],"rate_limits":{"primary":{"used_percent":5,"window_minutes":300,"resets_at":1791722190,"surprise":{}},"mystery":1}}}
        """)
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 5)
        XCTAssertEqual(usage.updatedAt, .reference, "Falls back to the file's date")
    }

    func testWindowTypeMapping() {
        XCTAssertEqual(OpenAIUsageParser.windowType(minutes: 300).type, .fiveHour)
        XCTAssertEqual(OpenAIUsageParser.windowType(minutes: 1440).type, .daily)
        XCTAssertEqual(OpenAIUsageParser.windowType(minutes: 10080).type, .weekly)
        XCTAssertEqual(OpenAIUsageParser.windowType(minutes: 43200).type, .monthly)
        XCTAssertEqual(OpenAIUsageParser.windowType(minutes: 180).type, .custom)
        XCTAssertEqual(OpenAIUsageParser.windowType(minutes: 180).label, "3h")
        XCTAssertEqual(OpenAIUsageParser.windowType(minutes: 20160).label, "14d")
        XCTAssertEqual(OpenAIUsageParser.windowType(minutes: nil).type, .custom)
        XCTAssertNil(OpenAIUsageParser.windowType(minutes: nil).label)
    }

    func testEventWithoutUsablePercentagesIsNotUsage() throws {
        let event = try XCTUnwrap(OpenAIUsageParser.latestEvent(inJSONL: Data(Self.validLine.utf8)))
        XCTAssertNoThrow(try OpenAIUsageParser.usage(from: event, recordedAt: .reference))
        let empty = #"{"payload":{"rate_limits":{"primary":{"window_minutes":300}}}}"#
        XCTAssertNil(OpenAIUsageParser.latestEvent(inJSONL: Data(empty.utf8)))
    }
}
