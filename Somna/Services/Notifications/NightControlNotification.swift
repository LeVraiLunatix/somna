import Foundation
import OSLog
import UserNotifications

/// The notification that sits on the lock screen while a night is recording,
/// and the button on it that ends the night.
///
/// **Why not a Live Activity.** A Live Activity is the right control for this
/// and costs an App Extension: a separate binary, with its own bundle ID and its
/// own provisioning profile. A free Apple account can activate three apps *and
/// extensions* at once, and AltStore already holds one of them. Somna would take
/// two of the three slots, so every tester would have to give something up to
/// install it. For a public beta distributed this way, that is not a trade the
/// feature is worth.
///
/// **Why not Now Playing.** `MPRemoteCommandCenter` would put a stop button on
/// the lock screen with no extension at all — but only for an app iOS considers
/// to be playing, which means moving the recording session from `.record` to
/// `.playAndRecord`. Somna would then occupy the Now Playing slot all night:
/// it would take over the headphone play/pause button and displace whatever the
/// user actually fell asleep to. Declaring itself a media player to borrow a
/// media player's button is the kind of half-truth this app does not tell.
///
/// A notification action costs nothing, is handled in the background, and needs
/// no unlock. It is less pretty than a Live Activity and it is honest about what
/// it is.
enum NightControlNotification {

    static let categoryIdentifier = "somna.night.running"
    static let stopActionIdentifier = "somna.night.stop"
    static let requestIdentifier = "somna.night.running.request"

    /// Registered once at launch, not when a night starts: iOS matches a
    /// delivered notification against the categories it knows about *at that
    /// moment*, and a category registered late gives a notification with no
    /// buttons on it.
    static var category: UNNotificationCategory {
        let stop = UNNotificationAction(
            identifier: stopActionIdentifier,
            title: String(localized: "notification.night.stop", defaultValue: "End the night"),
            // No `.foreground`: the app must not be brought to the front at
            // 4 a.m. No `.authenticationRequired`: needing Face ID to stop a
            // recording defeats the point of a lock-screen button.
            options: [.destructive]
        )
        return UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [stop],
            intentIdentifiers: [],
            options: []
        )
    }

    static var content: UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.night.title",
                               defaultValue: "Somna is listening")
        content.body = String(localized: "notification.night.body",
                              defaultValue: "Press and hold this notification to end the night without unlocking.")
        content.categoryIdentifier = categoryIdentifier
        // Silent and dark. This arrives as someone is falling asleep; a sound or
        // a lit screen would make the app that watches the night the reason the
        // night starts badly.
        content.sound = nil
        content.interruptionLevel = .passive
        return content
    }
}
