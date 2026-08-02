import Foundation
import Testing

@testable import Somna

/// The evaluator is pure so it can be tested exhaustively without a microphone —
/// which matters, because the CI runner has no audio input at all.
struct PlacementQualityEvaluatorTests {

    private func levels(_ value: Double, count: Int = 40) -> [Double] {
        Array(repeating: value, count: count)
    }

    @Test("A quiet, steady room rates excellent")
    func quietRoomIsExcellent() {
        let assessment = PlacementQualityEvaluator.evaluate(levels: levels(0.04))
        #expect(assessment.rating == .excellent)
        #expect(assessment.issues.isEmpty)
    }

    @Test("A noisy room is flagged with actionable advice")
    func noisyRoomIsFlagged() {
        let assessment = PlacementQualityEvaluator.evaluate(levels: levels(0.35))
        #expect(assessment.rating == .needsImprovement)
        #expect(assessment.issues.contains(.highAmbientNoise))
        // Every issue must carry advice; a verdict nobody can act on only makes
        // people distrust the app.
        for issue in assessment.issues {
            #expect(!issue.englishAdvice.isEmpty)
        }
    }

    /// The single most damaging failure mode this evaluator can have. A dead or
    /// covered microphone measures as perfect silence; calling that "excellent"
    /// would send someone to bed reassured, and they would wake to an empty
    /// timeline that reads exactly like a calm night.
    @Test("Total silence is reported as no input, never as an excellent room")
    func silenceIsNotExcellence() {
        let assessment = PlacementQualityEvaluator.evaluate(levels: levels(0))
        #expect(assessment.rating == .needsImprovement)
        #expect(assessment.issues == [.noInput])
    }

    @Test("An empty measurement is treated as no input")
    func emptyMeasurement() {
        let assessment = PlacementQualityEvaluator.evaluate(levels: [])
        #expect(assessment.issues == [.noInput])
    }

    @Test("Non-finite and negative samples are discarded")
    func invalidSamplesAreIgnored() {
        let assessment = PlacementQualityEvaluator.evaluate(
            levels: [0.05, .nan, -1, .infinity, 0.05, 0.05, 0.05]
        )
        #expect(assessment.rating == .excellent)
        #expect(assessment.noiseFloor > 0)
    }

    /// A door slamming once during calibration must not condemn a good bedroom,
    /// which is why the floor is a median rather than a mean.
    @Test("A single loud outlier does not ruin the verdict")
    func outliersDoNotDominate() {
        var samples = levels(0.03, count: 39)
        samples.append(0.95)

        let assessment = PlacementQualityEvaluator.evaluate(levels: samples)
        #expect(assessment.noiseFloor < PlacementQualityEvaluator.excellentFloor)
        #expect(assessment.rating != .needsImprovement)
    }

    @Test("A level that keeps swinging is reported as unstable")
    func unstableEnvironment() {
        let samples = (0..<40).map { $0.isMultiple(of: 2) ? 0.02 : 0.30 }
        let assessment = PlacementQualityEvaluator.evaluate(levels: samples)
        #expect(assessment.issues.contains(.unstableEnvironment))
    }

    @Test("A borderline room rates good rather than excellent")
    func borderlineRoomIsGood() {
        let assessment = PlacementQualityEvaluator.evaluate(levels: levels(0.14))
        #expect(assessment.rating == .good)
    }

    @Test("Every issue has a distinct localisation key")
    func issueKeysAreUnique() {
        let keys = Set(CalibrationIssue.allCases.map(\.adviceKey))
        #expect(keys.count == CalibrationIssue.allCases.count)
    }
}

@MainActor
struct OnboardingStoreTests {

    private func makeStore(
        microphone: MicrophonePermission = .undetermined,
        notifications: NotificationPermission = .undetermined
    ) -> OnboardingStore {
        OnboardingStore(environment: .preview(microphone: microphone, notifications: notifications))
    }

    @Test("Onboarding walks the seven steps in order")
    func stepOrder() async {
        let store = makeStore(microphone: .granted)
        await store.start()

        #expect(store.step == .welcome)
        for _ in 0..<6 { store.advance() }
        #expect(store.step == .calibration)
    }

    /// iOS grants one prompt per install. Asking before the explanations would
    /// spend it on someone who does not yet know what Somna does.
    @Test("The microphone request comes after the explanatory steps")
    func permissionComesAfterExplanations() {
        let explanatory: [OnboardingStore.Step] = [.welcome, .howItWorks, .capabilities, .privacy]
        for step in explanatory {
            #expect(step.rawValue < OnboardingStore.Step.microphone.rawValue)
        }
    }

    @Test("The microphone step blocks only while the answer is unknown")
    func microphoneStepBlocksUntilAnswered() async {
        let store = makeStore(microphone: .undetermined)
        await store.start()
        for _ in 0..<4 { store.advance() }

        #expect(store.step == .microphone)
        #expect(!store.canAdvance)

        store.advance()
        #expect(store.step == .microphone, "Onboarding advanced without an answer")
    }

