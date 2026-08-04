import Foundation
import OSLog
import UserNotifications

protocol NotificationScheduling: Sendable {
    /// Rebuilds every scheduled notification from the current settings.
    func refresh(for settings: UserSettings) async
    func cancelAll() async
    /// Tells the user their report is ready. Only ever sent after a real analysis.
    func notifyReportReady(sessionID: UUID) async
    /// Puts the running night on the lock screen, with the button that ends it.
    func showNightRunning() async
    func hideNightRunning() async
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

    let sessions: any NightSessionRepositing

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

        // The morning summary is deliberately **not** scheduled here.
        //
        // It used to be a daily repeating notification at 08:00 announcing that
        // a report was ready — every morning, whether a night had been recorded
        // or not. For an app whose entire premise is never claiming more than
        // the data supports, telling someone their night is ready when no night
        // exists was the worst defect in the project.
        //
        // It is now sent by `notifyReportReady(sessionID:)`, from the analysis
        // pipeline, when a report genuinely exists. No time to configure either:
        // it arrives when it is true.

        // The weekly report is only scheduled once there is something to report
        // on. The same reasoning, one week at a time.
        if settings.weeklyReportEnabled, await hasRecordedNights() {
            await schedule(
                identifier: Identifier.weeklyReport,
                title: String(localized: "notification.weekly.title",
                              defaultValue: "Your week in sound"),
                body: String(localized: "notification.weekly.body",
                             defaultValue: "Your recorded nights are waiting in Trends."),
                at: DateComponents(
                    hour: settings.weeklyReportMinutes / 60,
                    minute: settings.weeklyReportMinutes % 60,
                    weekday: 1
                )
            )
        }
    }

    private func hasRecordedNights() async -> Bool {
        ((try? await sessions.sessions(limit: 1, offset: 0)) ?? []).isEmpty == false
    }

    func cancelAll() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Posted when a night starts, removed when it ends.
    ///
    /// Delivered immediately rather than on a trigger, so it is already on the
    /// lock screen by the time the phone goes down — the moment someone is most
    /// likely to want to check that the night really started.
    func showNightRunning() async {
        guard await isAuthorised() else { return }
        let request = UNNotificationRequest(
            identifier: NightControlNotification.requestIdentifier,
            content: NightControlNotification.content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // A missing lock-screen control does not justify failing a night.
            // The in-app stop button is unaffected.
            Log.app.error("Could not show the night control: \(error.localizedDescription, privacy: .public)")
        }
    }

    func hideNightRunning() async {
        let center = UNUserNotificationCenter.current()
        let identifiers = [NightControlNotification.requestIdentifier]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        // Removing it from Notification Center too: a button offering to end a
        // night that ended hours ago is worse than no button.
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Sent only when a report actually exists, and only if the user asked for it.
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
    func showNightRunning() async {}
    func hideNightRunning() async {}
}
