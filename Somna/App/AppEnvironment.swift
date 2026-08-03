import SwiftData
import SwiftUI

/// The single injection point.
///
/// Every dependency in Somna is reached through this struct, typed by protocol.
/// There is no `.shared` anywhere in the project, which is what makes previews
/// cheap, tests hermetic, and the dependency graph readable in one file rather
/// than discovered by grep.
struct AppEnvironment: Sendable {
    let clock: any Clocking
    let permissions: any PermissionRequesting
    let sessions: any NightSessionRepositing
    let settings: any SettingsStoring
    let files: any NightFileStoring
    let haptics: any HapticFeedbacking
    let calibration: any CalibrationMeasuring
    let recorder: any AudioRecording
    let power: any PowerMonitoring
    let analyser: any NightAnalyzing
    let storage: any StorageManaging
    let notifications: any NotificationScheduling
}

extension AppEnvironment {

    /// Wires the real implementations. Called once, from `SomnaApp`.
    static func live(modelContainer: ModelContainer) -> AppEnvironment {
        AppEnvironment(
            clock: SystemClock(),
            permissions: PermissionService(),
            sessions: NightSessionRepository(modelContainer: modelContainer),
            settings: SettingsRepository(),
            files: NightFileStore(),
            haptics: LiveHapticFeedback(),
            calibration: CalibrationService(),
            recorder: AudioRecordingEngine(files: NightFileStore(), clock: SystemClock()),
            power: DevicePowerMonitor(),
            analyser: NightAnalysisEngine(
                files: NightFileStore(),
                classifier: SoundAnalysisClassifier(),
                clock: SystemClock()
            ),
            storage: StorageService(
                sessions: NightSessionRepository(modelContainer: modelContainer),
                files: NightFileStore()
            ),
            notifications: NotificationService()
        )
    }
}

extension EnvironmentValues {
    /// Always overridden at the root. The default exists only so SwiftUI can
    /// build the environment; see ``AppEnvironment/unconfigured``.
    @Entry var somna: AppEnvironment = .unconfigured
}

extension AppEnvironment {

    /// The default value SwiftUI uses before the root injects the real one.
    ///
    /// Its repository **throws** rather than returning empty results. An empty
    /// history is a plausible-looking answer, and a preview or a stray view that
    /// silently shows "no nights yet" would hide the missing injection until
    /// someone wondered where their data went. An error surfaces it immediately,
    /// in the error state the screen already has to handle, without crashing.
    static let unconfigured = AppEnvironment(
        clock: SystemClock(),
        permissions: StubPermissionService(microphone: .undetermined, notifications: .undetermined),
        sessions: UnconfiguredSessionRepository(),
        settings: InMemorySettingsRepository(),
        files: NightFileStore(root: FileManager.default.temporaryDirectory
            .appending(path: "SomnaUnconfigured", directoryHint: .isDirectory)),
        haptics: SilentHapticFeedback(),
        calibration: StubCalibrationService(),
        recorder: StubAudioRecorder(),
        power: StubPowerMonitor(),
        analyser: NightAnalysisEngine(
            files: NightFileStore(root: FileManager.default.temporaryDirectory
                .appending(path: "SomnaUnconfigured", directoryHint: .isDirectory)),
            classifier: StubSoundClassifier(),
            clock: SystemClock()
        ),
        storage: StorageService(
            sessions: UnconfiguredSessionRepository(),
            files: NightFileStore(root: FileManager.default.temporaryDirectory
                .appending(path: "SomnaUnconfigured", directoryHint: .isDirectory))
        ),
        notifications: StubNotificationService()
    )
}

/// Fails loudly instead of pretending there is no data.
private struct UnconfiguredSessionRepository: NightSessionRepositing {

    private var failure: SomnaError {
        .environmentNotConfigured(component: "NightSessionRepositing")
    }

    func sessions(limit: Int?, offset: Int) async throws -> [NightSession] { throw failure }
    func session(id: UUID) async throws -> NightSession? { throw failure }
    func mostRecentSession() async throws -> NightSession? { throw failure }
    func unfinishedSessions() async throws -> [NightSession] { throw failure }
    func save(_ session: NightSession) async throws { throw failure }
    func deleteSession(id: UUID) async throws { throw failure }
    func deleteAllSessions() async throws { throw failure }
    func events(for sessionID: UUID) async throws -> [NightEvent] { throw failure }
    func replaceEvents(_ events: [NightEvent], for sessionID: UUID) async throws { throw failure }
    func updateEvent(_ event: NightEvent) async throws { throw failure }
    func segments(for sessionID: UUID) async throws -> [AudioSegment] { throw failure }
    func save(_ segment: AudioSegment) async throws { throw failure }
    func latestCalibration() async throws -> CalibrationProfile? { throw failure }
    func save(_ calibration: CalibrationProfile) async throws { throw failure }
}
