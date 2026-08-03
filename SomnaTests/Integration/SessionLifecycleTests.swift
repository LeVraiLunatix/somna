import Foundation
import Testing

@testable import Somna

/// Exercises starting, stopping and recovering a night against the real
/// repository and a real temporary file store.
struct SessionLifecycleTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeEnvironment(failure: AudioError? = nil) -> (AppEnvironment, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SomnaLifecycle-\(UUID().uuidString)", directoryHint: .isDirectory)
        let base = AppEnvironment.preview()
        let environment = base.replacing(
            files: NightFileStore(root: root),
            recorder: StubAudioRecorder(clock: base.clock, failure: failure)
        )
        return (environment, root)
    }

    private func startUseCase(_ environment: AppEnvironment) -> StartNightSessionUseCase {
        StartNightSessionUseCase(
            sessions: environment.sessions,
            recorder: environment.recorder,
            files: environment.files,
            settings: environment.settings,
            clock: environment.clock
        )
    }

    @Test("Starting a night writes the row before any audio exists")
    func startPersistsSession() async throws {
        let (environment, root) = makeEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try await startUseCase(environment)()

        let stored = try #require(await environment.sessions.session(id: session.id))
        #expect(stored.status == .recording)
        #expect(stored.endDate == nil)
    }

    /// If the engine cannot start there is nothing to recover, so an empty night
    /// must not be left in the user's history.
    @Test("A failed start leaves no session and no files behind")
    func failedStartCleansUp() async throws {
        let (environment, root) = makeEnvironment(failure: .inputUnavailable)
        defer { try? FileManager.default.removeItem(at: root) }

        await #expect(throws: AudioError.inputUnavailable) {
            _ = try await startUseCase(environment)()
        }

        let sessions = try await environment.sessions.sessions()
        #expect(sessions.isEmpty)
    }

    @Test("Stopping records the duration and the segments")
    func stopPersistsOutcome() async throws {
        let (environment, root) = makeEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try await startUseCase(environment)()

        let stopUseCase = StopNightSessionUseCase(
            sessions: environment.sessions,
            recorder: environment.recorder,
            clock: environment.clock
        )
        let stopped = try await stopUseCase(reason: .userRequested)

        #expect(stopped.id == session.id)
        #expect(stopped.endDate != nil)
    }

    /// Five minutes cannot support any statement about a night. Producing a
    /// report anyway would be exactly the false precision this app avoids.
    @Test("A night too short to analyse is marked interrupted, not ready")
    func shortNightIsNotAnalysable() async throws {
        let (environment, root) = makeEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }

        // The stub's clock is frozen, so the recorded duration is zero.
        _ = try await startUseCase(environment)()

        let stopped = try await StopNightSessionUseCase(
            sessions: environment.sessions,
            recorder: environment.recorder,
            clock: environment.clock
        )(reason: .userRequested)

        #expect(!stopped.isAnalysable)
        #expect(stopped.status == .interrupted)
    }

    @Test("An involuntary stop never marks a night ready for analysis")
    func involuntaryStopIsInterrupted() async throws {
        let (environment, root) = makeEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await startUseCase(environment)()

        let stopped = try await StopNightSessionUseCase(
            sessions: environment.sessions,
            recorder: environment.recorder,
            clock: environment.clock
        )(reason: .batteryCritical)

        #expect(stopped.status == .interrupted)
    }
}

