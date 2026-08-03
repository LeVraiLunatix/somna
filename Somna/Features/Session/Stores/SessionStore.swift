import Foundation
import OSLog

/// Drives the preparation screen and the running session.
@MainActor
@Observable
final class SessionStore {

    enum Phase: Equatable {
        case preparing
        case starting
        case running
        case stopping
        /// The morning pass, run immediately after the night rather than left
        /// for later: the phone is awake and usually charging at this exact
        /// moment, which is the cheapest it will ever be to do this work.
        case analysing(AnalysisProgress)
        case finished(NightSession)
        case failed(SomnaError)
    }

    /// One item of the pre-flight checklist.
    struct Check: Identifiable, Equatable {
        enum Severity: Equatable {
            /// Recording cannot start.
            case blocking
            /// Recording will work, but worse.
            case advisory
            case satisfied
        }

        let id: String
        let title: String
        let detail: String
        let severity: Severity
    }

    private(set) var phase: Phase = .preparing
    private(set) var status: RecordingStatus = .idle
    private(set) var checks: [Check] = []
    private(set) var estimatedNightSize: Int64 = 0

    private let environment: AppEnvironment
    private var statusTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var canStart: Bool {
        !checks.contains { $0.severity == .blocking } && phase == .preparing
    }

    var isRunning: Bool {
        switch phase {
        case .starting, .running, .stopping: true
        case .preparing, .analysing, .finished, .failed: false
        }
    }

    // MARK: - Pre-flight

    func runPreflight() async {
        let microphone = await environment.permissions.microphonePermission()
        let capacity = environment.files.availableCapacity()
        let power = environment.powerSnapshot()
        let calibration = try? await environment.sessions.latestCalibration()

        estimatedNightSize = AudioConstants.estimatedBytesPerHour * 8

        var items: [Check] = []

        items.append(Check(
            id: "microphone",
            title: String(localized: "session.check.microphone", defaultValue: "Microphone"),
            detail: microphone.allowsRecording
                ? String(localized: "session.check.microphone.ok", defaultValue: "Allowed")
                : String(localized: "session.check.microphone.blocked",
                         defaultValue: "Blocked — allow it in iOS Settings"),
            severity: microphone.allowsRecording ? .satisfied : .blocking
        ))

        let hasRoom = capacity >= AudioConstants.minimumFreeSpaceToRecord
        items.append(Check(
            id: "storage",
            title: String(localized: "session.check.storage", defaultValue: "Free space"),
            detail: hasRoom
                ? String(localized: "session.check.storage.ok",
                         defaultValue: "\(capacity.formattedByteSize) available")
                : String(localized: "session.check.storage.low",
                         defaultValue: "Not enough room for a full night"),
            severity: hasRoom ? .satisfied : .blocking
        ))

        // Advisory, not blocking: someone taking a nap on a 40 % battery is
        // making a reasonable choice, and refusing would be paternalistic.
        items.append(Check(
            id: "power",
            title: String(localized: "session.check.power", defaultValue: "Power"),
            detail: powerDetail(power),
            severity: power.isSafeForOvernightRecording ? .satisfied : .advisory
        ))

        if power.isLowPowerMode {
            items.append(Check(
                id: "lowPowerMode",
                title: String(localized: "session.check.lowPower", defaultValue: "Low Power Mode"),
                detail: String(localized: "session.check.lowPower.detail",
                               defaultValue: "Recording still works, but analysis will wait until you charge."),
                severity: .advisory
            ))
        }

        items.append(Check(
            id: "calibration",
            title: String(localized: "session.check.calibration", defaultValue: "Room calibration"),
            detail: calibration == nil
                ? String(localized: "session.check.calibration.missing",
                         defaultValue: "Not done — detection will be less reliable")
                : String(localized: "session.check.calibration.ok", defaultValue: "Done"),
            severity: calibration == nil ? .advisory : .satisfied
        ))

        items.append(Check(
            id: "placement",
            title: String(localized: "session.check.placement", defaultValue: "Placement"),
            detail: String(localized: "session.check.placement.detail",
                           defaultValue: "On a stable surface, within a metre of the bed, microphone clear."),
            severity: .advisory
        ))

        checks = items
    }

