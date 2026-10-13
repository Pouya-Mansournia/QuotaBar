import XCTest
@testable import QuotaBar

final class ClaudeUsageParserTests: XCTestCase {
    private func parse(_ json: String) throws -> ProviderUsage {
        try ClaudeUsageParser.parse(Data(json.utf8), capturedAt: .reference)
    }

    func testValidResponse() throws {
        let usage = try parse("""
        {"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},
                        "seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}
        """)
        XCTAssertEqual(usage.provider, .claude)
        XCTAssertEqual(usage.updatedAt, .reference)
        XCTAssertEqual(usage.windows.map(\.type), [.fiveHour, .weekly])
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 23.5)
        XCTAssertEqual(usage.window(.fiveHour)?.resetsAt, Date(timeIntervalSince1970: 1_738_425_600))
        XCTAssertEqual(usage.window(.weekly)?.usedPercentage, 41.2)
    }

    func testMissingWeeklyValue() throws {
        let usage = try parse(#"{"rate_limits":{"five_hour":{"used_percentage":68,"resets_at":1738425600}}}"#)
        XCTAssertEqual(usage.windows.map(\.type), [.fiveHour])
        XCTAssertNil(usage.window(.weekly))
    }

    func testMissingResetTimeKeepsPercentage() throws {
        let usage = try parse(#"{"rate_limits":{"five_hour":{"used_percentage":12}}}"#)
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 12)
        XCTAssertNil(usage.window(.fiveHour)?.resetsAt)
    }

    func testMalformedResponse() {
        XCTAssertThrowsProviderError(try parse("5h limit: 68% used")) { error in
            XCTAssertEqual(error.connectionState, .unsupported)
        }
        XCTAssertThrowsProviderError(try parse(#"{"rate_limits": "#)) { error in
            XCTAssertEqual(error.connectionState, .unsupported)
        }
    }

    func testMissingRateLimitsIsUnavailableNotZero() {
        // Sent before the first API response, and for non-subscribers.
        XCTAssertThrowsProviderError(try parse(#"{"model":{"display_name":"Opus"}}"#)) { error in
            XCTAssertEqual(error.connectionState, .unavailable)
        }
        XCTAssertThrowsProviderError(try parse(#"{"rate_limits":{}}"#)) { error in
            XCTAssertEqual(error.connectionState, .unavailable)
        }
    }

    func testFormatVariation() throws {
        // Numbers as strings, a percent sign, and an ISO 8601 reset time.
        let usage = try parse("""
        {"rate_limits":{"five_hour":{"used_percentage":"68%","resets_at":"2026-10-13T13:42:00Z"},
                        "seven_day":{"used_percentage":"31.0","resets_at":"1738857600"}}}
        """)
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 68)
        XCTAssertEqual(usage.window(.fiveHour)?.resetsAt, Date.reference.addingTimeInterval(102 * 60))
        XCTAssertEqual(usage.window(.weekly)?.usedPercentage, 31)
        XCTAssertEqual(usage.window(.weekly)?.resetsAt, Date(timeIntervalSince1970: 1_738_857_600))
    }

    func testUnexpectedFieldsAreIgnored() throws {
        let usage = try parse("""
        {"session_id":"abc","cost":{"total_cost_usd":1.5},"new_top_level":[1,2,3],
         "rate_limits":{"five_hour":{"used_percentage":50,"resets_at":1738425600,"tier":"max","extra":{"a":1}},
                        "seven_day_opus":{"used_percentage":99},"future_window":null}}
        """)
        XCTAssertEqual(usage.windows.map(\.type), [.fiveHour])
        XCTAssertEqual(usage.window(.fiveHour)?.usedPercentage, 50)
    }

    func testFieldOrderDoesNotMatter() throws {
        let usage = try parse("""
        {"rate_limits":{"seven_day":{"resets_at":1738857600,"used_percentage":41},
                        "five_hour":{"resets_at":1738425600,"used_percentage":23}}}
        """)
        // Output order is fixed regardless of input order.
        XCTAssertEqual(usage.windows.map(\.type), [.fiveHour, .weekly])
        XCTAssertEqual(usage.windows.map(\.usedPercentage), [23, 41])
    }

    func testOneMalformedWindowDoesNotDiscardTheOther() throws {
        let usage = try parse("""
        {"rate_limits":{"five_hour":"unavailable","seven_day":{"used_percentage":41,"resets_at":1738857600}}}
        """)
        XCTAssertEqual(usage.windows.map(\.type), [.weekly])
    }

    func testSpendLimitWindow() throws {
        let usage = try parse("""
        {"rate_limits":{"spend_limit":{"used_percentage":162.8,"resets_at":1740787200,"used_usd":314.12,"limit_usd":500,"period":"monthly"}}}
        """)
        let window = try XCTUnwrap(usage.window(.apiBudget))
        XCTAssertEqual(window.usedPercentage, 100, "Over-limit values are clamped")
        XCTAssertEqual(window.estimatedCost, 314.12)
    }
}
