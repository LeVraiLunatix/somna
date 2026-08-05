import Foundation
import Testing

@testable import Somna

/// A recorder that is recording must keep saying so.
///
/// This is the contract both recorders owe the session screen, and the one the
/// real engine broke: it published status only from its state machine, so a
/// single status went out when recording began and then nothing. The clock, the
/// level meter and the size on screen sat frozen at their first values for the
/// whole night, which reads as an app that has stopped working — and on a first
/// night, with no report yet to prove otherwise, there is nothing to contradict
/// that reading.
///
/// Exercised against `StubAudioRecorder`, since the real engine needs a
/// microphone. It guards the contract, not `AudioRecordingEngine`'s
/// implementation of it — but the stub had the same defect, for the same reason,
/// and a preview of the session screen was frozen too.
@Suite("Recording status publishing")
struct RecordingStatusPublishingTests {

    @Test("A running recorder publishes more than its first status", .timeLimit(.minutes(1)))
    func keepsPublishingWhileRecording() async throws {
        let recorder = StubAudioRecorder()
        var statuses = await recorder.statusStream().makeAsyncIterator()

        try await recorder.start(sessionID: UUID(), bitRate: AudioConstants.defaultBitRate)

        // Drain until one arrives that is actually capturing, so the assertion
        // is about the recording state rather than the transitions into it.
        var recording: RecordingStatus?
        while let status = await statuses.next() {
            if status.state.isCapturing { recording = status; break }
        }
        let first = try #require(recording, "the recorder never reported capturing")

        // The next one is not a transition: nothing changes state here. It can
        // only arrive if the recorder reports while it records.
        let second = try #require(await statuses.next())

        #expect(second.state.isCapturing)
        #expect(second.recordedDuration > first.recordedDuration,
                "the clock on the session screen would not move")

        _ = try await recorder.stop(reason: .userRequested)
    }

    /// The cadence is a battery decision, not an arbitrary constant: this runs
    /// for eight hours on a phone that has to last the night.
    @Test("The publish interval matches what the screen can show")
    func publishIntervalMatchesDisplayGranularity() {
        // The running clock reads `m:ss`, so anything faster than 1 Hz wakes the
        // main actor to redraw a digit that cannot have changed.
        #expect(AudioConstants.statusPublishInterval == 1)
        #expect(TimeInterval(59).formattedCompactDuration == "0:59")
        #expect(TimeInterval(60).formattedCompactDuration == "1:00")
    }
}
