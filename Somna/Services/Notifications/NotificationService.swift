import Foundation
import OSLog
import UserNotifications

protocol NotificationScheduling: Sendable {
    /// Rebuilds every scheduled notification from the current settings.
    func refresh(for settings: UserSettings) async
    func cancelAll() async
    /// Tells the user their report is ready. Only ever sent after a real analysis.
    func notifyReportReady(sessionID: UUID) async
}

/// Local notifications.
///
/// Everything here is *local*: no push, no server, no account. That is also what
/// makes it work on a free Apple account, where remote push is unavailable.
///
/// **Tone is a design constraint, not a copy detail.** A sleep app that nags is
/// an app people delete. Nothing here implies the user did something wrong, and
/// no reminder says anything about how they slept — Somna does not know.
struct NotificationService: NotificationScheduling {

    private enum Identifier {
        static let eveningReminder = "somna.reminder.evening"
        static let morningSummary = "somna.summary.morning"
        static let weeklyReport = "somna.report.weekly"
        static let reportReady = "somna.report.ready"
    }

    func refresh(for settings: UserSettings) async {
        let center = UNUserNotificationCenter.current()

        // Rebuilt from scratch rather than patched: a settings screen that
        // toggles four switches would otherwise need to reason about which
        // combination it came from.
        center.removePendingNotificationRequests(withIdentifiers: [
            Identifier.eveningReminder,
            Identifier.morningSummary,
            Identifier.weeklyReport,
        ])

        guard await isAuthorised() else { return }

        if settings.eveningReminderEnabled {
            await schedule(
                identifier: Identifier.eveningReminder,
                title: String(localized: "notification.evening.title",
                              defaultValue: "Somna is ready for tonight"),
                body: String(localized: "notification.evening.body",
                             defaultValue: "Plug your iPhone in and put it near the bed whenever you are ready."),
                at: DateComponents(
                    hour: settings.eveningReminderMinutes / 60,
                    minute: settings.eveningReminderMinutes % 60
                )
            )
        }

        if settings.morningSummaryEnabled {
            await schedule(
                identifier: Identifier.morningSummary,
                title: String(localized: "notification.morning.title",
                              defaultValue: "Your night is ready to read"),
                body: String(localized: "notification.morning.body",
                             defaultValue: "Somna has finished going over what it heard."),
                at: DateComponents(hour: 8, minute: 0)
            )
        }

        if settings.weeklyReportEnabled {
            await schedule(
                identifier: Identifier.weeklyReport,
                title: String(localized: "notification.weekly.title",
                              defaultValue: "Your week in sound"),
                body: String(localized: "notification.weekly.body",
                             defaultValue: "Seven nights of trends are waiting for you."),
                at: DateComponents(hour: 9, minute: 0, weekday: 1)
            )
        }
    }

    func cancelAll() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func notifyReportReady(sessionID: UUID) async {
        guard await isAuthorised() else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.ready.title",
                               defaultValue: "Your night report is ready")
        content.body = String(localized: "notification.ready.body",
                              defaultValue: "Open Somna to see what it heard.")
        content.sound = .default
        // The session identifier lets the app open straight onto the right night.
        content.userInfo = ["sessionID": sessionID.uuidString]

        let request = UNNotificationRequest(
            identifier: "\(Identifier.reportReady).\(sessionID.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private func isAuthorised() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    private func schedule(
        identifier: String,
        title: String,
        body: String,
        at components: DateComponents
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // No sound on recurring reminders: one of them fires in the evening, when
        // someone may already be asleep.
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Log.notifications.error("A reminder could not be scheduled")
        }
    }
}

/// Notifications that go nowhere, for previews and tests.
struct StubNotificationService: NotificationScheduling {
    func refresh(for settings: UserSettings) async {}
    func cancelAll() async {}
    func notifyReportReady(sessionID: UUID) async {}
}
