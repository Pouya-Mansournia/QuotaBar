import Foundation

/// The subset of Claude Code's status line JSON that QuotaBar reads.
/// Schema: https://code.claude.com/docs/en/statusline
struct ClaudeStatusPayload: Decodable, Sendable {
    struct Window: Decodable, Sendable {
        let usedPercentage: LenientNumber?
        let resetsAt: LenientDate?
        let usedUSD: LenientNumber?
        let limitUSD: LenientNumber?
        let period: String?

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
            case usedUSD = "used_usd"
            case limitUSD = "limit_usd"
            case period
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercentage = container.decodeLossy(LenientNumber.self, forKey: .usedPercentage)
            resetsAt = container.decodeLossy(LenientDate.self, forKey: .resetsAt)
            usedUSD = container.decodeLossy(LenientNumber.self, forKey: .usedUSD)
            limitUSD = container.decodeLossy(LenientNumber.self, forKey: .limitUSD)
            period = container.decodeLossy(String.self, forKey: .period)
        }
    }

    struct RateLimits: Decodable, Sendable {
        let fiveHour: Window?
        let sevenDay: Window?
        let spendLimit: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case spendLimit = "spend_limit"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fiveHour = container.decodeLossy(Window.self, forKey: .fiveHour)
            sevenDay = container.decodeLossy(Window.self, forKey: .sevenDay)
            spendLimit = container.decodeLossy(Window.self, forKey: .spendLimit)
        }
    }

    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimits = container.decodeLossy(RateLimits.self, forKey: .rateLimits)
    }
}
