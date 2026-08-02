import Foundation

/// Live view of a running session, for the session screen.
struct RecordingStatus: Equatable, Sendable {
    let state: RecordingState
    /// Audio actually captured, excluding interruptions.
    let recordedDuration: TimeInterval
    /// Current input level, 0–1, for the meter.
    let level: Float
    let segmentCount: Int
    let bytesWritten: Int64

    static let idle = RecordingStatus(
        state: .idle,
        recordedDuration: 0,
        level: 0,
        segmentCount: 0,
        bytesWritten: 0
    )
}

/// What a finished session produced.
struct RecordingOutcome: Equatable, Sendable {
    let sessionID: UUID
    let startDate: Date
    let endDate: Date
    let recordedDuration: TimeInterval
    let segments: [AudioSegment]
    /// Interruptions, so the timeline can show the gaps rather than hide them.
    let gaps: [RecordingGap]
    let stopReason: StopReason
}

/// A stretch where nothing was captured.
struct RecordingGap: Equatable, Sendable, Codable {
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// The audio engine, as the rest of the app sees it.
protocol AudioRecording: Sendable {
    func start(sessionID: UUID, bitRate: Int) async throws
    func stop(reason: StopReason) async throws -> RecordingOutcome
    func currentStatus() async -> RecordingStatus
    /// Emits on every meaningful change. One consumer at a time — the session screen.
    func statusStream() async -> AsyncStream<RecordingStatus>
}
