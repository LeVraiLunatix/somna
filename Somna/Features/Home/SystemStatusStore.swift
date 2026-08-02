import Foundation
import OSLog

/// Backs the readiness screen.
///
/// `@MainActor` explicitly, per the isolation convention: the app's default
/// isolation is `nonisolated`, so anything that drives a view says so.
@MainActor
@Observable
final class SystemStatusStore {

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(SomnaError)
    }

    private(set) var state: LoadState = .loading

    private(set) var microphone: MicrophonePermission = .undetermined
    private(set) var notifications: NotificationPermission = .undetermined
    private(set) var availableCapacity: Int64 = 0
    private(set) var storedNightCount = 0
    private(set) var unfinishedNightCount = 0
    private(set) var calibration: CalibrationProfile?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Whether a night could be recorded right now, and why not if it could not.
    var blockingIssue: SomnaError? {
        if !microphone.allowsRecording {
            return .microphoneAccessDenied
        }
        if availableCapacity < AudioConstants.minimumFreeSpaceToRecord {
            return .insufficientStorage(
                requiredBytes: AudioConstants.minimumFreeSpaceToRecord,
                availableBytes: availableCapacity
            )
        }
        return nil
    }

    /// Roughly how many hours of recording the free space allows, so the number
    /// means something to a person deciding whether to start a session.
    var estimatedRecordableHours: Int {
        max(0, Int(availableCapacity.estimatedRecordingHours))
    }

    var isCalibrationStale: Bool {
        guard let calibration else { return true }
        return calibration.isStale(now: environment.clock.now)
    }

    func refresh() async {
        state = .loading

        microphone = await environment.permissions.microphonePermission()
        notifications = await environment.permissions.notificationPermission()
        availableCapacity = environment.files.availableCapacity()

        do {
            storedNightCount = try await environment.sessions.sessions().count
            unfinishedNightCount = try await environment.sessions.unfinishedSessions().count
            calibration = try await environment.sessions.latestCalibration()
            state = .ready
        } catch let error as SomnaError {
            Log.ui.error("Status refresh failed: \(String(describing: error), privacy: .public)")
            state = .failed(error)
        } catch {
            state = .failed(.persistenceUnavailable(underlying: String(describing: type(of: error))))
        }
    }

    func requestMicrophoneAccess() async {
        microphone = await environment.permissions.requestMicrophonePermission()
        if microphone.allowsRecording {
            environment.haptics.play(.calibrationFinished)
        }
    }

    func openSystemSettings() {
        environment.permissions.openSystemSettings()
    }
}
