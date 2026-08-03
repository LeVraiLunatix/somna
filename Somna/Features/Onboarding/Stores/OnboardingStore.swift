import Foundation
import OSLog

/// Drives the onboarding sequence.
@MainActor
@Observable
final class OnboardingStore {

    /// The seven steps, in order.
    ///
    /// Permission requests come *after* the explanations on purpose. iOS grants
    /// exactly one prompt per permission per install; spending it before someone
    /// understands what Somna does is how recording apps end up permanently
    /// denied by people who would have said yes.
    enum Step: Int, CaseIterable, Sendable {
        case welcome
        case howItWorks
        case capabilities
        case privacy
        case microphone
        case notifications
        case calibration

        var isLast: Bool { self == .calibration }
    }

    enum CalibrationState: Equatable {
        case idle
        case measuring
        case finished(CalibrationAssessment)
        case failed(AudioError)
    }

    private(set) var step: Step = .welcome
    private(set) var microphone: MicrophonePermission = .undetermined
    private(set) var notifications: NotificationPermission = .undetermined
    private(set) var calibration: CalibrationState = .idle
    private(set) var isRequestingPermission = false

    /// Set when onboarding is complete; the root view watches it.
    private(set) var hasFinished = false

    private let environment: AppEnvironment
    private let appSettings: AppSettings

    init(environment: AppEnvironment, appSettings: AppSettings) {
        self.environment = environment
        self.appSettings = appSettings
    }

    var progress: Double {
        Double(step.rawValue + 1) / Double(Step.allCases.count)
    }

    /// Whether the current step allows moving on.
    ///
    /// Only the microphone step can block, and only while the answer is still
    /// unknown. A refusal does not block: Somna explains what will not work and
    /// lets the person continue, because trapping someone in onboarding over a
    /// permission they declined is hostile.
    var canAdvance: Bool {
        switch step {
        case .microphone: microphone != .undetermined
        case .calibration: calibration != .measuring
        default: true
        }
    }

    // MARK: - Navigation

    func start() async {
        microphone = await environment.permissions.microphonePermission()
        notifications = await environment.permissions.notificationPermission()
    }

    func advance() {
        guard canAdvance else { return }

        if step.isLast {
            finish()
            return
        }

        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Leaves onboarding without calibrating.
    ///
    /// Calibration can always be redone from Settings, and forcing it here would
    /// mean someone who opened Somna in a noisy living room could never reach the
    /// app at all.
    func skipCalibration() {
        finish()
    }

    /// Routed through `AppSettings` rather than written straight to the
    /// repository: the root view observes that store, and a direct write would
    /// leave someone staring at the last onboarding screen after finishing it.
    private func finish() {
        appSettings.markOnboardingComplete()
        hasFinished = true
    }

    // MARK: - Permissions

    func requestMicrophone() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        microphone = await environment.permissions.requestMicrophonePermission()
    }

    func requestNotifications() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        notifications = await environment.permissions.requestNotificationPermission()
    }

    func openSystemSettings() {
        environment.permissions.openSystemSettings()
    }

    // MARK: - Calibration

    /// How long the room is measured. Long enough to see a fan cycle, short
    /// enough that nobody abandons onboarding waiting for it.
    static let calibrationDuration: TimeInterval = 15

    func runCalibration() async {
        guard microphone.allowsRecording else { return }
        calibration = .measuring

        do {
            let assessment = try await environment.calibration.measure(
                duration: Self.calibrationDuration
            )
            calibration = .finished(assessment)
            environment.haptics.play(.calibrationFinished)
            await persist(assessment)
        } catch let error as AudioError {
            Log.audio.error("Calibration failed: \(error.localizedDescription, privacy: .public)")
            calibration = .failed(error)
            environment.haptics.play(.errorOccurred)
        } catch {
            calibration = .failed(.engineFailedToStart)
            environment.haptics.play(.errorOccurred)
        }
    }

    private func persist(_ assessment: CalibrationAssessment) async {
        let profile = CalibrationProfile(
            ambientNoiseFloor: assessment.noiseFloor,
            noiseVariability: assessment.variability,
            placement: .nightstand,
            rating: assessment.rating,
            createdAt: environment.clock.now
        )

        do {
            try await environment.sessions.save(profile)
        } catch {
            // Non-fatal: the measurement can be redone from Settings, and losing
            // it must not prevent someone from finishing onboarding.
            Log.persistence.error("Calibration profile could not be saved")
        }
    }
}
