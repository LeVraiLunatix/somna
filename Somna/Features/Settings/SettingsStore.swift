import Foundation
import OSLog

/// Backs the settings screen.
///
/// Settings write through immediately rather than behind a Save button: there is
/// no state here worth confirming, and a Save button is one more way to lose a
/// change by navigating away.
@MainActor
@Observable
final class SettingsStore {

    /// A destructive action awaiting confirmation.
    ///
    /// Modelled rather than handled ad hoc, so no deletion path can ever skip
    /// the confirmation step by accident.
    enum PendingDeletion: Equatable, Identifiable {
        case rawAudio
        case everything

        var id: String {
            switch self {
            case .rawAudio: "rawAudio"
            case .everything: "everything"
            }
        }
    }

    /// Reads and writes through the app-wide store rather than holding a copy.
    ///
    /// A local copy is what let the theme drift: this screen saved a value the
    /// rest of the app never learned about.
    var settings: UserSettings {
        get { appSettings.settings }
        set { appSettings.update { $0 = newValue } }
    }

    private(set) var storage: StorageBreakdown = .empty
    private(set) var calibration: CalibrationProfile?
    private(set) var microphone: MicrophonePermission = .undetermined
    private(set) var notifications: NotificationPermission = .undetermined
    private(set) var isWorking = false
    private(set) var lastResult: RetentionResult?

    var pendingDeletion: PendingDeletion?

    private let environment: AppEnvironment
    private let appSettings: AppSettings

    init(environment: AppEnvironment, appSettings: AppSettings) {
        self.environment = environment
        self.appSettings = appSettings
    }

    var isCalibrationStale: Bool {
        guard let calibration else { return true }
        return calibration.isStale(now: environment.clock.now)
    }

    var appVersion: String { Bundle.main.displayVersion }
    var analysisVersion: String { AnalysisConstants.currentVersion }

    func load() async {
        microphone = await environment.permissions.microphonePermission()
        notifications = await environment.permissions.notificationPermission()
        storage = (try? await environment.storage.breakdown()) ?? .empty
        calibration = try? await environment.sessions.latestCalibration()
    }

    func requestNotifications() async {
        notifications = await environment.permissions.requestNotificationPermission()
        await environment.notifications.refresh(for: settings)
    }

    func openSystemSettings() {
        environment.permissions.openSystemSettings()
    }

    // MARK: - Destructive actions

    /// What the confirmation dialog must say before anything is removed.
    ///
    /// Built here rather than in the view so the description can never drift
    /// from what the action actually does.
    func confirmationMessage(for deletion: PendingDeletion) -> String {
        switch deletion {
        case .rawAudio:
            String(
                localized: "settings.confirm.rawAudio",
                defaultValue: "This removes \(storage.rawAudioBytes.formattedByteSize) of raw recordings. Your reports and the short clips behind each event are kept."
            )
        case .everything:
            String(
                localized: "settings.confirm.everything",
                defaultValue: "This permanently deletes all \(storage.nightCount) nights, every recording and every report. It cannot be undone."
            )
        }
    }

    func confirmPendingDeletion() async {
        guard let deletion = pendingDeletion else { return }
        pendingDeletion = nil
        isWorking = true
        defer { isWorking = false }

        switch deletion {
        case .rawAudio:
            lastResult = try? await environment.storage.eraseRawAudio()
        case .everything:
            try? await environment.storage.eraseEverything()
            lastResult = nil
        }

        environment.haptics.play(.deletionConfirmed)
        await load()
    }

    /// Applies the current retention policy now, rather than waiting for the
    /// next launch. Offered because someone who has just tightened the policy
    /// expects the space back immediately.
    func applyRetentionNow() async {
        isWorking = true
        defer { isWorking = false }

        lastResult = try? await environment.storage.applyRetention(
            settings.retentionPolicy, now: environment.clock.now
        )
        await load()
    }
}
