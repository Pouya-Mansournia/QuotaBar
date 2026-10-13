import SwiftUI

struct ProviderSettingsTab: View {
    @Environment(AppEnvironment.self) private var environment
    let provider: AIProvider

    @State private var bridgeInstalled = false
    @State private var bridgeMessage: String?

    var body: some View {
        let settings = environment.settings
        let snapshot = environment.store.snapshot(for: provider)

        Form {
            Section {
                Toggle("Enable \(provider.displayName)", isOn: Binding(
                    get: { settings.isEnabled(provider) },
                    set: { settings.setEnabled($0, for: provider) }
                ))
                LabeledContent("Connection status") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(settings.isEnabled(provider) ? snapshot.state.displayName : "Disabled")
                        if settings.isEnabled(provider), let error = snapshot.lastError {
                            Text(error.userMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Last successful refresh") {
                    Text(snapshot.lastSuccess.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                }
                LabeledContent("Data source") {
                    Text(environment.dataSource(for: provider))
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if provider == .claude {
                accountSection
                if !settings.claudeUseAccountAPI {
                    bridgeSection
                }
            }

            Section("Notification thresholds") {
                ThresholdToggles(provider: provider)
            }

            Section("Limitations") {
                Text(limitations)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear { bridgeInstalled = environment.bridge.isInstalled() }
    }

    private var accountSection: some View {
        @Bindable var settings = environment.settings

        return Section {
            Toggle("Read usage from my Anthropic account", isOn: $settings.claudeUseAccountAPI)
        } header: {
            Text("Data Source")
        } footer: {
            Text("""
            Shows the same numbers as Claude Code's Account & Usage panel, including usage from the \
            VS Code extension and claude.ai. QuotaBar reads Claude Code's sign-in token from the Keychain \
            (macOS asks you to allow this) and sends it only to api.anthropic.com. The token is never \
            stored or logged. This endpoint is not officially documented and may change.
            """)
        }
    }

    private var bridgeSection: some View {
        Section {
            LabeledContent("Status line bridge") {
                Button(bridgeInstalled ? "Remove" : "Install") { toggleBridge() }
            }
            if let bridgeMessage {
                Text(bridgeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Claude Code Integration")
        } footer: {
            Text("""
            The alternative without credentials or network access. Installing adds a small script as \
            `statusLine` in ~/.claude/settings.json that saves the limits locally. It updates only while \
            Claude Code runs in a terminal, not in the VS Code extension. An existing status line keeps \
            working, and a backup of the settings file is kept.
            """)
        }
    }

    private func toggleBridge() {
        do {
            if bridgeInstalled {
                try environment.bridge.uninstall()
                bridgeMessage = "Removed. Your previous status line was restored."
            } else {
                try environment.bridge.install()
                bridgeMessage = "Installed. Usage appears after your next message in Claude Code."
            }
        } catch {
            bridgeMessage = error.localizedDescription
        }
        bridgeInstalled = environment.bridge.isInstalled()
        Task { await environment.store.refresh() }
    }

    private var limitations: String {
        switch provider {
        case .claude where environment.settings.claudeUseAccountAPI:
            """
            Requires Claude Code to be signed in with a Claude subscription. QuotaBar never renews the \
            sign-in itself; if it expires, open Claude Code once. The account is checked at most every \
            two minutes. Token counts and cost are not provided by this source.
            """
        case .claude:
            """
            Values update while Claude Code is running in a terminal, and only for Pro and Max \
            subscriptions. Usage from claude.ai or other devices appears the next time Claude Code \
            reports. Token counts and cost are not provided by this source.
            """
        case .codex:
            """
            Values come from the most recent Codex CLI session on this Mac, so they update when Codex \
            is used here. Usage from ChatGPT or other devices appears the next time Codex runs. Token \
            limits and cost are not provided by this source.
            """
        }
    }
}
