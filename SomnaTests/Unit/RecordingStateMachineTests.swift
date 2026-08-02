import Foundation
import Testing

@testable import Somna

/// The only way to test interruption handling.
///
/// No CI runner produces a phone call, a Siri activation or a media-daemon
/// crash, and no simulator reproduces being backgrounded for eight hours. The
/// rules were extracted into a pure function precisely so the scenarios that
/// lose people's nights can be exercised anyway.
struct RecordingStateMachineTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func run(from state: RecordingState, _ events: [RecordingEvent]) -> RecordingState {
        events.reduce(state) { current, event in
            RecordingStateMachine.next(from: current, on: event) ?? current
        }
    }

    // MARK: - Happy path

    @Test("A normal night runs from idle to a night ready for analysis")
    func nominalSession() {
        let final = run(from: .idle, [
            .start,
            .engineStarted,
            .stopRequested(reason: .userRequested),
            .engineStopped,
        ])

        #expect(final == .stopped(reason: .userRequested))
        #expect(final.resultingSessionStatus == .awaitingAnalysis)
    }

    // MARK: - Interruptions

    @Test("A phone call interrupts and the recording resumes")
    func interruptionAndResume() {
        let final = run(from: .recording, [
            .interruptionBegan(at: start),
            .interruptionEnded(shouldResume: true),
            .engineResumed,
        ])

        #expect(final == .recording)
    }

    /// iOS omits the `shouldResume` hint after long interruptions such as a
    /// phone call, even when resuming would work. Honouring the absent flag
    /// would abandon nights that could have continued.
    @Test("Resuming is attempted even when iOS omits the hint")
    func resumeIsAttemptedWithoutTheHint() {
        let final = run(from: .recording, [
            .interruptionBegan(at: start),
            .interruptionEnded(shouldResume: false),
        ])

        #expect(final == .resuming(since: start))
    }

    /// The gap's real span is what the timeline shows. A twenty-minute call
    /// presented as an instant would make a broken night look intact, which is
    /// the failure this carried date exists to prevent.
    @Test("The interruption instant survives a failed resume")
    func failedResumeKeepsTheOriginalGap() {
        let final = run(from: .recording, [
            .interruptionBegan(at: start),
            .interruptionEnded(shouldResume: true),
            .failure(.engineFailedToStart),
        ])

        #expect(final == .interrupted(since: start))
        #expect(final.interruptedSince == start)
    }

    @Test("A second resume attempt can still succeed after the first fails")
    func resumeCanBeRetried() {
        let final = run(from: .recording, [
            .interruptionBegan(at: start),
            .interruptionEnded(shouldResume: true),
            .failure(.engineFailedToStart),
            .interruptionEnded(shouldResume: true),
            .engineResumed,
        ])

        #expect(final == .recording)
    }

    /// An interrupted night is not a lost night: its segments are on disk and
    /// another notification may still arrive.
    @Test("An interrupted session is still active")
    func interruptedIsStillActive() {
        let state = RecordingState.interrupted(since: start)
        #expect(state.isActive)
        #expect(!state.isCapturing)
        #expect(!state.isTerminal)
    }

    @Test("iOS can interrupt before the engine has finished starting")
    func interruptionDuringStart() {
        let final = run(from: .starting, [.interruptionBegan(at: start)])
        #expect(final == .interrupted(since: start))
    }

    // MARK: - Media services reset

    @Test("A media services reset is handled like an interruption")
    func mediaServicesReset() {
        let final = run(from: .recording, [.mediaServicesReset(at: start)])
        #expect(final == .interrupted(since: start))
    }

    @Test("A reset during a resume keeps the original gap")
    func resetDuringResume() {
        let final = run(from: .recording, [
            .interruptionBegan(at: start),
            .interruptionEnded(shouldResume: true),
            .mediaServicesReset(at: start.addingTimeInterval(60)),
        ])

        #expect(final == .interrupted(since: start))
    }

    // MARK: - Stopping

    @Test("Stopping is possible from any active state")
    func stoppingFromAnyActiveState() {
        let states: [RecordingState] = [
            .starting,
            .recording,
            .interrupted(since: start),
            .resuming(since: start),
        ]

        for state in states {
            let next = RecordingStateMachine.next(from: state, on: .stopRequested(reason: .userRequested))
            #expect(next == .stopping(reason: .userRequested), "Could not stop from \(state)")
        }
    }

    @Test("The stop reason survives to the terminal state")
    func stopReasonIsCarried() {
        let final = run(from: .recording, [
            .stopRequested(reason: .batteryCritical),
            .engineStopped,
        ])

        #expect(final == .stopped(reason: .batteryCritical))
    }

    /// A second stop must not resurrect a finished session — a real risk when
    /// the user taps stop as iOS is already terminating the app.
    @Test("Stopping twice does nothing the second time")
    func stoppingIsIdempotent() {
        let stopped = RecordingState.stopped(reason: .userRequested)
        #expect(RecordingStateMachine.next(from: stopped, on: .stopRequested(reason: .appTerminating)) == nil)
        #expect(RecordingStateMachine.next(from: .idle, on: .stopRequested(reason: .userRequested)) == nil)
    }

    // MARK: - Resulting status

    /// Only a deliberate stop produces a night ready for analysis. Everything
    /// else keeps the audio and lets the user decide, rather than reading as
    /// "your night is gone".
    @Test("Only a user-requested stop marks the night ready for analysis")
    func onlyDeliberateStopsAreClean() {
        #expect(RecordingState.stopped(reason: .userRequested).resultingSessionStatus == .awaitingAnalysis)

        let involuntary: [StopReason] = [
            .batteryCritical, .diskFull, .appTerminating, .interruptionNotResolved,
        ]
        for reason in involuntary {
            #expect(RecordingState.stopped(reason: reason).resultingSessionStatus == .interrupted)
        }

        #expect(RecordingState.failed(.inputUnavailable).resultingSessionStatus == .interrupted)
    }

    // MARK: - Robustness

    /// Audio notifications arrive out of order and in duplicate. Treating every
    /// unexpected one as a failure would end nights that were fine.
    @Test("Unexpected events are ignored rather than treated as failures")
    func unexpectedEventsAreIgnored() {
        #expect(RecordingStateMachine.next(from: .idle, on: .engineStarted) == nil)
        #expect(RecordingStateMachine.next(from: .recording, on: .start) == nil)
        #expect(RecordingStateMachine.next(from: .recording, on: .engineResumed) == nil)
        #expect(RecordingStateMachine.next(from: .idle, on: .interruptionEnded(shouldResume: true)) == nil)
    }

    @Test("Duplicate interruption notifications do not shift the gap start")
    func duplicateInterruptionsKeepTheFirstInstant() {
        let later = start.addingTimeInterval(30)
        let final = run(from: .recording, [
            .interruptionBegan(at: start),
            .interruptionBegan(at: later),
        ])

        // The second is rejected because `interrupted` has no transition for it,
        // so the gap keeps the instant capture actually stopped.
        #expect(final == .interrupted(since: start))
    }

    @Test("A failure while recording ends the session as interrupted, not lost")
    func failureEndsAsInterrupted() {
        let final = run(from: .recording, [.failure(.inputUnavailable)])
        #expect(final == .failed(.inputUnavailable))
        #expect(final.isTerminal)
        #expect(final.resultingSessionStatus == .interrupted)
    }
}

/// Exercises the stub through the same state machine the device uses.
struct StubRecorderTests {

    @Test("A stubbed session walks the real states")
    func stubFollowsTheStateMachine() async throws {
        let clock = FixedClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let recorder = StubAudioRecorder(clock: clock)
        let id = UUID()

        try await recorder.start(sessionID: id, bitRate: AudioConstants.defaultBitRate)
        #expect(await recorder.currentStatus().state == .recording)

        let outcome = try await recorder.stop(reason: .userRequested)
        #expect(outcome.sessionID == id)
        #expect(outcome.stopReason == .userRequested)
        #expect(await recorder.currentStatus().state == .idle)
    }

    @Test("A failing start surfaces the audio error")
    func failingStart() async {
        let recorder = StubAudioRecorder(failure: .inputUnavailable)

        await #expect(throws: AudioError.inputUnavailable) {
            try await recorder.start(sessionID: UUID(), bitRate: AudioConstants.defaultBitRate)
        }
    }
}
