import Foundation
import OSLog
import UserNotifications

/// Turns a tap on the lock-screen button into a command the app already knows
/// how to carry out.
///
/// Deliberately thin. It decides one thing — whether this response is the stop
/// button — and forwards. Everything about *how* a night ends stays in
/// `SessionStore`, where the other four ways of ending one already live.
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {

    private let onStopNight: @Sendable () -> Void

    init(onStopNight: @escaping @Sendable () -> Void) {
        self.onStopNight = onStopNight
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == NightControlNotification.stopActionIdentifier else {
            return
        }
        Log.app.info("Night ended from the lock screen")
        onStopNight()
    }

    /// Shown while Somna is in the foreground too. The banner is how someone
    /// checks the night is still running without leaving the app open on the
    /// session screen all night.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
