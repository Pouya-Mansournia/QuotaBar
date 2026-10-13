import Foundation

/// Formats reset times and "updated … ago" labels. Purely local; never
/// triggers a provider refresh.
struct ResetFormatter: Sendable {
    var calendar: Calendar = .current
    var locale: Locale = .current

    /// Resets closer than this are shown as a countdown; later ones as a time.
    private static let countdownLimit: TimeInterval = 12 * 3600

    /// Compact form: `48m`, `1h 42m`, `Tomorrow 09:00`, `Fri 17:00`.
    func short(to reset: Date, now: Date) -> String {
        let interval = reset.timeIntervalSince(now)
        if interval <= 0 { return "now" }
        if interval < 60 { return "<1m" }
        if interval < Self.countdownLimit {
            let minutes = Int(interval / 60)
            let (hours, remainder) = minutes.quotientAndRemainder(dividingBy: 60)
            if hours == 0 { return "\(remainder)m" }
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }
        return absolute(reset, now: now, weekday: .abbreviated)
    }

    /// Caption form: `Resets in 1h 42m`, `Resets Fri 17:00`.
    func resetLabel(to reset: Date, now: Date) -> String {
        let interval = reset.timeIntervalSince(now)
        let text = short(to: reset, now: now)
        return interval > 0 && interval < Self.countdownLimit ? "Resets in \(text)" : "Resets \(text)"
    }

    /// Sentence form for VoiceOver and notifications:
    /// `in 1 hour, 42 minutes`, `on Friday 17:00`.
    func spoken(to reset: Date, now: Date) -> String {
        let interval = reset.timeIntervalSince(now)
        if interval < 60 { return "in less than a minute" }
        if interval < Self.countdownLimit {
            let formatter = DateComponentsFormatter()
            formatter.calendar = calendar
            formatter.unitsStyle = .full
            formatter.allowedUnits = [.hour, .minute]
            let text = formatter.string(from: (interval / 60).rounded(.down) * 60) ?? short(to: reset, now: now)
            return "in \(text)"
        }
        let text = absolute(reset, now: now, weekday: .wide)
        return text.hasPrefix("Today") || text.hasPrefix("Tomorrow") ? text.lowercasedFirst : "on \(text)"
    }

    /// `just now`, `24 sec ago`, `7 min ago`, `3h ago`, `2d ago`.
    func ago(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<5: return "just now"
        case ..<60: return "\(seconds) sec ago"
        case ..<3600: return "\(seconds / 60) min ago"
        case ..<86400: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86400)d ago"
        }
    }

    private func absolute(_ date: Date, now: Date, weekday: Date.FormatStyle.Symbol.Weekday) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let time = date.formatted(style.hour().minute())
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }
        if date.timeIntervalSince(now) < 7 * 86400 {
            style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            return "\(date.formatted(style.weekday(weekday))) \(time)"
        }
        style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return date.formatted(style.month(.abbreviated).day())
    }
}

private extension String {
    var lowercasedFirst: String {
        prefix(1).lowercased() + dropFirst()
    }
}
