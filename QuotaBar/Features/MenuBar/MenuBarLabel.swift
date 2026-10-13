import SwiftUI

/// Pure text/symbol logic for the menu bar item, separated for testing.
enum MenuBarTitle {
    static let unknown = "–"

    /// - Parameter percentages: Primary-window percentage per enabled provider;
    ///   a nil value means the provider is enabled but has no data.
    static func text(
        style: MenuBarStyle,
        percentages: [(provider: AIProvider, value: Double?)],
        highest: Double?
    ) -> String? {
        func format(_ value: Double?) -> String {
            value.map { "\(UsageMath.displayPercent($0))" } ?? unknown
        }
        func single(_ provider: AIProvider) -> String? {
            guard let entry = percentages.first(where: { $0.provider == provider }) else { return nil }
            return entry.value == nil ? unknown : format(entry.value) + "%"
        }

        switch style {
        case .iconOnly:
            return nil
        case .claude:
            return single(.claude)
        case .codex:
            return single(.codex)
        case .both:
            guard !percentages.isEmpty else { return nil }
            return percentages
                .map { "\($0.provider.shortCode) \(format($0.value))" }
                .joined(separator: " · ")
        case .highest:
            return highest == nil ? unknown : format(highest) + "%"
        }
    }

    static func symbolName(highest: Double?) -> String {
        switch highest ?? 0 {
        case ..<17: "gauge.with.dots.needle.0percent"
        case ..<42: "gauge.with.dots.needle.33percent"
        case ..<59: "gauge.with.dots.needle.50percent"
        case ..<84: "gauge.with.dots.needle.67percent"
        default: "gauge.with.dots.needle.100percent"
        }
    }
}

struct MenuBarLabel: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let now = Date()
        let store = environment.store
        let settings = environment.settings
        let highest = store.highestPercentage(at: now)
        let title = MenuBarTitle.text(
            style: settings.menuBarStyle,
            percentages: settings.enabledProviders.map { ($0, store.primaryPercentage(for: $0, at: now)) },
            highest: highest
        )

        HStack(spacing: 4) {
            Image(systemName: MenuBarTitle.symbolName(highest: highest))
            if let title {
                Text(title).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(highest: highest))
    }

    private func accessibilityLabel(highest: Double?) -> String {
        guard let highest else { return "QuotaBar, no usage data" }
        return "QuotaBar, highest usage \(UsageMath.displayPercent(highest)) percent"
    }
}
