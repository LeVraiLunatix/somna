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

    /// No banner while Somna is in front.
    ///
    /// A banner over Somna's own screens tells nobody anything they cannot
    /// already see — the session screen shows the running night better than a
    /// notification about it does — and it covers the app to do so. It goes to
    /// Notification Center and the lock screen, which is where it is useful.
    ///
    /// This is not cosmetic. Before this delegate existed iOS suppressed
    /// foreground notifications by default; asking for banners made one appear
    /// over whichever screen happened to be up, and the accessibility audit
    /// started failing on a different screen each run with an issue it could not
    /// attribute to any element.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.list]
    }
}
