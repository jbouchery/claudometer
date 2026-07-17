import ClaudometerCore
import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter -- fires the alerts evaluate() produces.
/// ponytail: UNUserNotificationCenter.current() *crashes* (uncaught NSException, not a Swift
/// error) outside a real .app bundle -- e.g. `swift run` during development. Bundle.main has no
/// CFBundleIdentifier in that case, so we gate every call on it. build-app.sh's Info.plist sets
/// one, so the packaged app is unaffected.
/// Without a delegate, macOS silently drops the banner whenever the posting app is the
/// active app -- which is always the case right after clicking our own menu (test button),
/// and can be the case for real alerts too. willPresent forces the banner regardless.
private final class BannerAlwaysDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BannerAlwaysDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

enum NotificationSender {
    private static var hasAppBundle: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard hasAppBundle else { return }
        UNUserNotificationCenter.current().delegate = BannerAlwaysDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(_ alert: Alert) {
        guard hasAppBundle else { return }
        deliver(message(for: alert))
    }

    /// Manual test path (Help menu): re-requests authorization if undetermined, then sends.
    /// If nothing shows up, the fix is System Settings → Notifications → Claudometer.
    static func sendTest() {
        guard hasAppBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { deliver("Test notification -- alerts are working") }
        }
    }

    private static func deliver(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Claudometer"
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func message(for alert: Alert) -> String {
        let windowLabel = alert.window == .fiveHour ? "5h" : "7-day"
        switch alert.kind {
        case .saturation:
            return "\(windowLabel) quota is near its limit (90%)"
        case .freed:
            return "\(windowLabel) quota is available again"
        case .earlyReset:
            return "\(windowLabel) quota was reset early by Anthropic"
        }
    }
}
