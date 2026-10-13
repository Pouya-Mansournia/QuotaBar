import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ProviderSettingsTab(provider: .claude)
                .tabItem { Label("Claude", systemImage: AIProvider.claude.symbolName) }
            ProviderSettingsTab(provider: .codex)
                .tabItem { Label("OpenAI / Codex", systemImage: AIProvider.codex.symbolName) }
            NotificationSettingsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }
            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettingsTab: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var launchAtLogin = false
    @State private var launchError: String?

    var body: some View {
        @Bindable var settings = environment.settings

        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Menu Bar") {
                Picker("Display style", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Show provider icons", isOn: $settings.showProviderIcons)
                Toggle("Show weekly quota", isOn: $settings.showWeeklyQuota)
                Toggle("Show reset countdown", isOn: $settings.showResetCountdown)
            }

            Section("Data") {
                Picker("Refresh interval", selection: $settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Keep history for", selection: $settings.historyRetention) {
                    ForEach(HistoryRetention.allCases) { Text($0.displayName).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = environment.launchAtLogin.isEnabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != environment.launchAtLogin.isEnabled else { return }
        do {
            try environment.launchAtLogin.setEnabled(enabled)
            launchError = environment.launchAtLogin.requiresApproval
                ? "Approve QuotaBar in System Settings > General > Login Items."
                : nil
        } catch {
            launchError = "Could not change the login item: \(error.localizedDescription)"
            launchAtLogin = environment.launchAtLogin.isEnabled
        }
    }
}

/// The 80 / 90 / 95 % switches for one provider.
struct ThresholdToggles: View {
    @Environment(AppEnvironment.self) private var environment
    let provider: AIProvider

    var body: some View {
        ForEach(AppSettings.availableThresholds, id: \.self) { threshold in
            Toggle(threshold >= 95 ? "\(threshold)% critical" : "\(threshold)% warning", isOn: binding(for: threshold))
        }
    }

    private func binding(for threshold: Int) -> Binding<Bool> {
        let settings = environment.settings
        return Binding(
            get: { settings.thresholds(for: provider).contains(threshold) },
            set: { settings.setThreshold(threshold, enabled: $0, for: provider) }
        )
    }
}

struct NotificationSettingsTab: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var authorization: NotificationManager.Authorization = .notDetermined

    var body: some View {
        @Bindable var settings = environment.settings

        Form {
            Section {
                Toggle("Enable notifications", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            await environment.notifications.requestAuthorization()
                            authorization = await environment.notifications.authorization()
                        }
                    }
                Toggle("Notify when a quota window resets", isOn: $settings.notifyOnReset)
                if authorization == .denied {
                    LabeledContent("Notifications are turned off for QuotaBar in System Settings.") {
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .font(.callout)
                }
            } footer: {
                Text("Each threshold alerts once per quota window.")
            }

            ForEach(AIProvider.allCases) { provider in
                Section(provider.displayName) {
                    ThresholdToggles(provider: provider)
                }
                .disabled(!settings.notificationsEnabled)
            }
        }
        .formStyle(.grouped)
        .task { authorization = await environment.notifications.authorization() }
    }
}

struct AdvancedSettingsTab: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isTesting = false
    @State private var testResults: [String] = []
    @State private var message: String?

    var body: some View {
        @Bindable var settings = environment.settings

        Form {
            Section {
                Toggle("Debug logging", isOn: $settings.debugLogging)
                #if DEBUG
                Toggle("Mock mode (development builds only)", isOn: $settings.mockMode)
                #endif
            }

            Section("Maintenance") {
                LabeledContent("Provider refresh test") {
                    Button(isTesting ? "Testing…" : "Run Test") { runTest() }
                        .disabled(isTesting)
                }
                ForEach(testResults, id: \.self) { line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Diagnostics report") {
                    Button("Export…") { exportDiagnostics() }
                }
                LabeledContent("Cached usage, alert state and history") {
                    Button("Reset Cache") {
                        Task {
                            await environment.store.resetCache()
                            message = "Cache reset."
                        }
                    }
                }
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runTest() {
        isTesting = true
        Task {
            await environment.store.refresh()
            testResults = AIProvider.allCases.map { provider in
                guard environment.settings.isEnabled(provider) else {
                    return "\(provider.displayName): disabled"
                }
                let snapshot = environment.store.snapshot(for: provider)
                if let error = snapshot.lastError {
                    return "\(provider.displayName): \(snapshot.state.displayName) — \(error.userMessage)"
                }
                let windows = snapshot.usage?.windows
                    .map { "\($0.shortName) \(UsageMath.displayPercent($0.usedPercentage))%" }
                    .joined(separator: ", ") ?? "no data"
                return "\(provider.displayName): Connected — \(windows)"
            }
            isTesting = false
        }
    }

    private func exportDiagnostics() {
        Task {
            let report = await environment.diagnosticsReport()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "QuotaBar-Diagnostics.txt"
            panel.allowedContentTypes = [.plainText]
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try Data(report.utf8).write(to: url, options: .atomic)
                message = "Diagnostics exported."
            } catch {
                message = "Could not save the report: \(error.localizedDescription)"
            }
        }
    }
}
