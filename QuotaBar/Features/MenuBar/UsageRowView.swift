import SwiftUI

extension UsageLevel {
    /// System colors, so the bars adapt to Light/Dark Mode and Increase Contrast.
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .yellow
        case .high: .orange
        case .critical: .red
        }
    }
}

enum UsageAccessibility {
    /// e.g. "Claude five-hour usage, 68 percent, resets in 1 hour, 42 minutes"
    static func label(
        provider: AIProvider,
        window: UsageWindow,
        now: Date,
        formatter: ResetFormatter = ResetFormatter()
    ) -> String {
        let name = window.label ?? window.type.spokenName
        var parts = ["\(provider.displayName) \(name) usage"]
        if window.isExpired(at: now) {
            parts.append("window has reset, waiting for new data")
        } else {
            parts.append("\(UsageMath.displayPercent(window.usedPercentage)) percent")
            if let resetsAt = window.resetsAt {
                parts.append("resets \(formatter.spoken(to: resetsAt, now: now))")
            }
        }
        return parts.joined(separator: ", ")
    }
}

/// A thin capsule meter coloured by usage level. Drawn directly so the level
/// colour stays visible whether or not the menu's window is key.
struct UsageBar: View {
    let percentage: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                // Below 1% the label reads 0%, so the bar stays empty too.
                if percentage >= 1 {
                    Capsule()
                        .fill(UsageLevel(percentage: percentage).color)
                        .frame(width: max(proxy.size.height, proxy.size.width * percentage / 100))
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// One quota window: name, percentage, bar and reset caption.
struct UsageRowView: View {
    let provider: AIProvider
    let window: UsageWindow
    let now: Date
    let showCountdown: Bool

    private let formatter = ResetFormatter()

    var body: some View {
        let percentage = window.effectivePercentage(at: now)
        let expired = window.isExpired(at: now)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.shortName)
                Spacer()
                Text("\(UsageMath.displayPercent(percentage))%")
                    .monospacedDigit()
                    .fontWeight(.medium)
            }
            .font(.callout)

            UsageBar(percentage: percentage)

            if expired {
                caption("Window reset · waiting for new data")
            } else if showCountdown, let resetsAt = window.resetsAt {
                caption(formatter.resetLabel(to: resetsAt, now: now))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UsageAccessibility.label(provider: provider, window: window, now: now))
        .accessibilityValue("\(UsageLevel(percentage: percentage).description) level")
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
