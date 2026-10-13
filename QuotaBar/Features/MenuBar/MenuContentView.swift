import SwiftUI

struct MenuContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private let formatter = ResetFormatter()

    var body: some View {
        // Countdowns and "updated … ago" advance locally; no provider is queried.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            content(now: context.date)
        }
        .frame(width: 320)
    }

    private func content(now: Date) -> some View {
        let store = environment.store
        let settings = environment.settings

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI Usage")
                    .font(.headline)
                if environment.isMockModeActive {
                    Text("MOCK")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                }
                Spacer()
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if settings.enabledProviders.isEmpty {
                Text("No providers enabled. Turn one on in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
            ForEach(settings.enabledProviders) { provider in
                ProviderCardView(
                    provider: provider,
                    snapshot: store.snapshot(for: provider),
                    now: now,
                    showIcon: settings.showProviderIcons,
                    showWeekly: settings.showWeeklyQuota,
                    showCountdown: settings.showResetCountdown
                )
                Divider()
            }

            Text(updatedText(now: now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            VStack(spacing: 0) {
                MenuRowButton(title: "Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r")
                .disabled(store.isRefreshing)

                MenuRowButton(title: "Usage History…", systemImage: "chart.xyaxis.line") {
                    openWindow(id: WindowID.history)
                    NSApp.activate(ignoringOtherApps: true)
                }

                MenuRowButton(title: "Settings…", systemImage: "gearshape") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",")

                MenuRowButton(title: "Quit QuotaBar", systemImage: "power") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
    }

    private func updatedText(now: Date) -> String {
        guard let lastRefresh = environment.store.lastRefresh else {
            return environment.store.isRefreshing ? "Updating…" : "Not updated yet"
        }
        return "Updated \(formatter.ago(lastRefresh, now: now))"
    }
}

/// A full-width button that highlights on hover, like a menu item.
struct MenuRowButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .primary : .tertiary)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered && isEnabled ? Color.primary.opacity(0.1) : .clear)
        )
        .onHover { isHovered = $0 }
    }
}
