import SwiftUI

/// First-run window: one button to connect Claude, with the macOS password
/// dialog explained before it appears.
struct SetupView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var claudeSignedIn = KeychainReader.hasClaudeCodeSignIn()
    @State private var isConnecting = false

    private static let claudeCodeSetupURL = URL(string: "https://code.claude.com/docs/en/setup")!

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to QuotaBar")
                    .font(.title2.weight(.semibold))
                Text("QuotaBar lives in the menu bar and shows how much of your AI usage limits is left.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox {
                claudeStep
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }

            GroupBox {
                codexStep
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }

            HStack {
                Spacer()
                Button("Done") {
                    environment.settings.hasCompletedSetup = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onDisappear { environment.settings.hasCompletedSetup = true }
    }

    // MARK: Claude

    @ViewBuilder
    private var claudeStep: some View {
        let snapshot = environment.store.snapshot(for: .claude)

        VStack(alignment: .leading, spacing: 10) {
            stepTitle("Claude", symbol: AIProvider.claude.symbolName, connected: snapshot.usage != nil && snapshot.lastError == nil)

            if let usage = snapshot.usage, snapshot.lastError == nil {
                Text(summary(of: usage))
                    .foregroundStyle(.secondary)
            } else if claudeSignedIn {
                passwordHint
                HStack(spacing: 10) {
                    Button(isConnecting ? "Connecting…" : "Connect Claude") { connect() }
                        .disabled(isConnecting)
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    }
                }
                if !isConnecting, environment.settings.claudeUseAccountAPI, let error = snapshot.lastError {
                    Label(error.userMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("""
                QuotaBar reads Claude usage through Claude Code. It is not signed in on this Mac yet. \
                Install Claude Code and sign in once with the same account you use on claude.ai; your \
                usage from the Claude app and website is included.
                """)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Install Guide") { NSWorkspace.shared.open(Self.claudeCodeSetupURL) }
                    Button("Check Again") { claudeSignedIn = KeychainReader.hasClaudeCodeSignIn() }
                }
            }
        }
    }

    /// Shown before the system dialog, which gives no context of its own.
    private var passwordHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("When you click Connect, macOS asks for a password:")
            Label("Type the password you use to unlock this Mac.", systemImage: "1.circle")
            Label("Click Always Allow.", systemImage: "2.circle")
            Text("This lets QuotaBar read your Claude sign-in to check your usage with Anthropic. Nothing is sent anywhere else.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func connect() {
        isConnecting = true
        Task {
            await environment.connectClaudeAccount()
            isConnecting = false
        }
    }

    // MARK: Codex

    private var codexStep: some View {
        let snapshot = environment.store.snapshot(for: .codex)

        return VStack(alignment: .leading, spacing: 6) {
            stepTitle("Codex", symbol: AIProvider.codex.symbolName, connected: snapshot.usage != nil)
            if let usage = snapshot.usage {
                Text(summary(of: usage))
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing to set up. Usage appears here once the Codex CLI has been used on this Mac. If you don't use Codex, turn it off in Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Shared

    private func stepTitle(_ title: String, symbol: String, connected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Spacer()
            if connected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
    }

    private func summary(of usage: ProviderUsage) -> String {
        usage.windows
            .map { "\($0.shortName) \(UsageMath.displayPercent($0.usedPercentage))%" }
            .joined(separator: " · ")
    }
}
