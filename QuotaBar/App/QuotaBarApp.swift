import SwiftUI

@main
struct QuotaBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment

    init() {
        let environment = AppEnvironment()
        _environment = State(initialValue: environment)
        environment.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(environment)
        } label: {
            MenuBarLabel()
                .environment(environment)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(environment)
        }

        Window("Usage History", id: WindowID.history) {
            HistoryView()
                .environment(environment)
        }
        .defaultSize(width: 640, height: 420)
        .windowResizability(.contentMinSize)
    }
}

enum WindowID {
    static let history = "history"
}
