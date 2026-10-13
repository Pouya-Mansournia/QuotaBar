import Foundation

/// Extracts rate-limit readings from Codex session logs. Pure; no I/O.
enum OpenAIUsageParser {
    /// The general Codex limit. Logs can also carry model-specific limits
    /// under other ids; those are only used when nothing else is present.
    private static let generalLimitID = "codex"
    private static let marker = Data("\"rate_limits\"".utf8)

    /// Returns the most recent usable rate-limit event in a JSONL log,
    /// scanning from the end. Lines that are not valid JSON are skipped.
    static func latestEvent(inJSONL data: Data) -> CodexRateLimitEvent? {
        var fallback: CodexRateLimitEvent?
        let decoder = JSONDecoder()

        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true).reversed() {
            // Most lines are transcript content; skip them without decoding.
            guard line.range(of: marker) != nil,
                  let decoded = try? decoder.decode(CodexRolloutLine.self, from: line),
                  let limits = decoded.payload?.rateLimits,
                  limits.primary?.usedPercent != nil || limits.secondary?.usedPercent != nil
            else { continue }

            let event = CodexRateLimitEvent(timestamp: decoded.timestamp?.value, limits: limits)
            if limits.limitID == nil || limits.limitID == generalLimitID {
                return event
            }
            if fallback == nil {
                fallback = event
            }
        }
        return fallback
    }

    /// - Parameter recordedAt: Used when the event carries no timestamp.
    static func usage(from event: CodexRateLimitEvent, recordedAt: Date) throws -> ProviderUsage {
        let timestamp = event.timestamp ?? recordedAt
        var windows: [UsageWindow] = []

        for raw in [event.limits.primary, event.limits.secondary] {
            guard let raw, let percentage = UsageMath.normalizedPercentage(raw.usedPercent?.value) else {
                continue
            }
            var (type, label) = windowType(minutes: raw.windowMinutes?.value)
            if windows.contains(where: { $0.type == type && $0.label == label }) {
                // Two windows of the same length: keep both distinguishable.
                type = .custom
                label = label ?? "Secondary"
            }
            let resetsAt = raw.resetsAt?.value
                ?? raw.resetsInSeconds.map { timestamp.addingTimeInterval($0.value) }
            windows.append(UsageWindow(type: type, usedPercentage: percentage, resetsAt: resetsAt, label: label))
        }

        guard !windows.isEmpty else {
            throw ProviderError.noUsageData("Codex has not reported usage limits")
        }
        let plan = event.limits.planType.flatMap { $0.isEmpty ? nil : $0.capitalized }
        return ProviderUsage(provider: .codex, windows: windows, updatedAt: timestamp, planName: plan)
    }

    /// Maps a window length onto a known window type, or a labelled custom one.
    static func windowType(minutes: Double?) -> (type: UsageWindowType, label: String?) {
        guard let minutes, minutes.isFinite, minutes > 0 else {
            return (.custom, nil)
        }
        switch Int(minutes.rounded()) {
        case 300: return (.fiveHour, nil)
        case 1440: return (.daily, nil)
        case 10080: return (.weekly, nil)
        case 40320...44640: return (.monthly, nil)
        case let value where value < 60: return (.custom, "\(value)m")
        case let value where value < 2880: return (.custom, "\(value / 60)h")
        case let value: return (.custom, "\(value / 1440)d")
        }
    }
}
