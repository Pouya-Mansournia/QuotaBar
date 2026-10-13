import Foundation

/// One line of a Codex CLI session log (`rollout-*.jsonl`), reduced to the
/// fields QuotaBar reads. Codex records the rate-limit state returned by the
/// server in every `token_count` event.
struct CodexRolloutLine: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let type: String?
        let rateLimits: CodexRateLimits?

        enum CodingKeys: String, CodingKey {
            case type
            case rateLimits = "rate_limits"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = container.decodeLossy(String.self, forKey: .type)
            rateLimits = container.decodeLossy(CodexRateLimits.self, forKey: .rateLimits)
        }
    }

    let timestamp: LenientDate?
    let payload: Payload?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = container.decodeLossy(LenientDate.self, forKey: .timestamp)
        payload = container.decodeLossy(Payload.self, forKey: .payload)
    }
}

struct CodexRateLimits: Decodable, Sendable {
    struct Window: Decodable, Sendable {
        let usedPercent: LenientNumber?
        let windowMinutes: LenientNumber?
        let resetsAt: LenientDate?
        /// Older Codex versions reported a relative reset instead of `resets_at`.
        let resetsInSeconds: LenientNumber?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
            case resetsInSeconds = "resets_in_seconds"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercent = container.decodeLossy(LenientNumber.self, forKey: .usedPercent)
            windowMinutes = container.decodeLossy(LenientNumber.self, forKey: .windowMinutes)
            resetsAt = container.decodeLossy(LenientDate.self, forKey: .resetsAt)
            resetsInSeconds = container.decodeLossy(LenientNumber.self, forKey: .resetsInSeconds)
        }
    }

    let limitID: String?
    let primary: Window?
    let secondary: Window?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case limitID = "limit_id"
        case primary
        case secondary
        case planType = "plan_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitID = container.decodeLossy(String.self, forKey: .limitID)
        primary = container.decodeLossy(Window.self, forKey: .primary)
        secondary = container.decodeLossy(Window.self, forKey: .secondary)
        planType = container.decodeLossy(String.self, forKey: .planType)
    }
}

/// A rate-limit reading and the moment Codex recorded it.
struct CodexRateLimitEvent: Sendable {
    let timestamp: Date?
    let limits: CodexRateLimits
}