/// Recovery is what stands between a crash and a lost night.
struct RecoveryTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeEnvironment() -> (AppEnvironment, NightFileStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SomnaRecovery-\(UUID().uuidString)", directoryHint: .isDirectory)
        let files = NightFileStore(root: root)
        let environment = AppEnvironment.preview().replacing(files: files)
        return (environment, files, root)
    }

    private func useCase(_ environment: AppEnvironment) -> RecoverInterruptedSessionsUseCase {
        RecoverInterruptedSessionsUseCase(
            sessions: environment.sessions,
            files: environment.files,
            clock: environment.clock
        )
    }

    /// A row stuck in `recording` looks like a night that is still going,
    /// forever. The user has no way to know it needs fixing.
    @Test("A night the app died inside is reconciled from its manifest")
    func crashedNightIsRecovered() async throws {
        let (environment, files, root) = makeEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = NightSession(
            startDate: start,
            status: .recording,
            createdAt: start,
            updatedAt: start
        )
        try await environment.sessions.save(session)
        try files.prepareDirectories(for: session.id)

        let segment = AudioSegment(
            sessionID: session.id,
            fileName: "seg-000.m4a",
            startDate: start,
            endDate: start.addingTimeInterval(600),
            fileSize: 2_400_000,
            processingState: .ready
        )
        try NightManifest(
            sessionID: session.id,
            startDate: start,
            endDate: nil,
            recordedDuration: 600,
            segments: [segment],
            gaps: [],
            stopReason: nil
        ).write(using: files)

        let recovered = try await useCase(environment)()

        #expect(recovered.count == 1)
        let stored = try #require(await environment.sessions.session(id: session.id))
        #expect(stored.status == .interrupted)
        #expect(stored.recordedDuration == 600)
        // The segment comes back from the manifest, so the audio is reachable
        // from the app rather than sitting on disk unreferenced.
        let segments = try await environment.sessions.segments(for: session.id)
        #expect(segments.count == 1)
        #expect(segments.first?.fileName == "seg-000.m4a")
    }

    @Test("A crashed night with no manifest is still marked interrupted")
    func recoveryWithoutManifest() async throws {
        let (environment, _, root) = makeEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = NightSession(
            startDate: start,
            status: .recording,
            createdAt: start,
            updatedAt: start
        )
        try await environment.sessions.save(session)

        _ = try await useCase(environment)()

        let stored = try #require(await environment.sessions.session(id: session.id))
        #expect(stored.status == .interrupted)
    }

    @Test("Completed nights are left alone")
    func completedNightsAreUntouched() async throws {
        let (environment, _, root) = makeEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = NightSession(
            startDate: start,
            endDate: start.addingTimeInterval(8 * 3600),
            status: .completed,
            recordedDuration: 8 * 3600,
            createdAt: start,
            updatedAt: start
        )
        try await environment.sessions.save(session)

        let recovered = try await useCase(environment)()

        #expect(recovered.isEmpty)
        #expect(try await environment.sessions.session(id: session.id)?.status == .completed)
    }

    /// Directories nothing references occupy space while being invisible from
    /// every screen — the hardest kind of storage growth to diagnose.
    @Test("Orphaned directories are removed")
    func orphansAreRemoved() async throws {
        let (environment, files, root) = makeEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }

        let orphan = UUID()
        try files.prepareDirectories(for: orphan)
        #expect(FileManager.default.fileExists(atPath: files.sessionDirectory(for: orphan).path(percentEncoded: false)))

        _ = try await useCase(environment)()

        #expect(!FileManager.default.fileExists(atPath: files.sessionDirectory(for: orphan).path(percentEncoded: false)))
    }

    /// A `.part` file is a segment that was being written when the app died. Its
    /// content is truncated, so analysing it would produce events from audio
    /// that was never fully encoded.
    @Test("Truncated segments are deleted rather than analysed")
    func partFilesAreRemoved() async throws {
        let (environment, files, root) = makeEnvironment()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = NightSession(
            startDate: start,
            status: .recording,
            createdAt: start,
            updatedAt: start
        )
        try await environment.sessions.save(session)
        try files.prepareDirectories(for: session.id)

        let truncated = files.segmentURL(for: session.id, fileName: "seg-003.m4a.part")
        try Data("half a segment".utf8).write(to: truncated)

        _ = try await useCase(environment)()

        #expect(files.incompleteSegmentFiles(for: session.id).isEmpty)
    }
}

@MainActor
struct SessionStoreTests {

    @Test("The checklist blocks on a missing microphone")
    func microphoneBlocks() async {
        let store = SessionStore(environment: .preview(microphone: .permanentlyDenied))
        await store.runPreflight()

        #expect(!store.canStart)
        #expect(store.checks.contains { $0.id == "microphone" && $0.severity == .blocking })
    }

    /// Someone taking a nap on a 40 % battery is making a reasonable choice.
    /// Refusing would be paternalistic, so low power advises rather than blocks.
    @Test("An unplugged phone warns but does not block")
    func batteryAdvisesOnly() async {
        let store = SessionStore(environment: .preview(power: 0.22, isCharging: false))
        await store.runPreflight()

        #expect(store.canStart)
        #expect(store.checks.contains { $0.id == "power" && $0.severity == .advisory })
    }

    @Test("A charged, permitted phone can start")
    func nominalPreflight() async {
        let store = SessionStore(environment: .preview())
        await store.runPreflight()

        #expect(store.canStart)
        #expect(!store.checks.contains { $0.severity == .blocking })
    }

    @Test("A missing calibration advises rather than blocks")
    func calibrationAdvises() async {
        let store = SessionStore(environment: .preview())
        await store.runPreflight()

        #expect(store.checks.contains { $0.id == "calibration" && $0.severity == .advisory })
    }

    @Test("Starting a session moves the store into the running phase")
    func startRuns() async {
        let store = SessionStore(environment: .preview())
        await store.runPreflight()
        await store.start()

        #expect(store.phase == .running)
        #expect(store.isRunning)
    }

    @Test("A session cannot start while a check is blocking")
    func blockedStartDoesNothing() async {
        let store = SessionStore(environment: .preview(microphone: .permanentlyDenied))
        await store.runPreflight()
        await store.start()

        #expect(store.phase == .preparing)
    }
}
