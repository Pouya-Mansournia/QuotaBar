import Foundation

/// Turns Claude Code status line JSON into usage windows. Pure; no I/O.
enum ClaudeUsageParser {
    /// - Parameters:
    ///   - data: Status line JSON as captured by the bridge script.
    ///   - capturedAt: When Claude Code produced it.
    static func parse(_ data: Data, capturedAt: Date) throws -> ProviderUsage {
        let payload: ClaudeStatusPayload
        do {
            payload = try JSONDecoder().decode(ClaudeStatusPayload.self, from: data)
        } catch {
            throw ProviderError.unsupportedResponse("Claude status line JSON could not be decoded")
        }

        // Claude Code only sends rate_limits to Pro/Max subscribers, and only
        // after the first API response of a session.
        guard let limits = payload.rateLimits else {
            throw ProviderError.noUsageData("Claude Code has not reported usage limits")
        }

        var windows: [UsageWindow] = []
        if let window = makeWindow(limits.fiveHour, type: .fiveHour) {
            windows.append(window)
        }
        if let window = makeWindow(limits.sevenDay, type: .weekly) {
            windows.append(window)
        }
        if var window = makeWindow(limits.spendLimit, type: .apiBudget) {
            window.estimatedCost = limits.spendLimit?.usedUSD?.value
            windows.append(window)
        }

        guard !windows.isEmpty else {
            throw ProviderError.noUsageData("Claude Code has not reported usage limits")
        }
        return ProviderUsage(provider: .claude, windows: windows, updatedAt: capturedAt)
    }

    private static func makeWindow(_ raw: ClaudeStatusPayload.Window?, type: UsageWindowType) -> UsageWindow? {
        guard let percentage = UsageMath.normalizedPercentage(raw?.usedPercentage?.value) else {
            return nil
        }
        return UsageWindow(type: type, usedPercentage: percentage, resetsAt: raw?.resetsAt?.value)
    }

    // MARK: Account usage endpoint

    private static let percentageKeys = ["utilization", "used_percentage", "used_percent", "percent", "percentage"]
    private static let resetKeys = ["resets_at", "reset_at", "resetsAt", "resets"]
    private static let nameKeys = ["type", "id", "name", "window", "key", "label"]

    /// Parses the response of the Anthropic account usage endpoint.
    ///
    /// Known shapes: `{"five_hour":{"utilization":33,"resets_at":"…"},"seven_day":{…}}`
    /// and a newer `{"limits":[{…}]}` list. Model-specific weekly limits are ignored.
    static func parseAccountUsage(_ data: Data, fetchedAt: Date) throws -> ProviderUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.unsupportedResponse("Account usage response is not a JSON object")
        }

        var windows: [UsageWindow] = []
        func add(_ raw: Any?, as type: UsageWindowType) {
            guard !windows.contains(where: { $0.type == type }),
                  let dictionary = raw as? [String: Any],
                  let percentage = UsageMath.normalizedPercentage(number(in: dictionary, keys: percentageKeys))
            else { return }
            windows.append(UsageWindow(type: type, usedPercentage: percentage, resetsAt: date(in: dictionary, keys: resetKeys)))
        }

        add(root["five_hour"], as: .fiveHour)
        add(root["seven_day"], as: .weekly)

        for item in root["limits"] as? [[String: Any]] ?? [] {
            let name = nameKeys.compactMap { item[$0] as? String }.joined(separator: " ").lowercased()
            // Per-model limits are separate quotas, not the overall weekly one.
            guard !name.isEmpty, !["opus", "sonnet", "haiku", "oauth"].contains(where: name.contains) else { continue }
            if name.contains("five") || name.contains("5h") || name.contains("5_h") || name.contains("session") {
                add(item, as: .fiveHour)
            } else if name.contains("seven") || name.contains("week") || name.contains("7d") || name.contains("7_d") {
                add(item, as: .weekly)
            }
        }

        guard !windows.isEmpty else {
            let knownKeys = ["five_hour", "seven_day", "limits"]
            if knownKeys.contains(where: { root[$0] != nil }) {
                // Recognised shape, but no window is open right now.
                throw ProviderError.noUsageData("No active Claude usage window reported")
            }
            // Key names only, never values, so the shape can be diagnosed.
            throw ProviderError.unsupportedResponse("Unrecognised account usage fields: \(root.keys.sorted().joined(separator: ", "))")
        }
        return ProviderUsage(provider: .claude, windows: windows, updatedAt: fetchedAt)
    }

    private static func number(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            switch dictionary[key] {
            case let value as NSNumber where CFGetTypeID(value) != CFBooleanGetTypeID():
                return value.doubleValue
            case let value as String:
                if let parsed = Double(value.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) { return parsed }
            default:
                continue
            }
        }
        return nil
    }

    private static func date(in dictionary: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            switch dictionary[key] {
            case let value as NSNumber where CFGetTypeID(value) != CFBooleanGetTypeID():
                if let date = LenientDate.date(fromEpoch: value.doubleValue) { return date }
            case let value as String:
                if let date = LenientDate.date(from: value) { return date }
            default:
                continue
            }
        }
        return nil
    }
}
