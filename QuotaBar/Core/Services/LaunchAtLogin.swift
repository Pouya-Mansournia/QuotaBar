import Foundation
import ServiceManagement

/// Launch at login through `SMAppService`, the supported macOS 13+ API.
@MainActor
struct LaunchAtLogin {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user must approve the login item in System Settings.
    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}
