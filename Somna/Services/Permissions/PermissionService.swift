import AVFoundation
import Foundation
import OSLog
import UIKit
import UserNotifications

/// Real permission handling.
///
/// Somna only ever asks for the microphone *after* explaining why, in the
/// onboarding. iOS grants exactly one prompt per permission for the lifetime of
/// an install: spending it before the user understands the app is how recording
/// apps end up permanently denied by people who would have said yes.
struct PermissionService: PermissionRequesting {

    // MARK: - Microphone

    func microphonePermission() async -> MicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: .undetermined
        case .granted: .granted
        case .denied:
            // iOS reports one `denied` state, but once it is set the system will
            // never prompt again — so from the app's point of view it is always
            // the permanent kind, and the UI must route to Settings.
            .permanentlyDenied
        @unknown default: .denied
        }
    }

    func requestMicrophonePermission() async -> MicrophonePermission {
        let current = await microphonePermission()
        guard current == .undetermined else { return current }

        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        Log.privacy.info("Microphone permission resolved: \(granted ? "granted" : "denied", privacy: .public)")
        return granted ? .granted : .permanentlyDenied
    }

    // MARK: - Notifications

    func notificationPermission() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return switch settings.authorizationStatus {
        case .notDetermined: .undetermined
        case .authorized, .ephemeral: .granted
        case .provisional: .provisional
        case .denied: .denied
        @unknown default: .denied
        }
    }

    func requestNotificationPermission() async -> NotificationPermission {
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // A refusal is a valid outcome, not a failure worth surfacing:
            // notifications are optional in Somna and nothing depends on them.
            Log.notifications.info("Notification authorisation request ended without approval")
        }
        return await notificationPermission()
    }

    // MARK: - Settings

    @MainActor
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            Log.app.error("Settings URL could not be constructed")
            return
        }
        UIApplication.shared.open(url)
    }
}

/// Permissions with fixed answers, for previews and tests.
struct StubPermissionService: PermissionRequesting {

    let microphone: MicrophonePermission
    let notifications: NotificationPermission

    init(
        microphone: MicrophonePermission = .granted,
        notifications: NotificationPermission = .granted
    ) {
        self.microphone = microphone
        self.notifications = notifications
    }

    func microphonePermission() async -> MicrophonePermission { microphone }
    func requestMicrophonePermission() async -> MicrophonePermission { microphone }
    func notificationPermission() async -> NotificationPermission { notifications }
    func requestNotificationPermission() async -> NotificationPermission { notifications }
    @MainActor func openSystemSettings() {}
}