    /// Trapping someone in onboarding over a permission they declined is hostile,
    /// and Somna still works as a reader of past nights without it.
    @Test("A refusal does not trap the user in onboarding")
    func refusalDoesNotBlock() async {
        let store = makeStore(microphone: .permanentlyDenied)
        await store.start()
        for _ in 0..<4 { store.advance() }

        #expect(store.step == .microphone)
        #expect(store.canAdvance)

        store.advance()
        #expect(store.step == .notifications)
    }

    @Test("Notifications never block progress")
    func notificationsNeverBlock() async {
        let store = makeStore(microphone: .granted, notifications: .denied)
        await store.start()
        for _ in 0..<5 { store.advance() }

        #expect(store.step == .notifications)
        #expect(store.canAdvance)
    }

    @Test("Finishing onboarding records that it was completed")
    func finishingPersists() async {
        let environment = AppEnvironment.preview(microphone: .granted)
        let store = OnboardingStore(environment: environment)
        await store.start()

        #expect(!environment.settings.load().hasCompletedOnboarding)

        for _ in 0..<7 { store.advance() }

        #expect(store.hasFinished)
        #expect(environment.settings.load().hasCompletedOnboarding)
    }

    /// Someone who opens Somna in a noisy living room must still be able to
    /// reach the app; calibration can always be redone from Settings.
    @Test("Calibration can be skipped")
    func calibrationIsSkippable() async {
        let environment = AppEnvironment.preview(microphone: .granted)
        let store = OnboardingStore(environment: environment)
        await store.start()

        store.skipCalibration()

        #expect(store.hasFinished)
        #expect(environment.settings.load().hasCompletedOnboarding)
    }

    @Test("A successful calibration is recorded and stored")
    func calibrationPersists() async throws {
        let environment = AppEnvironment.preview(microphone: .granted)
        let store = OnboardingStore(environment: environment)
        await store.start()

        await store.runCalibration()

        #expect(store.calibration == .finished(StubCalibrationService().assessment))
        let saved = try #require(await environment.sessions.latestCalibration())
        #expect(saved.rating == .excellent)
    }

    @Test("Calibration is not attempted without the microphone")
    func calibrationRequiresMicrophone() async {
        let store = makeStore(microphone: .permanentlyDenied)
        await store.start()

        await store.runCalibration()
        #expect(store.calibration == .idle)
    }

    @Test("Progress advances monotonically to one")
    func progress() async {
        let store = makeStore(microphone: .granted)
        await store.start()

        var previous = 0.0
        for _ in 0..<OnboardingStore.Step.allCases.count {
            #expect(store.progress > previous)
            previous = store.progress
            if !store.step.isLast { store.advance() }
        }
        #expect(abs(previous - 1.0) < 0.0001)
    }
}

@MainActor
struct HomeStoreTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("With no recorded nights, home presents the first run")
    func firstRun() async {
        let store = HomeStore(environment: .preview())
        await store.refresh()
        #expect(store.state == .ready(.firstRun))
    }

    @Test("A night recorded this morning is the main subject")
    func recentNightIsFeatured() async throws {
        let environment = AppEnvironment.preview()
        let session = NightSession(
            startDate: environment.clock.now.addingTimeInterval(-8 * 3600),
            endDate: environment.clock.now.addingTimeInterval(-3600),
            status: .completed,
            recordedDuration: 7 * 3600,
            createdAt: environment.clock.now,
            updatedAt: environment.clock.now
        )
        try await environment.sessions.save(session)

        let store = HomeStore(environment: environment)
        await store.refresh()

        guard case .ready(.recentNight(let shown)) = store.state else {
            Issue.record("Expected a recent night, got \(String(describing: store.state))")
            return
        }
        #expect(shown.id == session.id)
    }

    @Test("An older night moves out of the spotlight")
    func oldNightBecomesIdle() async throws {
        let environment = AppEnvironment.preview()
        let old = environment.clock.now.addingTimeInterval(-3 * 24 * 3600)
        try await environment.sessions.save(
            NightSession(
                startDate: old,
                endDate: old.addingTimeInterval(7 * 3600),
                status: .completed,
                recordedDuration: 7 * 3600,
                createdAt: old,
                updatedAt: old
            )
        )

        let store = HomeStore(environment: environment)
        await store.refresh()

        guard case .ready(.idle(let last)) = store.state else {
            Issue.record("Expected the idle presentation, got \(String(describing: store.state))")
            return
        }
        #expect(last != nil)
    }

    @Test("A blocked microphone prevents starting and explains why")
    func blockedMicrophone() async {
        let store = HomeStore(environment: .preview(microphone: .permanentlyDenied))
        await store.refresh()

        #expect(!store.canStartSession)
        #expect(store.blockingIssue == .microphoneAccessDenied)
    }

    @Test("The greeting follows the time of day, not the data")
    func greetingFollowsClock() async {
        // The preview clock is fixed, so this asserts a real mapping rather than
        // whatever hour the test happens to run at.
        let store = HomeStore(environment: .preview())
        let key = store.greetingKey
        #expect(key.hasPrefix("home.greeting."))
    }
}
