#if DEBUG
import Foundation

/// Fixed sample data for UI development. Compiled into Debug builds only, and
/// used only when "Mock mode" is switched on in Settings > Advanced.
struct MockUsageProvider: UsageProvider {
    let provider: AIProvider
    let dataSourceDescription = "Mock data (development only)"

    func fetchUsage() async throws -> ProviderUsage {
        let now = Date()
        let windows: [UsageWindow]
        switch provider {
        case .claude:
            windows = [
                UsageWindow(type: .fiveHour, usedPercentage: 68, resetsAt: now.addingTimeInterval(102 * 60)),
                UsageWindow(type: .weekly, usedPercentage: 31, resetsAt: now.addingTimeInterval(3 * 86400)),
            ]
        case .codex:
            windows = [
                UsageWindow(type: .fiveHour, usedPercentage: 42, resetsAt: now.addingTimeInterval(191 * 60)),
                UsageWindow(type: .weekly, usedPercentage: 18, resetsAt: now.addingTimeInterval(5 * 86400)),
            ]
        }
        return ProviderUsage(provider: provider, windows: windows, updatedAt: now, planName: "Mock")
    }
}
#endif
