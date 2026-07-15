import ClaudometerCore
import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter -- fires the alerts evaluate() produces.
/// ponytail: UNUserNotificationCenter.current() *crashes* (uncaught NSException, not a Swift
/// error) outside a real .app bundle -- e.g. `swift run` during development. Bundle.main has no
/// CFBundleIdentifier in that case, so we gate every call on it. build-app.sh's Info.plist sets
/// one, so the packaged app is unaffected.
enum NotificationSender {
    private static var hasAppBundle: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard hasAppBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(_ alert: Alert) {
        guard hasAppBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = "Claudometer"
        content.body = message(for: alert)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func message(for alert: Alert) -> String {
        let windowLabel = alert.window == .fiveHour ? "5h" : "7 jours"
        switch alert.kind {
        case .saturation:
            return "Quota \(windowLabel) proche de la limite (90%)"
        case .freed:
            return "Quota \(windowLabel) de nouveau disponible"
        }
    }
}
