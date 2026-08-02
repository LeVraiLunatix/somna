import Foundation

/// A recorder that writes nothing, for previews and tests.
///
/// It still walks the real state machine rather than jumping straight to
/// `recording`, so a preview of the session screen shows the same sequence a
/// device does — and so a store that mishandles `starting` fails in a preview
/// rather than at 23:40 on someone's first night.
actor StubAudioRecorder: AudioRecording {

    private var state: RecordingState = .idle
    private var sessionID: UUID?
    private var startDate: Date?
    private var continuation: AsyncStream<RecordingStatus>.Continuation?

    private let clock: any Clocking
    /// Set to make `start` fail, so error paths can be exercised.
    private let failure: AudioError?

    init(clock: any Clocking = SystemClock(), failure: AudioError? = nil) {
        self.clock = clock
        self.failure = failure
    }

    func currentStatus() -> RecordingStatus {
        RecordingStatus(
            state: state,
            recordedDuration: elapsed,
            level: state.isCapturing ? 0.12 : 0,
            segmentCount: 0,
            bytesWritten: 0
        )
    }

    func statusStream() -> AsyncStream<RecordingStatus> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(currentStatus())
        }
    }

    func start(sessionID: UUID, bitRate: Int) async throws {
        guard state == .idle else { return }

        self.sessionID = sessionID
        startDate = clock.now
        transition(.start)

        if let failure {
            transition(.failure(failure))
            throw failure
        }

        transition(.engineStarted)
    }

    func stop(reason: StopReason) async throws -> RecordingOutcome {
        guard let sessionID, let startDate else { throw AudioError.engineFailedToStart }

        transition(.stopRequested(reason: reason))
        transition(.engineStopped)

        let outcome = RecordingOutcome(
            sessionID: sessionID,
            startDate: startDate,
            endDate: clock.now,
            recordedDuration: elapsed,
            segments: [],
            gaps: [],
            stopReason: reason
        )

        state = .idle
        self.sessionID = nil
        self.startDate = nil
        continuation?.yield(currentStatus())

        return outcome
    }

    /// Drives an interruption from a test, since no simulator produces one.
    func simulate(_ event: RecordingEvent) {
        transition(event)
    }

    private var elapsed: TimeInterval {
        guard let startDate else { return 0 }
        return max(0, clock.now.timeIntervalSince(startDate))
    }

    private func transition(_ event: RecordingEvent) {
        guard let next = RecordingStateMachine.next(from: state, on: event) else { return }
        state = next
        continuation?.yield(currentStatus())
    }
}
