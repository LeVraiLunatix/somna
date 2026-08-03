#if DEBUG
import Foundation
import SwiftData

extension AppEnvironment {

    /// A fully working environment backed by an in-memory store.
    ///
    /// `#if DEBUG` so no preview scaffolding ships in a beta build. Previews get
    /// a real repository rather than a stub, which means a preview exercises the
    /// same mapping and persistence code the app does — previews that lie about
    /// the data layer are how layout bugs reach a device.
    ///
    /// The clock is frozen so "3 hours ago" reads identically on every rebuild.
    static func preview(
        microphone: MicrophonePermission = .granted,
        notifications: NotificationPermission = .granted,
        settings: UserSettings = .default,
        power: Double? = 0.85,
        isCharging: Bool = true
    ) -> AppEnvironment {
        let clock = FixedClock(now: Date(timeIntervalSince1970: 1_800_000_000))

        let files = NightFileStore(
            root: FileManager.default.temporaryDirectory
                .appending(path: "SomnaPreview-\(UUID().uuidString)", directoryHint: .isDirectory)
        )

        let container: ModelContainer
        do {
            container = try ModelContainerFactory.makeContainer(inMemory: true)
        } catch {
            // Previews only. If an in-memory container cannot be built the whole
            // persistence layer is broken, and failing here points at it directly
            // instead of producing a preview full of empty states.
            fatalError("Preview container could not be created: \(error)")
        }

        return AppEnvironment(
            clock: clock,
            permissions: StubPermissionService(microphone: microphone, notifications: notifications),
            sessions: NightSessionRepository(modelContainer: container),
            settings: InMemorySettingsRepository(settings),
            files: files,
            haptics: SilentHapticFeedback(),
            calibration: StubCalibrationService(),
            recorder: StubAudioRecorder(clock: clock),
            power: StubPowerMonitor(level: power, isCharging: isCharging),
            analyser: NightAnalysisEngine(
                files: files,
                classifier: StubSoundClassifier(),
                clock: clock
            )
        )
    }
}
#endif
