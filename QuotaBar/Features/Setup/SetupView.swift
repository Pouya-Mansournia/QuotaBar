import SwiftUI

/// First-run window: one button to connect Claude, with the macOS password
/// dialog explained before it appears.
struct SetupView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var claudeSignedIn: Bool
    @State private var isConnecting = false

    /// - Parameter claudeSignedIn: Overrides detection, for previews and screenshots.
    init(claudeSignedIn: Bool? = nil) {
        _claudeSignedIn = State(initialValue: claudeSignedIn ?? KeychainReader.hasClaudeCodeSignIn())
    }

    @State private var didCopy = false

    private static let claudeCodeSetupURL = URL(string: "https://code.claude.com/docs/en/setup")!

    /// Anthropic's installer, then `~/.local/bin` on PATH (where it installs
    /// `claude`; a fresh shell does not have it), then `claude` to sign in.
    static let installCommand = """
    curl -fsSL https://claude.ai/install.sh | bash; \
    export PATH="$HOME/.local/bin:$PATH"; \
    grep -q '.local/bin' ~/.zshrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc; \
    claude
    """

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
                Text(AppCredit.text)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                installSteps
            }
        }
    }

    /// For people who have never used Claude Code: four steps, one paste.
    private var installSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One-time setup. QuotaBar reads your usage through Claude Code, which is not on this Mac yet. Usage from the Claude app and website is included.")
                .foregroundStyle(.secondary)

            Label("Copy the setup command.", systemImage: "1.circle")
            HStack {
                Button(didCopy ? "Copied" : "Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.installCommand, forType: .string)
                    didCopy = true
                }
                Button("Open Terminal") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                }
            }
            .padding(.leading, 24)

            Label("In Terminal, press ⌘V, then Return. Wait for it to finish.", systemImage: "2.circle")
            Label("Sign in with your Claude account when the browser opens.", systemImage: "3.circle")
            Label("Come back here and click Check Again.", systemImage: "4.circle")
            HStack {
                Button("Check Again") { claudeSignedIn = KeychainReader.hasClaudeCodeSignIn() }
                Button("Install Guide") { NSWorkspace.shared.open(Self.claudeCodeSetupURL) }
                    .buttonStyle(.link)
            }
            .padding(.leading, 24)
        }
        .fixedSize(horizontal: false, vertical: true)
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
