import SwiftUI

/// The reusable per-provider block in the menu.
struct ProviderCardView: View {
    let provider: AIProvider
    let snapshot: ProviderSnapshot
    let now: Date
    let showIcon: Bool
    let showWeekly: Bool
    let showCountdown: Bool

    private let formatter = ResetFormatter()
    /// Readings older than this get an explicit age, even when the refresh succeeded.
    private static let agedAfter: TimeInterval = 10 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let usage = snapshot.usage {
                ForEach(visibleWindows(of: usage)) { window in
                    UsageRowView(provider: provider, window: window, now: now, showCountdown: showCountdown)
                }
                freshness(of: usage)
            } else {
                unavailable
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if showIcon {
                Image(systemName: provider.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
            Text(provider.displayName)
                .font(.subheadline.weight(.semibold))
            if let plan = snapshot.usage?.planName {
                Text(plan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // With no reading, the body already says "Unavailable".
            if snapshot.state != .connected, snapshot.usage != nil || snapshot.state != .unavailable {
                Text(snapshot.state.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Unavailable")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let error = snapshot.lastError {
                Text(error.userMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func freshness(of usage: ProviderUsage) -> some View {
        if snapshot.isStale {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text("Data may be stale · Updated \(formatter.ago(usage.updatedAt, now: now))")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                if let error = snapshot.lastError {
                    Text(error.userMessage)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        } else if now.timeIntervalSince(usage.updatedAt) > Self.agedAfter {
            Text("Last reported \(formatter.ago(usage.updatedAt, now: now))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func visibleWindows(of usage: ProviderUsage) -> [UsageWindow] {
        // Never hide a provider's only window.
        let filtered = usage.windows.filter { showWeekly || $0.type != .weekly }
        return filtered.isEmpty ? usage.windows : filtered
    }
}