    private func powerDetail(_ power: PowerState) -> String {
        if power.isCharging {
            return String(localized: "session.check.power.charging", defaultValue: "Charging")
        }
        guard let level = power.level else {
            return String(localized: "session.check.power.unknown", defaultValue: "Unknown")
        }
        // The percentage is formatted first so the catalogue entry never has to
        // carry a literal `%`, which a format string would need escaped as `%%`
        // — a trap that only shows up at runtime, in one language.
        let percent = level.formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "session.check.power.unplugged",
                      defaultValue: "\(percent) and not charging — plug in for a full night")
    }

    // MARK: - Running

    func start() async {
        guard canStart else { return }
        phase = .starting

        let useCase = StartNightSessionUseCase(
            sessions: environment.sessions,
            recorder: environment.recorder,
            files: environment.files,
            settings: environment.settings,
            clock: environment.clock
        )

        do {
            _ = try await useCase()
            environment.haptics.play(.sessionStarted)
            phase = .running
            observeStatus()
        } catch let error as SomnaError {
            environment.haptics.play(.errorOccurred)
            phase = .failed(error)
        } catch let error as AudioError {
            environment.haptics.play(.errorOccurred)
            // Audio failures are shown with their own wording, which is more
            // specific than anything the generic error type could say.
            Log.audio.error("Session start failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(.microphoneAccessDenied)
        } catch {
            phase = .failed(.persistenceUnavailable(underlying: String(describing: type(of: error))))
        }
    }

    func stop(reason: StopReason = .userRequested) async {
        guard isRunning else { return }
        phase = .stopping
        statusTask?.cancel()

        let useCase = StopNightSessionUseCase(
            sessions: environment.sessions,
            recorder: environment.recorder,
            clock: environment.clock
        )

        do {
            let session = try await useCase(reason: reason)
            environment.haptics.play(.sessionStopped)
            await analyse(session)
        } catch let error as SomnaError {
            phase = .failed(error)
        } catch {
            phase = .failed(.persistenceUnavailable(underlying: String(describing: type(of: error))))
        }
    }

    /// Runs the morning pass and lands on the finished night.
    ///
    /// A failure here does **not** become a failed screen: the recording is
    /// intact, the night is saved, and the analysis can be retried from the
    /// night's own page. Showing an error would suggest the night was lost.
    private func analyse(_ session: NightSession) async {
        guard session.isAnalysable else {
            phase = .finished(session)
            return
        }

        phase = .analysing(.starting)

        let useCase = AnalyzeNightUseCase(
            sessions: environment.sessions,
            analyser: environment.analyser,
            settings: environment.settings,
            notifications: environment.notifications,
            clock: environment.clock
        )

        do {
            let analysed = try await useCase(sessionID: session.id) { progress in
                Task { @MainActor [weak self] in
                    if case .analysing = self?.phase { self?.phase = .analysing(progress) }
                }
            }
            phase = .finished(analysed)
        } catch {
            Log.analysis.error("Post-session analysis failed; the night is kept as recorded")
            phase = .finished(session)
        }
    }

    /// Mirrors the engine's status into the view.
    ///
    /// `[weak self]` rather than a `deinit` that cancels: a `deinit` cannot touch
    /// main-actor state, and a strong capture would keep the store alive for the
    /// whole night even after its screen is gone. Weak capture ends the loop the
    /// moment nothing is watching.
    private func observeStatus() {
        statusTask?.cancel()
        let recorder = environment.recorder

        statusTask = Task { [weak self] in
            for await update in await recorder.statusStream() {
                guard let self, !Task.isCancelled else { return }
                self.status = update
            }
        }
    }
}

private extension AppEnvironment {
    /// Reads the battery without making every caller hop to the main actor.
    @MainActor
    func powerSnapshot() -> PowerState {
        power.snapshot()
    }
}
