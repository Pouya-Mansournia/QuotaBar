import Foundation
import UserNotifications

struct UsageNotification: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
}

protocol UsageNotifying: Sendable {
    func deliver(_ notifications: [UsageNotification]) async
}

/// Builds notification text. Pure, so the wording is unit-tested.
enum NotificationComposer {
    static func compose(_ event: ThresholdEvent, now: Date, formatter: ResetFormatter = ResetFormatter()) -> UsageNotification {
        switch event {
        case .crossed(let provider, let window, let threshold):
            var body = "Your current \(window.type.spokenName) usage window is at \(UsageMath.displayPercent(window.usedPercentage))%."
            if let resetsAt = window.resetsAt, resetsAt > now {
                body += "\nReset expected \(formatter.spoken(to: resetsAt, now: now))."
            }
            return UsageNotification(
                identifier: "\(provider.rawValue).\(window.id).\(threshold)",
                title: "\(provider.displayName) usage reached \(threshold)%",
                body: body
            )
        case .reset(let provider, let window):
            return UsageNotification(
                identifier: "\(provider.rawValue).\(window.id).reset",
                title: "\(provider.displayName) \(window.type.spokenName) window reset",
                body: "Your \(window.type.spokenName) quota is available again."
            )
        }
    }
}

/// Posts native notifications through UserNotifications.
struct NotificationManager: UsageNotifying {
    enum Authorization: Sendable {
        case allowed
        case denied
        case notDetermined
    }

    func authorization() async -> Authorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional: .allowed
        case .denied: .denied
        default: .notDetermined
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func deliver(_ notifications: [UsageNotification]) async {
        guard !notifications.isEmpty, await authorization() == .allowed else { return }
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            // Reusing the identifier replaces an earlier alert for the same threshold.
            let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                AppLog.shared.error("Notification failed: \(error.localizedDescription)")
            }
        }
    }
}
